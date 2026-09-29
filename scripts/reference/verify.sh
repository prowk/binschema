#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output="${RUNNER_TEMP:-/tmp}/binschema-reference-vectors"
rm -rf "$output"
mkdir -p "$output"

python3 "$root/scripts/reference/generate_vectors.py" "$output"
(
  cd "$output"
  sha256sum --check "$root/scripts/reference/SHA256SUMS"
)

# 每个断言都来自独立工具，不复用 BinSchema 的解析或编码实现。
pngcheck -q "$output/reference.png"
soxi "$output/reference.wav" | grep -F "Channels       : 1"
soxi "$output/reference.wav" | grep -F "Sample Rate    : 8000"

tcpdump_output="$(tcpdump -nn -vv -r "$output/reference.pcap" 2>&1)"
printf '%s\n' "$tcpdump_output"
grep -F "192.0.2.1.53000 > 198.51.100.53.53" <<<"$tcpdump_output"
grep -F "A? example.com." <<<"$tcpdump_output"

file -b "$output/reference.mp4" | grep -E "ISO Media|MP4 Base Media"
readelf -h "$output/reference.elf" | grep -F "ELF64"
readelf -h "$output/reference.elf" | grep -F "little endian"
readelf -S "$output/reference.elf" | grep -F ".text"
readelf -S "$output/reference.elf" | grep -F ".shstrtab"

# PCAP 中的 UDP payload 与 reference.dns 完全相同；tcpdump 的问题名输出
# 因此同时提供 DNS wire format 的外部语义验证。
for format in png wav pcap bmff dns elf; do
  extension="$format"
  if [[ "$format" == "bmff" ]]; then
    extension="mp4"
  fi
  moon run --target native cmd/main -- \
    verify "$output/reference.$extension" --format "$format"
done
