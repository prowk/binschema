# BinSchema

安全、可组合、可追踪的 MoonBit 二进制协议编解码框架，附带 CLI、Wasm-GC 可视化工具和 PNG/WAVE/PCAP 示例。

完整文档请阅读 [README.mbt.md](README.mbt.md)。

## Highlights

- 同一 `Codec[T]` 定义编码与解码
- 默认资源限制、严格 EOF、字段路径和精确错误偏移
- PNG CRC、WAVE RIFF、PCAP 多字节序真实格式验证
- Wasm、Wasm-GC、JavaScript、Native 四后端测试
- 浏览器本地可视化，不上传文件

Apache-2.0 licensed.
