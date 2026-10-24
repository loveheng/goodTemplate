# goodTemplate · goodhub 服务端模板

Android 常驻壳 + 内嵌 MCP 服务端内核的**起底脚手架**：新 app 复制本仓 → `init-app` 一键改名 → 换真实工具面即上工。

**独立演化**：本仓自带全部内核源码，与任何外部仓无同步/跟版关系，内核改动直接落本仓。

## 架构总览

```
                      ┌────────────────────────────────────┐
  桌面调试（adb reverse）  │  HTTP 回环调试通道                     │
  ──────────────────→  │  main.dart → McpController          │
                      │             └→ tool_face_assembly ──┼──┐
  goodhub 宿主（Binder）  │  Binder 生产通道                     │  │ 双通道共用同一份装配
  ──────────────────→  │  McpBinderService(SDK 基类)          │  │ （单点收口，禁双写）
                      │   └→ headless engine                │  │
                      │       └→ mcp_binder_entrypoint ─────┼──┘
                      └────────────┬───────────────────────┘
                                   ↓
        McpServer（JSON-RPC 内核）→ CommandGateway（唯一写入口，AI/用户侧注册表分离）
                                   ↓
        SettingsKv（SecretAwareKv：普通键持久化 / 凭证键分流 Keystore 安全存储）
```

- **领域网关（CategoryTool）**：N 个细粒度子操作聚合为 1 个 MCP 工具（action 枚举派发），W 档子操作只 buildCommand、网关统一派发；示例见 `lib/tools/sample_tool_face.dart`。
- **依赖反转**：领域端口（`lib/mcp/sample_provider.dart` 样板）内核只依赖抽象；实现落 `lib/service/`，失败返不可空信封**禁 null 静默降级**。
- **凭证零明文**：凭证键经 `SecretAwareKv` 分流到 Keystore 安全存储（`SecretStoreChannel.kt`，**双引擎注册**：MainActivity + McpBinderService 漏挂即 MissingPluginException）。
- **元组件基座**（`lib/ui/` + `lib/ui_ports/readiness.dart`）：BlockCanvas 区块底座 / 通用纯件（app_components）/ 括号配对 formatter / 就绪状态点与元类型。**元组件口径：只收不可再分的积木**，页面与成品网格各 app 自拼；取 token 走主题扩展——**宿主在自建主题里注册 `AppTokens` 实例**（视觉值归宿主；示范见 `test/ui_smoke_test.dart`）。模板不带主题骨架与页面范式。
- **内核配套页**（`lib/ui/mcp_service_page.dart`）：MCP HTTP 调试服务控制页（启停 / token 重生成 / 直连指引）——调试设施本身，随内核走；宿主注入 `McpController`，视觉值同样走宿主注册的 token。

## 起底（init-app）

```sh
# 复制本仓为新 app 目录后，在新仓根跑（**首跑用 bash 直调**：新仓尚无 .git，
# `toolbox run` 解析不到项目池；init-app 收尾自建 git 首提交，此后 toolbox 可用）：
bash scripts/agent-tools/init-app.sh --name my_app --org com.yourco --title "MyApp" [--with-agents]
# 跑完自动 pub get + analyze 验收；改名点覆盖 pubspec/gradle/Kotlin 包路径/通道名/manifest meta/dart 导入前缀/R2 部署前缀。
```

对接契约（脚本只检查、永不修改）：SDK 坐标 `com.zzh.goodhub.mcp:*`、签名权限 `com.zzh.goodhub.permission.MCP_SERVER`、服务 action `com.zzh.goodhub.action.MCP_SERVER`。

起底后三步：

1. 写真实领域网关（参照 sample），在 `lib/tool_face_assembly.dart` 单点收口；
2. 需要凭证的键在装配处登记 `SecretAwareKv.secretKeys`（两侧装配：main 与 binder entrypoint）；
3. goodhub 实机 bind 联调（同签名出包）。

## 领域网关纪律（G1–G6）

领域网关与子操作的机械约束——`lib/mcp/category_tool_face.dart`、`lib/tools/` 注释中的 G 档编号以本节为本仓唯一正文：

- **G1 action 即对外契约**：`action` 名一经对外发布**禁改名、禁自造同义新名**——客户端按名调用，改名即破坏性变更。
- **G2 公共入口 / 私有内部**：抽象契约（`SubAction` / `CategoryTool` / `register`）为 package 内部 public（`_` 是文件级私有，跨文件无法子类化）；具体子操作实现类（`_XxxSub`）以 `_` 前缀私有于各自文件。
- **G3 写门禁机械强制**：W 档子操作只 `buildCommand` 构造命令**不派发**；`admits` 鉴权 + `dispatch` 统一收口在 `CategoryTool.call` 网关层，子操作禁自行 dispatch/鉴权。
- **G4 `isError` 唯一派生**：`isError = !success` 硬绑定，禁止在 `McpServer` 或任何调用点二次赋值——杜绝「`isError:false` 而 `success:false`」矛盾体。
- **G5 参数宽容解析边界**：宽容解析（parseDouble/parseInt/parseBool）只允许出现在子操作入参边界、一次性转强类型；缺参或不可解析一律返带 `code` 的 error，**禁止默认值兜底**（严禁静默降级）。
- **G6 W 档前置校验与 Actor 信封**：W 档可选 `validate`（`admits` 通过后、`buildCommand` 之前调用）；Actor 输出统一 `{'success': …}` JSON 信封，`isError` 由信封派生——业务失败对客户端可见而非藏在文本里。

## 构建通路（Android）

- `minSdk = 34`（Android 14）：SDK 两模块基线，低于 34 manifest merger 直接失败。
- 依赖解析 = `mavenLocal()` + 离线分发件目录（默认 sibling 仓 `../goodhub-mcp-sdk/dist/maven-repo`，可 `-PmcpSdkDist=<dir>` 覆盖）。**SDK 升版后须先在 goodhub-mcp-sdk 仓跑 `scripts/dist.sh`**，否则解析 FAILED。
- McpBinderService 继承 SDK `GoodHubPluginService` 并重写 `handleJsonRpc` 接管路由（业务在 Dart，SDK 反射派发器扫不到 `@McpTool`，不接管则 `tools/list` 空）；tools/call 走 `_async` + onEvent 终帧切片，勿退化。

## 验收命令

```sh
flutter analyze                # 0 issue
flutter test                   # smoke：内核链路/凭证分流/装配 R-W 双档 + 元组件与内核配套页冒烟
toolbox run init-app --self-test
node tool/mcp-bridge/e2e-check.mjs   # 真机/模拟器 HTTP 回环端到端（token 见控制台日志）
toolbox run arch-guard         # R1–R7 红线机械扫
```
