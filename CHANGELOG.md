# Changelog

## Unreleased

- 新增规范的 ULEB128/SLEB128 codec，并补齐边界、溢出、截断和跨后端测试。
- 强化 PNG、WAVE、PCAP 结构不变量及损坏样例校验。
- CLI 增加可测试调度、输入限制和稳定退出码；浏览器检查器增加 16 MiB 限制和键盘可访问性。
- GitHub 首页发布完整使用文档，并加入可复现的自定义协议示例。

## 0.1.0 — 2026-09-19

- 首个公开版本。
- 安全双向 `Codec[T]`、基础数值/字节/位域 codec 与组合子。
- PNG、WAVE、PCAP 示例格式及统一检查 API。
- Native CLI 与 Wasm-GC 浏览器可视化界面。
- Wasm、Wasm-GC、JavaScript、Native 四后端测试。
