# 外部参考验证

BinSchema 的单元测试会检查内部数据模型、错误路径和字节级往返，但编码器与解码器可能共享同一个错误。为降低这种共同失效风险，CI 还会生成一组不调用 BinSchema API 的最小二进制向量，并把同一批文件交给成熟系统工具与 BinSchema CLI 分别验证。

运行方式：

```bash
python3 scripts/reference/generate_vectors.py /tmp/binschema-reference-vectors
bash scripts/reference/verify.sh
```

`verify.sh` 面向 Ubuntu，需要 `python3`、`file`、`binutils`、`pngcheck`、`sox` 与 `tcpdump`。CI 会安装并记录这些工具的版本。

## 独立证据矩阵

| 格式 | 规范来源 | 独立工具与断言 | 向量来源 |
|---|---|---|---|
| PNG | [W3C PNG Third Edition](https://www.w3.org/TR/png-3/) | `pngcheck` 验证 signature、chunk、CRC 与压缩数据 | 生成器按规范组装 1×1 灰度图 |
| WAVE | [Microsoft RIFF/WAVE 规范](https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/Docs/riffmci.pdf) | `soxi` 识别单声道、8 kHz、8-bit PCM | 生成器按 RIFF chunk 布局组装四个采样 |
| PCAP | [IETF PCAP File Format](https://www.ietf.org/archive/id/draft-gharris-opsawg-pcap-02.html) | `tcpdump` 读取链路包并识别 IPv4/UDP 端点 | 生成器组装全局头、记录头与一个 Ethernet frame |
| DNS | [RFC 1035](https://www.rfc-editor.org/rfc/rfc1035) | `tcpdump` 从 PCAP 的相同 UDP payload 解析出 `A? example.com.` | 生成器独立组装 header 与 question；同一字节串另存为 `.dns` |
| ISO BMFF | [ISO/IEC 14496-12](https://www.iso.org/standard/83102.html) | `file`/libmagic 将最小 `ftyp` box 识别为 ISO Media/MP4 | 生成器按 box size、type 与兼容品牌字段组装 |
| ELF | [System V gABI Chapter 4](https://refspecs.linuxfoundation.org/elf/gabi4+/ch4.eheader.html) | GNU `readelf` 识别 ELF64、小端及 `.text`/`.shstrtab` | 生成器按 ELF64 header 与 section table 组装 relocatable object |

`scripts/reference/SHA256SUMS` 固定了六个输出的 SHA-256，防止生成器或运行时差异悄悄改变测试语料。所有向量均由仓库脚本从字段值生成，不含从第三方项目复制的二进制内容。生成器与验证脚本随本仓库采用 Apache-2.0；规范链接仅作为事实性格式依据。CI 中执行的第三方工具不被打包或再分发，其许可证分别为：pngcheck（zlib）、SoX（LGPL-2.1-or-later/GPL-2.0-or-later）、tcpdump（BSD-3-Clause）、file/libmagic（BSD-2-Clause）和 GNU binutils（GPL-3.0-or-later）。

## 证据边界

这些小向量不是格式一致性认证，也不能覆盖完整媒体语义。它们提供的是一条独立、可重复的最低证据：外部工具接受的相同字节，BinSchema 能够解码、重新编码并保持字节相等。更复杂的边界与畸形输入仍由单元测试、属性测试和 mutation corpus 覆盖。
