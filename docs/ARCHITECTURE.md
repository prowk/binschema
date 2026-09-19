# 架构说明

## 分层

BinSchema 将协议处理划分为四层：

1. `Decoder` / `Encoder` 管理游标、位偏移、缓冲区和资源预算。
2. `Codec[T]` 封装双向规则，组合子负责复用与校验。
3. `formats` 使用同一套公开 API 实现 PNG、WAVE、PCAP，并提供格式自动检测。
4. CLI 与 Wasm Web 只依赖统一的 `Inspection`，因此输出语义一致。

```text
Binary input
    │
    ▼
bounded Decoder ──► Codec[T] ──► typed value
    │                   │             │
    └─ TraceEntry[]     └─ Encoder ◄──┘
                              │
                              ▼
                        roundtrip check
```

## 核心不变量

- 解码器只能消费当前边界内的字节。
- 位读取与字节读取不可在未对齐状态下混用。
- 声明长度在分配/循环前先与运行时和用户上限比较。
- 默认解码必须消费完整输入。
- 编码输出始终受到 `max_output_bytes` 限制。
- 具名字段的错误路径和轨迹使用同一命名空间。

## 扩展一种格式

格式包可直接组合基础 codec，也可用 `Codec::make` 实现依赖前序字段的协议。复杂格式应先验证 magic，再验证长度；先创建有界子解码器，再解析内容；最后验证校验和或结构终止符。

Web 桥接只导出字符串接口 `inspect_hex` 与 `sample_hex`，避免将 MoonBit GC 引用泄漏到 JavaScript。浏览器使用 JS String Builtins，解析逻辑本身仍由同一份 MoonBit 格式代码执行。
