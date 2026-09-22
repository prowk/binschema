# BinSchema

**简体中文** · [English](README.en.md) · [🌐 在线 Playground](https://prowk.github.io/binschema/)

> 用一份可组合的 `Codec[T]` 同时定义安全解码与编码，并让每个字节都可解释。

BinSchema 是一个用 MoonBit 编写的安全二进制协议编解码框架。它将边界检查、资源限制、字段路径、偏移追踪和往返验证统一在同一套 API 中，并附带原生 CLI、Wasm-GC 浏览器检查器以及 PNG、WAVE、PCAP、ISO BMFF 与 DNS 五种真实格式实现。

## 特性

- **安全默认值**：64 MiB 核心输入/输出限制、集合长度上限、嵌套深度上限和严格 EOF 检查。
- **双向定义**：同一 `Codec[T]` 同时负责解码和编码，便于验证 `encode(decode(bytes)) == bytes`。
- **可诊断错误**：错误包含分类、绝对字节偏移、字段路径和稳定的可读消息。
- **结构追踪**：`.named()` 记录字段的 `[start, end)`、类型和值预览，可直接驱动可视化界面。
- **Schema 与静态检查**：每个 `Codec[T]` 都能导出结构树，并通过 `lint()` 检查缺失的局部上限、动态分支和区域吞噬等协议风险。
- **规范变长整数**：内置安全的 `uleb128()` 与 `sleb128()`，拒绝截断、溢出、超长和非最短编码。
- **高级组合**：提供 `count_prefixed`、`until_eof` 与 `tagged`，覆盖计数数组、流式尾读和标签联合。
- **零拷贝解码**：`decode_view`、`bytes_view_fixed`、`remaining_view` 与 `checksum_suffix_view` 可直接借用 `BytesView`，有需要时再显式转成拥有型 `Bytes`。
- **增量帧解析**：`decode_prefix`、`probe_decode` 与 `IncrementalDecoder` 支持分块输入、`NeedMore` 判定和多 frame 尾部保留。
- **跨后端验证**：Wasm、Wasm-GC、JavaScript、Native 四后端使用同一套测试。
- **结构化安全回归**：从真实格式的 Schema/Trace 派生确定性 mutation，覆盖截断、长度膨胀、CRC 损坏和字段边界翻转。
- **真实格式校验**：检查 PNG CRC 与块顺序、WAVE RIFF 结构、PCAP 字节序/长度/时间戳、ISO BMFF box 长度与扩展头，以及 DNS section count、label 长度和压缩指针边界/方向/深度。

## 快速开始

在 MoonBit 项目中添加依赖：

```bash
moon add prowk/binschema
```

并在调用方的 `moon.pkg` 中导入：

```text
import {
  "prowk/binschema" @bin,
}
```

下面的快速开始同时是仓库里的可执行文档测试。组合一个带魔数、版本号和 LEB128 流 ID 的协议：

```mbt check
///|
test "README quick start" {
  let packet = @binschema.pair(
    @binschema.magic(b"BS").named("magic"),
    @binschema.pair(
      @binschema.u8().named("version"),
      @binschema.uleb128().named("stream_id"),
    ),
  )
  let value = ((), (1U, 624485UL))
  let bytes = match @binschema.encode(packet, value) {
    Err(error) => fail(error.render())
    Ok(bytes) => bytes
  }
  match @binschema.decode(packet, bytes) {
    Err(error) => fail(error.render())
    Ok(decoded) => {
      assert_eq(decoded.value, value)
      assert_eq(decoded.trace.length(), 3)
      assert_true(packet.describe().contains("stream_id"))
      assert_eq(packet.lint().length(), 0)
    }
  }
}
```

基础 codec 覆盖有/无符号 8/16/32/64 位整数、大小端、ULEB128、SLEB128、固定字节串、magic、MSB 位域和布尔值。主要组合子包括 `pair`、`repeat`、`count_prefixed`、`until_eof`、`tagged`、`xmap`、`validate`、`bounded`、`length_prefixed`、`optional_if`、`checksum_suffix` 与零拷贝 `checksum_suffix_view`。对于大输入，可用 `decode_view` + `bytes_view_fixed` / `remaining_view` 避免不必要的字节复制。

## 增量 / 流式输入

对于 TCP、串口或其他分块输入，可以先用 `probe_decode` 判断当前缓冲区是否足够，或直接使用 `IncrementalDecoder` 累积 chunk。成功解析一个 frame 后，未消费尾部会保留给下一帧：

```mbt check
///|
test "README incremental decode" {
  let codec = @binschema.pair(@binschema.u16_be(), @binschema.u8())
  let stream = @binschema.IncrementalDecoder::new(codec)
  assert_true(stream.feed(b"\x12") is @binschema.NeedMore)
  match stream.feed(b"\x34\x56\xaa") {
    @binschema.Done(decoded) => assert_eq(decoded.value, (0x1234U, 0x56U))
    _ => fail("expected one complete frame")
  }
  assert_eq(stream.buffered_bytes(), 1)
}
```

只有 `UnexpectedEof` 会被视为 `NeedMore`；校验失败、非法枚举值等错误会立即返回 `Failed`。依赖当前区域结尾的 `until_eof` / `remaining_*` 应先放进协议定义的有界区域，再用于流式场景。

## 可复现的自定义协议示例

仓库中的 [`examples/custom_packet`](examples/custom_packet) 定义了如下布局：

```text
magic "BS" | version u8 | stream_id uleb128 | sequence u16_le
```

克隆仓库后可直接运行：

```bash
moon update
moon run --target native examples/custom_packet
```

预期输出包含：

```text
encoded: 42 53 01 e5 8e 26 07 00
stream_id: 624485
trace fields: 4
```

如果想看一个更接近真实应用的完整协议示例，参见 [`examples/demo_protocol`](examples/demo_protocol)。它在一份 codec 树中组合 magic、版本校验、计数数组、tagged union、长度前缀 payload、字段 trace 和整包 checksum，展示“定义一次协议，同时获得编码、解码、校验与字节级解释”的完整工作流。

运行：

```bash
moon run --target native examples/demo_protocol
```

## CLI

```bash
moon run --target native cmd/main -- inspect image.png
moon run --target native cmd/main -- inspect capture.pcap --json
moon run --target native cmd/main -- verify audio.wav
moon run --target native cmd/main -- sample png sample.png
moon run --target native cmd/main -- sample bmff sample.mp4
moon run --target native cmd/main -- sample dns sample.dns
moon run --target native cmd/main -- lint png
moon run --target native cmd/main -- lint pcap --json
moon run --target native cmd/main -- inspect sample.mp4 --format bmff
moon run --target native cmd/main -- inspect sample.dns --format dns
moon run --target native cmd/main -- formats
```

CLI 支持 PNG、WAVE、PCAP、BMFF 与 DNS；`mp4` / `isobmff` 会解析为 BMFF。DNS 因缺少可靠固定 magic，不参与自动识别，需显式使用 `--format dns`。`lint <format>` 会对内置协议的 Schema 执行静态检查；Warning 仅提示风险，Lint Error 会返回数据错误退出码，便于接入 CI。输入上限为 64 MiB，并使用稳定退出码区分参数错误、数据错误和 I/O 错误。

## Web / Wasm-GC 检查器

**在线体验：** [https://prowk.github.io/binschema/](https://prowk.github.io/binschema/)

无需安装 MoonBit，直接在浏览器中选择 PNG、WAVE、PCAP、常见 MP4 / ISO BMFF 或 DNS 文件即可查看结构；文件只在本地浏览器处理，不会上传。

本地开发时，Wasm 二进制由源码构建生成，仓库不再提交 `web/binschema.wasm`：

```bash
moon build --target wasm-gc web/bridge --release
cp _build/wasm-gc/release/build/web/bridge/bridge.wasm web/binschema.wasm
python -m http.server 4173 --directory web
```

Windows PowerShell 可用：

```powershell
Copy-Item _build/wasm-gc/release/build/web/bridge/bridge.wasm web/binschema.wasm
```

打开 `http://127.0.0.1:4173/`。文件仅在浏览器本地处理，不会上传；浏览器输入上限为 16 MiB。界面可查看字段结构、十六进制范围和往返校验结果，并支持键盘导航。

## 仓库结构

```text
├─ codec.mbt / decoder.mbt / encoder.mbt  # 安全组合子核心
├─ schema.mbt / lint.mbt                  # Schema 元数据与静态检查
├─ primitives.mbt / varint.mbt            # 定长与变长基础类型
├─ formats/                               # PNG / WAVE / PCAP / ISO BMFF / DNS
├─ cmd/main/                              # 原生 CLI
├─ web/                                   # Wasm-GC 桥接与浏览器检查器
├─ examples/custom_packet/                # 最小自定义协议示例
├─ examples/demo_protocol/                # 更完整的真实协议示例
└─ docs/                                  # 架构和安全模型
```

## 开发与验收

```bash
moon update
moon info
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon test README.mbt.md --target native --deny-warn
moon bench --build-only --target native --deny-warn
moon test --target native --enable-coverage --deny-warn
moon coverage analyze
moon build --target native cmd/main --release
moon build --target native examples/custom_packet --release
moon build --target native examples/demo_protocol --release
moon build --target wasm-gc web/bridge --release
cmp README.md README.mbt.md
```

测试覆盖整数边界、大小端、位对齐、资源限制、嵌套深度、组合子错误传播、变长整数异常、确定性 property roundtrip、固定二进制 corpus、基于 Schema/Trace 的结构化 mutation、损坏格式样例、CLI 调度和 Wasm JSON 契约。GitHub Actions 会在四后端执行这些测试，并验证示例构建、覆盖率流程和 README 同步。

更多设计细节见 [架构说明](docs/ARCHITECTURE.md)、[安全模型](docs/SECURITY.md)、[兼容性策略](docs/COMPATIBILITY.md) 与 [发布流程](docs/RELEASING.md)。安全问题请按 [安全策略](docs/SECURITY.md) 中的方式报告。

## License

[Apache-2.0](LICENSE)
