# BinSchema

> 用一份可组合的 `Codec[T]` 同时定义安全解码与编码，并让每个字节都可解释。

BinSchema 是一个以 MoonBit 编写的二进制协议编解码框架。它将边界检查、资源限制、字段路径、偏移追踪和往返验证统一在同一套 API 中，并附带原生 CLI、Wasm-GC 可视化界面以及 PNG、WAVE、PCAP 三种真实格式示例。

## 为什么是 BinSchema

手写二进制解析器很容易出现长度溢出、越界读取、尾随数据被忽略、校验和漏验，以及编码与解码逻辑漂移。BinSchema 把这些风险变成框架默认行为：

- **安全默认值**：64 MiB 输入/输出限制、集合长度上限、嵌套深度上限和严格 EOF 检查。
- **双向定义**：同一 `Codec[T]` 同时负责 decode/encode，便于验证 `encode(decode(bytes)) == bytes`。
- **可诊断错误**：统一错误包含分类、绝对字节偏移、字段路径和可读消息。
- **结构追踪**：`.named()` 自动记录每个字段的 `[start, end)`、类型和值预览。
- **跨后端**：核心库和格式实现通过 Wasm、Wasm-GC、JavaScript、Native 四后端测试。
- **开箱即用**：带 CLI、纯浏览器 Wasm 检查器以及 PNG CRC、RIFF 长度、PCAP 字节序等真实校验。

## 快速开始

```mbt nocheck
let header = @bin.pair(
  @bin.magic(b"BS").named("magic"),
  @bin.u16_le().named("version"),
)

match @bin.decode(header, b"BS\x01\x00") {
  Ok(decoded) => {
    // decoded.value == ((), 1U)
    // decoded.trace 包含字段路径和精确字节范围
  }
  Err(error) => println(error.render())
}
```

主要组合子包括：`pair`、`repeat`、`xmap`、`validate`、`bounded`、`length_prefixed`、`optional_if` 和 `checksum_suffix`。基础类型覆盖有/无符号 8/16/32/64 位整数、大小端、固定字节串、magic、MSB 位域和布尔值。

安装依赖：

```bash
moon add prowk/binschema
```

## CLI

```bash
moon run --target native cmd/main -- inspect image.png
moon run --target native cmd/main -- inspect capture.pcap --json
moon run --target native cmd/main -- verify audio.wav
moon run --target native cmd/main -- sample png sample.png
```

支持 `PNG`、`WAVE`、`PCAP`，也可通过 `--format` 显式指定。

## Web / Wasm-GC 演示

```powershell
moon build --target wasm-gc web/bridge
Copy-Item _build/wasm-gc/debug/build/web/bridge/bridge.wasm web/binschema.wasm
python -m http.server 4173 --directory web
```

打开 `http://127.0.0.1:4173/`。文件完全在浏览器本地处理，不会上传；悬停结构字段时会高亮对应十六进制字节。

## 仓库结构

```text
├─ codec.mbt / decoder.mbt / encoder.mbt  # 安全组合子核心
├─ primitives.mbt                         # 基础二进制类型
├─ formats/                               # PNG / WAVE / PCAP 与统一检查 API
├─ cmd/main/                              # 原生 CLI
├─ web/                                   # Wasm-GC 桥接与可视化页面
├─ docs/                                  # 架构和安全模型
└─ 比赛要求/                              # 参赛要求与项目申报材料
```

## 质量保证

```bash
moon check --target all --deny-warn
moon test --target all --deny-warn
moon info
moon fmt
```

测试覆盖正常往返、大小端、位域、条件字段、长度前缀、限制触发、尾随字节、校验和破坏及三种示例格式。更多设计细节见 [架构说明](docs/ARCHITECTURE.md) 与 [安全模型](docs/SECURITY.md)。

## License

Apache-2.0
