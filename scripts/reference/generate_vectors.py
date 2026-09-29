#!/usr/bin/env python3
"""生成不依赖 BinSchema 实现的最小二进制参考向量。"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import ipaddress
import struct
from pathlib import Path


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    """按 PNG 规范组装一个带 CRC 的 chunk。"""
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
    )


def make_png() -> bytes:
    # IDAT 是一个 1x1、8-bit 灰度图像的固定 zlib 流，避免依赖 zlib 版本。
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0)
    idat = bytes.fromhex("789c6360000000020001")
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", idat)
        + png_chunk(b"IEND", b"")
    )


def make_wav() -> bytes:
    samples = bytes((0x00, 0x40, 0x80, 0xFF))
    fmt = struct.pack("<HHIIHH", 1, 1, 8_000, 8_000, 1, 8)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt
    body += b"data" + struct.pack("<I", len(samples)) + samples
    return b"RIFF" + struct.pack("<I", len(body)) + body


def make_dns() -> bytes:
    question = b"\x07example\x03com\x00" + struct.pack(">HH", 1, 1)
    return struct.pack(">HHHHHH", 0xC0DE, 0x0100, 1, 0, 0, 0) + question


def internet_checksum(payload: bytes) -> int:
    """计算 IPv4 头使用的 16-bit one's-complement checksum。"""
    if len(payload) % 2:
        payload += b"\x00"
    total = sum(struct.unpack(f">{len(payload) // 2}H", payload))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def make_pcap(dns: bytes) -> bytes:
    udp = struct.pack(">HHHH", 53_000, 53, 8 + len(dns), 0) + dns
    source = ipaddress.IPv4Address("192.0.2.1").packed
    destination = ipaddress.IPv4Address("198.51.100.53").packed
    ip_header = struct.pack(
        ">BBHHHBBH4s4s",
        0x45,
        0,
        20 + len(udp),
        0x1234,
        0,
        64,
        17,
        0,
        source,
        destination,
    )
    checksum = internet_checksum(ip_header)
    ip_header = ip_header[:10] + struct.pack(">H", checksum) + ip_header[12:]
    ethernet = bytes.fromhex("0200000000020200000000010800")
    packet = ethernet + ip_header + udp
    global_header = struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65_535, 1)
    packet_header = struct.pack("<IIII", 1_700_000_000, 123_456, len(packet), len(packet))
    return global_header + packet_header + packet


def make_bmff() -> bytes:
    payload = b"isom" + struct.pack(">I", 0x200) + b"isomiso2"
    return struct.pack(">I4s", 8 + len(payload), b"ftyp") + payload


def make_elf() -> bytes:
    # ELF64 little-endian relocatable，含 .text 与 .shstrtab 两个具名 section。
    ident = b"\x7fELF\x02\x01\x01" + b"\x00" * 9
    header = ident + struct.pack(
        "<HHIQQQIHHHHHH",
        1,
        62,
        1,
        0,
        0,
        88,
        0,
        64,
        0,
        0,
        64,
        3,
        2,
    )
    names = b"\x00.text\x00.shstrtab\x00"
    content = header + b"\xc3" + names
    content += b"\x00" * (88 - len(content))
    section = struct.Struct("<IIQQQQIIQQ")
    return (
        content
        + section.pack(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        + section.pack(1, 1, 6, 0, 64, 1, 0, 0, 1, 0)
        + section.pack(7, 3, 0, 0, 65, len(names), 0, 0, 1, 0)
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    dns = make_dns()
    vectors = {
        "reference.png": make_png(),
        "reference.wav": make_wav(),
        "reference.pcap": make_pcap(dns),
        "reference.mp4": make_bmff(),
        "reference.dns": dns,
        "reference.elf": make_elf(),
    }
    for name, payload in vectors.items():
        (args.output / name).write_bytes(payload)
        digest = hashlib.sha256(payload).hexdigest()
        print(f"{digest}  {name}")


if __name__ == "__main__":
    main()
