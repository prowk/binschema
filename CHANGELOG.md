# Changelog

## Unreleased

## 0.3.0 — 2026-09-22

- 修复定宽无符号整数编码的静默截断：`u8` / `u16_*` 现在拒绝超出 wire width 的值，长度前缀也不会写出截断后的长度。
- 修复非整字节 bit codec 的 byte-frame 对称性：编码零填充的末字节可被完整/前缀/有界解码正确消费，非零尾随 padding bits 会被拒绝。
- 强化 `padding` 输出预算与增量 framing：零填充在大写入前预检 `max_output_bytes`，`IncrementalDecoder` 拒绝零消费 frame，并新增 `append()` 以便批量小 chunk 后再 `poll()`。
- 收紧 PNG/WAVE 编码模型：PNG 校验公开 CRC、chunk type 与核心 IHDR 规则；WAVE 校验非零 RIFF size、派生 format metadata、chunk id 与 padding 一致性。
- 新增不依赖 `sample_*` encoder 的固定 wire golden fixtures，覆盖 PNG、WAVE、PCAP、ISO BMFF、DNS 与 ELF 的独立解析/roundtrip smoke test。
- 明确 Schema Linter、buffered incremental framing、内置真实格式与 CLI `verify` 的能力边界；发布 CI 固定 MoonBit 0.10.14，并额外检查 latest toolchain 前向兼容。
- 新增 ELF32/ELF64 字节保真结构检查：支持双端序、program/section header table 边界验证、扩展 section numbering 与 section-name string table 解析，并贯通 Inspector、CLI 与 Web。
- 新增 DNS 报文格式支持：解析 header/question/RR，保留 raw RDATA 与压缩域名 wire；压缩 pointer 强制包内向后引用并受 `max_depth` 限制，section count/label/展开域名均受资源边界约束，并贯通 CLI、Web Inspector、Schema 与 mutation 回归。
- Decoder 新增 `view_at(offset, count)` 非消费有界随机读取与 `max_depth()` 预算查询，为 DNS 压缩指针、offset table 等引用型协议提供安全基础。
- 新增 ISO BMFF / MP4 box 格式支持：保留未知 box payload，支持普通 32-bit size、64-bit `largesize`、`size=0`、`uuid` user type，并贯通 CLI、Web Inspector、Schema 与 mutation 回归。
- 新增基于 Schema/Trace 的确定性 mutation 安全回归：覆盖字段边界截断、长度字段膨胀、PNG CRC 损坏和字段首字节翻转，并在四后端执行一致性验证。
- 新增前缀与增量解码：`decode_prefix*`、`probe_decode*` 和 `IncrementalDecoder` 可区分完整 frame、需要更多数据与真实格式错误，并保留未消费尾部用于后续 frame。
- 新增 Schema Linter：可检查缺失的局部长度/计数上限、动态 tagged 分支、until-eof/remaining 区域依赖和同级字段重名；CLI 新增 `lint <format> [--json]`。
- Inspector 结果现包含协议 Schema 树，内置格式提供静态结构描述，Web Inspector 可直接浏览协议层级与约束。
- `Codec[T]` 现携带可检查的 Schema 元数据树，可导出名称、组合结构与约束，并支持稳定文本描述。
- 新增零填充、字节边界对齐与 NUL 终止字节串 codec，补齐常见二进制布局基础能力。

## 0.2.0 — 2026-09-22

- 同步公开版本常量与 `moon.mod`，并在 CI 中强制校验版本一致性。
- 新增完整 Demo Protocol，展示计数数组、tagged 消息、长度前缀 payload、字段 trace 与 checksum 的组合用法。
- 新增 `count_prefixed`、`until_eof`、`tagged` 高级组合子，并为大输入提供 `decode_view` / `BytesView` 零拷贝解码路径。
- 新增确定性 property-style roundtrip 测试与固定二进制 corpus 回归测试，并纳入 Wasm、Wasm-GC、JavaScript、Native 四后端 CI。
- 收紧核心公开结构的可变性，新增可配置轨迹预算以防止诊断数据放大。
- 新增规范的 ULEB128/SLEB128 codec，并补齐边界、溢出、截断和跨后端测试。
- 强化 PNG、WAVE、PCAP 结构不变量及损坏样例校验。
- CLI 增加可测试调度、输入限制和稳定退出码；浏览器检查器增加 16 MiB 限制和键盘可访问性。
- CI 增加生成接口同步、API 文档、发布包审计、可执行 README、Native benchmark、coverage 与完整构建门禁。
- 声明模块/包级后端支持范围，补充英文入口、兼容性策略、正式发布流程与 GitHub Pages 在线 Playground。
- 浏览器 Wasm 改为由源码在构建/部署阶段生成，不再提交 `web/binschema.wasm` 预编译产物，避免二进制与源码漂移。

## 0.1.0 — 2026-09-19

- 首个公开版本。
- 安全双向 `Codec[T]`、基础数值/字节/位域 codec 与组合子。
- PNG、WAVE、PCAP 示例格式及统一检查 API。
- Native CLI 与 Wasm-GC 浏览器可视化界面。
- Wasm、Wasm-GC、JavaScript、Native 四后端测试。
