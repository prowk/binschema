# 核心流程复现与赛事验收审计

核对日期：2026-11-12。实测环境：Windows x86-64、MSVC 2022、`moonc v0.10.20+65efd5b93`，完整工具链见[兼容性记录](COMPATIBILITY.md)。

## 结论与审计范围

BinSchema 的核心功能能够运行，已有可运行示例、必要测试和开源许可证，具备赛事工程验收的基础。但**当前 GitHub 已公开版本不能在当前工具链下完全按照原文档无修改复现全部流程**。导入别名、严格检查和 Web 复制路径存在已复现的问题。

本次核对了三条独立路径：

1. GitHub `main` 的实际提交 `eea380a8b39e06bd1120973073f592c5d806bb56`：从与远端 SHA 相同的本地 Git 对象导出干净副本，隔离运行，不混入工作区修复。
2. 独立 Mooncakes 调用方：实际安装 `prowk/binschema@0.3.1`，不使用本地 workspace 替换依赖。
3. 已部署的 [Playground](https://prowk.github.io/binschema/)：下载实际 Wasm 验证导出，并使用本机 Chrome 检查页面交互。

首次审计时修复尚未提交。随后修复已通过 [PR #39](https://github.com/prowk/binschema/pull/39) 合入；[CI 记录](https://github.com/prowk/binschema/actions/runs/43232733318) 中 Ubuntu、Windows 和外部参考验证全部通过。以下公开版本结果保留为 `eea380a` 的历史审计；v0.3.2 使用修正后的复现流程。

## 当前赛事要求

仓库中的 `比赛要求/比赛.md` 整理于 2026-09-19，属于九月赛历史资料。[官网](https://moonbitlang.github.io/Hackathon2026/)在本次核对时已经更新为十一月赛：

| 官网公开验收项 | 项目证据与边界 |
| --- | --- |
| MoonBit 为主要实现语言 | 核心 Codec、六种格式、CLI、TCP 示例和 Wasm 桥接均为 MoonBit；JS 为浏览器界面，C 为 Native 文件 I/O 桥接 |
| 仓库公开、开发过程可追踪 | [公开仓库](https://github.com/prowk/binschema)、提交历史、已合并 PR、Changelog 和 [v0.3.1 release](https://github.com/prowk/binschema/releases/tag/v0.3.1) 可核验 |
| 清晰 README、可运行示例、必要测试 | 三个 Native 示例、六格式 CLI、公开包 API 与在线引擎已复现；严格检查及原文档问题见下一节 |
| 已有项目包含本期实质新增工作 | 公开 `main` 最近提交仍在 9 月；不能仅凭既有功能证明十一月新增工作。本期贡献需实际提交并提供变更和验证记录，是否符合实质工作量由赛事审核认定 |
| 认可的开源许可证、说明移植或参考来源 | Apache-2.0；格式规范、向量来源和第三方工具许可证见[外部参考验证](REFERENCE_VALIDATION.md)；这不等于对全部代码来源做过法律审计 |
| 参赛者掌握目标、技术路线与质量 | 需要参赛者现场说明，无法仅通过自动测试确认 |

官网目前说明每队不超过 3 人，报名和验收日期以官方通知为准；已有项目可参与，但重复提交、拆分项目或仅做简单修改不计入验收与奖励。报名表、一页项目说明、交流群加入情况和审核状态不属于本仓库运行验证，仍需参赛者确认。完整飞书章程本次未能读取，不能据此宣称已获得官方验收或参赛资格确认。

## 首次审计公开版本 eea380a 的逐项结果

| 流程 | 实测结果 | 对评委复现的影响与处理 |
| --- | --- | --- |
| `moon add prowk/binschema@0.3.1` | 安装成功，依赖树仅包含核心包和 `x@0.5.5`，未引入 TCP 的 async 依赖 | 发布包可用于独立调用方 |
| 原样复制中文 README 的导入与两个 API 示例 | 失败：导入别名是 `@bin`，示例使用 `@binschema` | 本地已统一为 `@binschema`；修正后四后端均通过；六格式公共 API 另行通过 |
| `examples/custom_packet` | 成功；编码 `42 53 01 e5 8e 26 07 00`，stream_id 624485，4 个 trace 字段 | 可以复现最小协议编解码 |
| `examples/demo_protocol` | 成功；3 条消息、24 字节、23 个 trace 字段 | 可以复现完整组合协议 |
| TCP `app -- demo` | 六场景全部完成，包括分片、粘包、坏 checksum、超长声明、超时和背压 | 可以复现真实网络边界 |
| 六格式 CLI | 每种格式的 `sample`、`inspect --json`、`verify`、`lint --json` 均成功 | 原 README 开头依赖未提供的文件名；本地已改为先生成样例再检查 |
| `moon check --target all --deny-warn` | 失败：根包 11 处旧 `derive(...)` 被视为错误 | 本地已迁移语法；修复后四后端检查、release 构建和 455 项测试通过 |
| `moon build --target wasm-gc web/bridge --release` | 构建成功 | 原 README 随后的复制路径缺少 `prowk/binschema/`，不能直接启动新构建的 Web 引擎；本地已修正 |
| 当前线上 Wasm | 六格式、自动识别及结构化错误导出检查通过 | 可以直接使用已部署引擎 |
| 当前线上页面 | Chrome 已检查六个内置样例，均显示往返校验通过；Schema/Trace 切换及字段/字节双向定位通过 | 页脚及 Mooncakes 链接仍显示 `0.3.0`，与仓库 `0.3.1` 不一致；本地已同步，尚未部署 |
| 最新持续验证 | [2026-11-09 运行失败](https://github.com/prowk/binschema/actions/runs/42612250087)：mutation 成功，资源构建被旧语法和 `--deny-warn` 阻断 | 不能把历史绿色 badge 当作最新工具链的完整通过证据 |

在线页面内置样例的实际摘要：

| 样例 | 大小 | Trace 字段数 | 往返校验 |
| --- | --- | --- | --- |
| PNG | 67 B | 14 | 通过 |
| WAVE | 48 B | 10 | 通过 |
| PCAP | 44 B | 13 | 通过 |
| ISO BMFF | 85 B | 16 | 通过 |
| DNS | 45 B | 16 | 通过 |
| ELF | 280 B | 22 | 通过 |

Chrome 中点击 ELF Trace 的 `elf.magic` 后，前四个字节 `7f 45 4c 46` 与该行同步高亮；再点击偏移 `0x0004` 的字节 `02`，选中项变为 `elf.class`。这验证了实际页面事件与双向定位，而不只是引擎导出。自选文件、拖放、键盘导航和浏览器兼容矩阵未在本次交互检查中逐项验证。

## 从源码复现核心流程

先安装[官方 MoonBit 工具链](https://www.moonbitlang.com/download/)，Native 使用需要 C 工具链；Windows 使用 MSVC 和 Windows SDK。以下命令均在仓库根目录执行。公开分支需要先包含上述兼容性修复；核对待验收提交时，应同时记录 `git rev-parse HEAD` 和 `moon version --all`。

```bash
git clone https://github.com/prowk/binschema.git
cd binschema
git rev-parse HEAD
moon version --all
moon update
moon check --target all --deny-warn
moon build --target all --release --deny-warn
moon test --target all --deny-warn
moon test README.mbt.md --target native --deny-warn
```

复现协议定义、编解码、trace 与真实 TCP：

```bash
moon run --target native examples/custom_packet
moon run --target native examples/demo_protocol
moon run --target native examples/tcp_framing/app -- demo
```

预期分别包含 `encoded: 42 53 01 e5 8e 26 07 00`、`messages: 3` / `roundtrip bytes: 24`，以及 `demo: all scenarios passed`。

无需准备外部文件即可演示 CLI：

```bash
moon run --target native cmd/main -- sample png sample.png
moon run --target native cmd/main -- inspect sample.png --json
moon run --target native cmd/main -- verify sample.png
moon run --target native cmd/main -- lint png --json
```

预期 JSON 含 `"roundtrip_equal": true`，`verify` 显示验证通过。`sample` 还支持 `wav`、`pcap`、`bmff`、`dns`、`elf`；DNS 检查时显式使用 `--format dns`。CLI 的通过仅表示当前支持的结构规则和字节往返，不是格式标准的完整认证。

完整 Native/CLI 流程也可运行：

```bash
python scripts/compatibility-smoke.py
```

## 作为库安装与使用

```bash
moon new binschema-user
cd binschema-user
moon add prowk/binschema@0.3.2
```

将中文 README 的导入段加入 `moon.pkg`，保持别名为 `@binschema`，然后将快速开始代码保存为 `quickstart_test.mbt`，执行 `moon test --target native`。仅用于测试时，可把导入标记为 `for "test"`，避免严格检查中的未使用导入警告。

维护者发布后可从本仓库运行以下检查。默认模式创建独立临时模块，从 README 原样提取导入与两个 `mbt check` 示例，使用 Mooncakes 发布包在四后端运行，不会以本地 workspace 替代依赖。发布前 CI 显式传入 `--source` 验证当前源码，以便尚未上传的新版本也能先完成 CI；该模式不宣称已安装注册表发布包：

```bash
python scripts/check-readme-consumer.py
```

## Web 演示

直接打开 [Playground](https://prowk.github.io/binschema/)，依次点击六个内置样例，检查格式、大小、字段数和往返结果。切换 Schema/Trace，点击 Trace 行及字节查看双向定位。DNS 使用显式格式选择。

本地构建：

```bash
moon build --target wasm-gc web/bridge --release
cp _build/wasm-gc/release/build/prowk/binschema/web/bridge/bridge.wasm web/binschema.wasm
python -m http.server 4173 --directory web
```

Windows PowerShell 将复制命令替换为：

```powershell
Copy-Item _build/wasm-gc/release/build/prowk/binschema/web/bridge/bridge.wasm web/binschema.wasm
```

浏览器打开 `http://127.0.0.1:4173/`。需要支持 Wasm-GC、JS string builtins 和 imported string constants 的浏览器；上传区实际读取本地文件，不向服务器上传。若只验证引擎导出，可在 Node.js 24 下执行 `node web/check-wasm.mjs`。

## 提交验收前仍需完成的事项

1. 将本地兼容性修复、文档修复及回归检查提交并推送到待验收分支，记录确切 SHA；本次审计没有代为执行发布。
2. 等待该 SHA 的 Ubuntu/Windows CI 和 Pages 构建通过，重新从该提交的干净副本复现；Linux 资源与外部参考工具由 Ubuntu CI 验证。
3. 在项目申报/更新材料中说明十一月的实质新增工作，附提交、测试与演示证据。不能直接把九月发布版当成本期新增成果。
4. 按当前官方通知确认报名、交流群、项目说明和验收提交要求，并准备解释 Codec、边界限制、Trace、增量解析和第三方依赖选择。
