# Changelog

## Unreleased

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
