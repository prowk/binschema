# 架构说明

## 分层

BinSchema 将协议处理划分为四层：

1. `Decoder` / `Encoder` 管理游标、位偏移、缓冲区和资源预算；Decoder 内部持有 `BytesView`，有界子区域默认借用原输入。
2. `Codec[T]` 封装双向规则，同时携带只读 `SchemaNode` 元数据；组合子会同步组合运行时规则和协议结构。
3. `formats` 使用同一套公开 API 实现 ELF、PNG、WAVE、PCAP、ISO BMFF、DNS，并为手写动态解析器提供显式 Schema 结构描述。
4. CLI 与 Wasm Web 只依赖统一的 `Inspection`；其中同时包含 `SchemaNode`（静态结构）与 `TraceEntry[]`（本次输入的动态字节轨迹）。

```text
Binary input
    │
    ▼
bounded Decoder ──► Codec[T] ──► typed value
    │                   │             │
    └─ TraceEntry[]     ├─ SchemaNode │
                        └─ Encoder ◄──┘
                             │
             ┌───────────────┴──────────────┐
             ▼                              ▼
       roundtrip check                Inspector / tooling
                                             │
                                             └─ Schema Linter
```

## 核心不变量

- 解码器只能消费当前边界内的字节；`view_at` 允许在同一边界内进行不移动游标的随机借用读取，用于压缩指针与 offset table，越界仍返回结构化错误。
- `take_view` / `bounded` / `decode_view` 优先使用借用视图；只有调用拥有型 API 时才复制为 `Bytes`。
- 位读取与字节读取不可在未对齐状态下混用。
- 声明长度在分配/循环前先与运行时和用户上限比较。
- 默认解码必须消费完整输入。
- 编码输出始终受到 `max_output_bytes` 限制。
- 具名字段的错误路径和轨迹使用同一命名空间。
- 轨迹记录受 `max_trace_entries` 预算约束，避免诊断数据绕过输入资源限制。

## 扩展一种格式

格式包可直接组合基础 codec，也可用 `Codec::make` 实现依赖前序字段的协议。`count_prefixed` 处理显式计数数组，`until_eof` 处理消费到区域结尾的序列，`tagged` 处理标签联合；大 payload 应优先使用 `bytes_view_fixed` / `remaining_view`。复杂格式应先验证 magic，再验证长度；先创建有界子解码器，再解析内容；最后验证校验和或结构终止符。

Web 桥接只导出字符串接口 `inspect_hex` 与 `sample_hex`，避免将 MoonBit GC 引用泄漏到 JavaScript。浏览器使用 JS String Builtins，解析逻辑本身仍由同一份 MoonBit 格式代码执行。


## Schema Linter

`lint_schema` 只分析 `SchemaNode`，不执行解码，因此可以在没有样本文件的情况下检查协议结构。首版规则将缺失的局部 `max_length` / `max_count` / 固定边界视为错误，将动态 tagged 分支、`until_eof`、`remaining_*` 与同级重名视为警告。规则输出稳定的 `code`、`severity`、`path` 与 `message`，便于 CLI、CI 和未来的 Web 工具复用。


## 增量与流式解码

完整文件仍使用 `decode` / `decode_view` 的严格 EOF 语义。网络帧或拼接缓冲区可使用 `decode_prefix` 只消费一个值；`probe_decode` 仅将 `UnexpectedEof` 映射为 `NeedMore`，其他错误立即暴露。`IncrementalDecoder` 在此基础上负责累积 chunk、遵守 `max_input_bytes`，成功后只丢弃已消费前缀并保留尾部。依赖“当前区域 EOF”的 `until_eof` / `remaining_*` 不适合作为无边界流式 frame，应该先用协议长度字段建立 `bounded` 区域。


## ISO BMFF 压力格式

ISO BMFF 用作长度驱动容器协议的真实压力样例。`BmffBox` 保留 4-byte type、普通/扩展尺寸编码方式、`size=0` 语义、可选 `uuid` user type 与原始 payload。未知 box 不做有损解释，因此 `decode -> encode` 可以保持字节级一致；解码在消费 payload 前验证 header 长度、运行时可表示范围和 enclosing region 剩余长度，编码则要求 `size=0` 只能出现在当前区域最后一个 box。自动检测仅接受常见 `ftyp` / `styp` 起始签名，其他合法 BMFF 文件仍可通过显式 `--format bmff` 检查，以降低误识别。


## DNS 引用型压力格式

DNS 用作“顺序字段 + 包内引用”的真实压力样例。域名主路径仍通过普通 Decoder 顺序消费；遇到 RFC 1035 压缩指针时，使用 `view_at` 在同一报文边界内非消费读取目标。实现要求 pointer 目标严格早于 pointer 本身、所有随机读取必须留在当前 Decoder 区域内，并以 `max_depth` 限制 pointer 跳转链；label 长度限制为 63 octets，展开后的域名限制为 255 octets，四个 section count 在进入循环前与 collection budget 比较。`DnsName` 同时保留展开后的 labels 和本字段原始 wire，因此包含压缩指针的合法报文仍可字节级 roundtrip。RDATA 首版保持 raw bytes，避免在未实现具体 RR TYPE 时做有损解释。


## ELF offset-table 压力格式

ELF 用作“固定 header + 文件内 offset table + 跨表字符串引用”的真实压力样例。首版同时支持 ELF32/ELF64 与大小端，验证 `e_phoff` / `e_shoff`、表项大小、表项数量、section payload 范围，以及 `e_shstrndx` 指向的 section-name string table；`e_shnum == 0`、`e_shstrndx == 0xffff` 与扩展 program-header count 会从 section header zero 解析。ELF codec 是字节保真的结构视图：`ElfFile` 同时保存解析后的 metadata 与原始 `raw`，编码前会重新解析 `raw` 并要求 metadata 完全一致，避免用户修改 metadata 后编码器悄悄忽略更改。重定位、符号表和动态链接语义留给后续专门层，不在本阶段做有损解释。
