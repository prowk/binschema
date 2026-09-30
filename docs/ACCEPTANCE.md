# BinSchema 验收清单

本文档将项目证据与赛事验收项逐项对应。所有命令均从仓库根目录运行。

## 1. MoonBit 主实现与工具链版本

- GitHub 将仓库主语言识别为 MoonBit；核心库、格式实现、CLI 和 Wasm 桥接均使用 `.mbt` 源码。
- 最低支持版本为 `moonc 0.10.14`，CI 会解析实际版本并拒绝更旧的编译器。
- 本地核验：`moon version --all`、`moon check --target all --deny-warn`。

## 2. 公开仓库与提交记录

- 公开仓库：[github.com/prowk/binschema](https://github.com/prowk/binschema)。
- 默认分支为 `main`，功能、修复、测试和发布提交使用清晰的 Conventional Commits 风格标题。
- 核验：`git log --oneline --decorate -20`。

## 3. 源码结构与核心功能

- `codec.mbt`、`decoder.mbt`、`encoder.mbt`：组合式双向编解码核心。
- `primitives.mbt`、`varint.mbt`：基础类型、位域和规范变长整数。
- `schema.mbt`、`lint.mbt`：结构描述与协议静态检查。
- `formats/`：ELF、PNG、WAVE、PCAP、ISO BMFF 和 DNS 实现。
- `cmd/main/` 与 `web/bridge/`：原生 CLI 与 Wasm-GC 浏览器入口。
- `examples/tcp_framing/`：隔离的 TCP 集成模块，验证拆包、背压、超时、错误定位与连接清理，不改变核心库依赖或 API。

## 4. README 与可复现使用说明

- `README.md` 说明项目目标、最低工具链、安装、API 使用、CLI、Web 检查器和开发验收命令。
- `README.mbt.md` 包含可执行快速开始与增量解析示例，CI 通过 `moon test README.mbt.md --target native --deny-warn` 验证。
- `README.en.md` 提供对应的英文说明。

## 5. 持续集成

- [GitHub Actions CI](https://github.com/prowk/binschema/actions/workflows/ci.yml) 覆盖接口同步、文档生成、发布包审计、格式检查、四后端检查与测试、外部参考工具、mutation fuzz、资源压力检查、覆盖率、示例、CLI 和 Wasm-GC 构建。
- `latest-toolchain` 作业额外验证最新 MoonBit 工具链的前向兼容性。
- [持续验证工作流](https://github.com/prowk/binschema/actions/workflows/continuous-verification.yml) 每周运行固定回归 seed 与按 run id 推导的动态 seed，并归档带环境信息的性能和峰值内存记录。
- Pages 工作流从源码重建并部署浏览器演示站。

## 6. 可运行示例

最小示例：

```bash
moon update
moon run --target native examples/custom_packet
```

完整协议示例：

```bash
moon run --target native examples/demo_protocol
```

真实 TCP 集成示例：

```bash
moon run --target native examples/tcp_framing/app -- demo
```

该命令在临时 loopback 端口自动验证正常、分片、粘包、坏 checksum、超长声明、半包超时和有界队列背压后退出；也提供独立 `server` / `client` 模式。

## 7. 核心测试

- 根包测试覆盖整数、组合子、边界限制、错误路径、增量解析、组合式 property roundtrip 和固定 corpus。
- `formats/` 覆盖六种格式的正常、截断、损坏和结构化 mutation 路径；独立原生 runner 支持固定 seed 的持续 fuzz。
- CLI、演示协议、TCP loopback 集成、Wasm JSON 桥接和浏览器静态资源均有独立测试。
- 六种格式还使用外部成熟工具交叉验证，证据边界见 `docs/REFERENCE_VALIDATION.md`；资源工作负载与记录规则见 `docs/PERFORMANCE.md`。
- 完整核验：`moon test --target all --deny-warn`；fuzz smoke：`moon run --target native tools/mutation_fuzz -- --seed 1 --iterations 512`；覆盖率在插桩测试后分别用 `moon coverage analyze -p prowk/binschema -- -f summary` 和 `moon coverage analyze -p prowk/binschema/formats -- -f summary` 核验核心库与格式包。

## 8. Mooncakes 发布

- 模块名与版本由 `moon.mod` 声明为 `prowk/binschema@0.3.1`。
- 已发布文档：[mooncakes.io/docs/prowk/binschema@0.3.1](https://mooncakes.io/docs/prowk/binschema@0.3.1)。
- 发布前可用 `moon package --list` 核验归档内容，并按 `docs/RELEASING.md` 执行发布流程。

## 9. 开源许可证与第三方依赖

- 项目采用 OSI 认可的 [Apache License 2.0](../LICENSE)，`moon.mod` 同步声明 `license = "Apache-2.0"`。
- 项目依赖在 `moon.mod` 中显式声明并由 `.mooncakes/.moon-lock` 锁定；发布包审计会排除仓库专用资源。
- 当前实现未直接移植或复制其他开源项目的源代码；若未来引入此类代码，必须保留原始版权、许可证和归属声明。
