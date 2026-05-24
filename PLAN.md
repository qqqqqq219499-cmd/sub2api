# Sub2API Codex 队列卡顿优化与当前部署运行手册

## 0. 当前结论

本文件保留历史排查记录，但旧的线上状态已经废除：服务器已在 2026-05-24 重装系统，原数据库和原容器数据不再作为事实来源。

当前可用方案不是在服务器上源码构建本仓库，而是按朋友 runbook 使用官方镜像部署：

- 公网后台：`http://43.155.248.210`
- OpenAI 兼容 Base URL：`http://43.155.248.210/v1`
- 部署目录：`/opt/sub2api`
- 镜像：`weishaw/sub2api:latest`
- 容器：`sub2api`、`sub2api-postgres`、`sub2api-redis`、`sub2api-caddy`
- 凭据位置：服务器 `/opt/sub2api/.credentials.txt`
- 当前 API Key 名称：`codex-main`
- 当前账号：4 个 OpenAI OAuth 账号，均已绑定 `codex` 和 `gpt5.5` 分组

废弃/暂停事项：

- 暂停在这台 2G 服务器上源码 Docker build，本机内存会卡在前端构建，容易把机器打挂。
- 暂不把 GitHub commit `232bd7b7 fix openai sticky fallback scheduling` 自构建部署到线上；当前线上先用官方镜像 + 稳定配置跑通。
- 旧服务器数据已不保留，后续排查不得继续引用旧数据库里的账号、队列、usage 作为当前事实。

## 1. 目标说明

历史目标：定位 Codex 通过 Sub2API 使用 `gpt-5.5` 时出现队列卡顿的主要原因，并给出适合单人使用、最多两个 Codex 窗口的稳定优化方案。

当前目标：保持新服务器部署可用，优先保证 CC Switch 能通过 `Responses API` 访问 `gpt-5.5`。

## 2. 当前代码结构和关键文件

- `backend/internal/service/openai_account_scheduler.go`：OpenAI 账号调度、优先级、并发与负载选择逻辑。
- `backend/internal/service/scheduler_layered_filter_test.go`：账号调度优先级与过滤相关测试。
- `backend/migrations/001_init.sql`：账号表、优先级等字段的初始化定义。
- 线上 PostgreSQL：`accounts`、`account_groups`、`usage_logs`、`scheduler_outbox` 等运行态数据。
- 线上容器：`sub2api`、`sub2api-postgres`、`sub2api-redis`。

## 3. 具体实施步骤

1. 恢复会话上下文，确认上次最后问题和已改配置。
2. 读取线上服务、账号、队列和最近请求状态。
3. 分析队列卡顿证据：账号占用、慢请求、失败请求、队列等待、调度刷新是否正常。
4. 根据证据给出优化方案，优先配置级调整；如必须改代码，再单独列出改动范围。
5. 用 TDD 修复普通 `session_hash` 粘性账号满载仍等待的问题：先改测试确认旧逻辑失败，再改调度逻辑。
6. 执行必要验证：目标单测、相关调度测试；如本机无 Go，则使用远端临时 Docker Go 环境验证并记录限制。

## 4. 每一步要修改的文件

- `PLAN.md`。
- `backend/internal/service/openai_account_scheduler_test.go`：把旧的“粘性账号忙也继续等”测试改为“普通 session 粘性满载时回退到空闲账号”。
- `backend/internal/service/openai_account_scheduler.go`：调整 `session_hash` 粘性命中但账号槽位未获取时的回退逻辑；保持 `previous_response_id` 强连续链不随便换号。

## 5. 每一步完成后的验证方式

- 步骤 1：确认 CCSWITCH 恢复脚本输出了 transcript 和最后实质请求。
- 步骤 2：确认容器 healthy，并能读取账号、队列、使用日志。
- 步骤 3：用 SQL 和日志输出确认卡顿来源，不靠猜测。
- 步骤 4：每个优化项说明适用条件、收益和风险。
- 步骤 5：目标单测先失败，失败原因应为仍返回粘性账号 WaitPlan；生产逻辑修改后该目标单测通过。
- 步骤 6：运行相关 Go 测试；受本机缺少 Go 工具链影响时，记录远端 Docker 验证命令和结果。

## 6. 风险点和回滚/修正方案

- 风险：误把网络慢、上游慢、账号限流、应用队列混为一谈。
  - 修正：用 `usage_logs`、容器日志、账号状态分别验证。
- 风险：配置调得太激进导致单号被限流或更容易超时。
  - 修正：优先保持单号低并发，必要时小步调整并观察。
- 风险：直接改线上配置影响当前请求。
  - 修正：先只读诊断，确认根因后再执行配置变更。
- 风险：已有用户改动被覆盖。
  - 修正：修改前检查 git 状态，只编辑明确相关文件。

## 7. 当前进度 checklist

- [x] 恢复会话上下文
- [x] 确认仓库状态和线上容器健康
- [x] 读取账号、队列、使用日志和错误日志
- [x] 分析队列卡顿根因
- [x] 给出优化方案
- [x] 编写/调整回归测试
- [x] 验证回归测试红灯
- [x] 修改调度逻辑
- [x] 验证目标单测绿灯
- [x] 完整验证并记录结果
- [x] 按朋友 runbook 在重装后的服务器重新部署 Sub2API
- [x] 导入 `order-e69509b5-keys.txt` 中 4 个 OAuth 账号
- [x] 创建 `codex-main` API Key
- [x] 修复用户余额缓存导致的 `INSUFFICIENT_BALANCE`
- [x] 验证公网 `/v1/chat/completions` 可用
- [x] 验证公网 `/v1/responses` 可用
- [x] 明确 CC Switch 配置必须使用带 `/v1` 的 Base URL
- [x] 排查运维监控红色告警来源
- [x] 修复账号模型映射中的 `"*": "*"` 错误
- [x] 将 4 个 OpenAI OAuth 账号并发从 `1` 调整为 `2`
- [x] 验证 `gpt-5.4`、`gpt-5.4-mini`、`gpt-5.5` 的 `/v1/responses` 请求均返回 200

## 8. 排查记录

- 2026-05-24：已通过 `ccswitch_resume.py` 恢复会话，最后实质请求是继续分析 Codex 经 Sub2API 使用 `gpt-5.5` 时队列卡顿的优化方案。
- 2026-05-24：本地仓库 `git status --short` 无输出，当前无脏改动。
- 2026-05-24：线上 `sub2api`、`sub2api-postgres`、`sub2api-redis` 均为 healthy。
- 2026-05-24：旧服务器阶段 4 个 OpenAI-Codex 账号均为 `active`、`schedulable=true`、`concurrency=1`、`priority=50`，均绑定 `codex` 分组，无冷却、限流或临时不可调度状态。
- 2026-05-24：Redis 实时并发显示当前仅 `concurrency:account:2` 与 `concurrency:user:1` 有槽位占用，账号 #1/#3/#4 未占用槽位。
- 2026-05-24：服务日志出现 `account_id=2` 的 `timeout waiting for account concurrency slot`，同时截图显示 `OPENAI 1/4` 且 `队列 1`。根因指向 OpenAI 粘性会话命中账号 #2 后返回账号等待计划，没有转向空闲账号。
- 2026-05-24：代码确认 `openai_account_scheduler.go` 中调度顺序为 `previous_response_id` -> `session_hash` -> `load_balance`；`session_hash` 命中账号但槽位满时直接返回 `WaitPlan`，默认 `sticky_session_wait_timeout=120s`、`sticky_session_max_waiting=3`。
- 2026-05-24：已将 `SessionStickyBusyKeepsSticky` 回归测试改为 `SessionStickyBusyFallsBackToIdleAccount`，期望普通 session 粘性账号满载时切到空闲账号 #21002。
- 2026-05-24：本机 PowerShell 环境未发现 Go 工具链和 Docker CLI，需使用远端临时 Docker Go 环境验证。
- 2026-05-24：远端 SSH 曾出现 `Connection timed out during banner exchange`，这是验证环境连接问题，不能视为测试结果。
- 2026-05-24：用户正在重启服务器，远端验证暂停；本地继续阅读调度代码，确认 `previous_response_id` 独立优先层不应参与本次回退改动。
- 2026-05-24：服务器重启完成后，改用 GitHub 临时 clone + apply 测试 diff 的轻量方式跑红灯；`docker run --cpus=1 --memory=1536m` 仍超过 240 秒未返回，随后 SSH 握手超时。判定当前远端不适合作为 Go 编译测试机，红灯验证暂记为环境阻塞。
- 2026-05-24：已修改 `openai_account_scheduler.go`：普通 `session_hash` 粘性账号未获取并发槽时不再返回粘性 WaitPlan，而是返回 nil 让调度继续进入负载均衡层；`previous_response_id` 强连续层未修改。
- 2026-05-24：改用本机临时便携 Go `go1.26.3 windows/amd64` 验证。临时恢复旧 WaitPlan 逻辑后运行 `go test ./internal/service -run TestOpenAIGatewayService_SelectAccountWithScheduler_SessionStickyBusyFallsBackToIdleAccount -count=1`，测试按预期失败：期望账号 #21002，实际账号 #21001。
- 2026-05-24：恢复修复版后运行同一目标单测，通过。
- 2026-05-24：运行相关调度测试 `go test ./internal/service -run 'TestOpenAIGatewayService_SelectAccountWithScheduler|TestOpenAIAccountScheduler|TestOpenAIAccountSchedule|TestOpenAIWSAccountSticky|TestDefaultOpenAI' -count=1`，通过。
- 2026-05-24：运行完整 `internal/service` 包测试 `go test ./internal/service -count=1`，通过。
- 2026-05-24：已提交 `232bd7b7 fix openai sticky fallback scheduling`，并推送到 `origin/windowstats-20260524`。首次 push 遇到 TLS 握手失败，重试后成功。

## 9. 新服务器部署记录

- 2026-05-24：用户重装腾讯云轻量服务器，IP 为 `43.155.248.210`，系统为 Ubuntu 24.04。
- 2026-05-24：服务器已安装 Docker `29.1.3` 与 Docker Compose `2.40.3`。
- 2026-05-24：按 `sub2api-install-runbook-public(1).md` 在 `/opt/sub2api` 部署四容器方案。
- 2026-05-24：`JWT_EXPIRE_HOUR=720` 会导致服务启动失败，已修正为 `JWT_EXPIRE_HOUR=168`。
- 2026-05-24：服务器源码构建曾因 2G 内存不足在前端构建阶段 OOM，因此当前线上不走源码构建。
- 2026-05-24：当前容器状态验证：`sub2api` healthy、Postgres healthy、Redis healthy、Caddy running。
- 2026-05-24：公网后台 `http://43.155.248.210` 返回 200。

## 10. 当前运行配置

- 登录邮箱：`admin@sub2api.local`
- 登录密码：记录在服务器 `/opt/sub2api/.credentials.txt`
- API Key：记录在服务器 `/opt/sub2api/.credentials.txt`，名称为 `codex-main`
- OpenAI 分组：`codex`
- 兼容模型名：`gpt-5.5`
- 负载策略：`round-robin`
- OpenAI OAuth 账号并发：每号 `2`
- `allow_ungrouped_key_scheduling=false`
- `openai_advanced_scheduler_enabled=false`
- `openai_fast_policy_settings={"rules":[]}`

## 11. CC Switch 配置

CC Switch 的供应商配置应使用：

- API 请求地址：`http://43.155.248.210/v1`
- 模型名称：`gpt-5.5`
- API Key：使用 `codex-main`
- `auth.json` 中 `OPENAI_API_KEY` 填同一个 API Key

注意：不要填 `http://43.155.248.210`。实测 `/v1/responses` 正常返回 200，而不带 `/v1` 的 `/responses` 请求会卡住/超时。这个坑挺阴，别再踩。

## 12. 当前验证记录

- 2026-05-24：清理 Redis `apikey:auth:*` 后，`INSUFFICIENT_BALANCE` 消失。
- 2026-05-24：公网 `POST http://43.155.248.210/v1/chat/completions` 返回 200，模型 `gpt-5.5` 成功回复。
- 2026-05-24：公网 `POST http://43.155.248.210/v1/responses` 返回 200，输出文本为 `ok`。
- 2026-05-24：数据库确认 `accounts_total=4`、`active_schedulable_accounts=4`、`codex_group_accounts=4`、`active_api_keys=1`。
- 2026-05-25：运维监控红色告警主要来自旧配置产生的 `gpt-5.4` / `gpt-5.4-mini` 502，以及一次未带 `/v1` 的 `/responses` 长耗时请求。
- 2026-05-25：账号 `model_mapping` 原先包含 `"*": "*"`，导致未显式映射的模型被改写成字面量 `*`，上游返回 `The '*' model is not supported when using Codex with a ChatGPT account.`。
- 2026-05-25：已将 4 个 OpenAI OAuth 账号的 `model_mapping` 改为显式映射：`gpt-5`、`gpt-5.1`、`gpt-5.3-codex`、`gpt-5.4`、`gpt-5.4-mini`、`gpt-5.5`，不再保留 `"*": "*"`。
- 2026-05-25：修改账号映射后需要重启 `sub2api` 容器，否则进程内账号快照仍可能继续使用旧映射。
- 2026-05-25：已将 4 个 OpenAI OAuth 账号并发从 `1` 调整为 `2`，用于缓解官方镜像仍存在的粘性账号忙时等待问题。
- 2026-05-25：并发验证 `gpt-5.5`、`gpt-5.4`、`gpt-5.4-mini` 的 `/v1/responses` 请求均返回 HTTP 200。
- 2026-05-25：继续复查时确认公网 `POST http://43.155.248.210/v1/responses` 对 `gpt-5.5`、`gpt-5.4`、`gpt-5.4-mini` 仍可直接返回 HTTP 200，说明模型映射修复未回退。
- 2026-05-25：数据库最近 `usage_logs` 显示 `gpt-5.5` 当前仍按 `gpt-5.5→gpt-5.4` 映射落到上游 `gpt-5.4`，`gpt-5.4-mini` 也映射到上游 `gpt-5.4`，与预期配置一致。
- 2026-05-25：最近 6 小时 `ops_error_logs` 中残留的主要异常已不再是 `The '*' model is not supported...`，而是上游 `https://chatgpt.com/backend-api/codex/responses` 偶发 `http2: timeout awaiting response headers`，对应外部表现为 `/v1/responses` 约 600 秒后返回 502。
- 2026-05-25：账号快照复查确认 4 个 OpenAI OAuth 账号仍全部为 `active`、`schedulable=true`、`concurrency=2`，当前没有证据表明 `"*": "*"` 映射错误或本地并发配置回退。
- 2026-05-25：代码复查确认 OpenAI `Forward` 与 OAuth passthrough 在 `httpUpstream.Do(...)` 返回超时错误时，原先只会写普通 `502 upstream_error`，不会包装成 `UpstreamFailoverError`，因此 handler 无法切号。
- 2026-05-25：配置默认 `gateway.response_header_timeout=600`，而 `repository/http_upstream.go` 内部回退默认值仍为 `300s`，两处都过长且口径不一致，会放大“会话像死掉一样不动”的体感。

## 13. 后续如果要继续优化

1. 先确认当前官方镜像是否仍有队列卡顿。
2. 如果卡顿复现，再决定是否把 `232bd7b7` 做成远端构建产物或在更大机器上构建镜像。
3. 不要在当前 2G 服务器上直接跑完整源码构建。
4. 每次改余额、API Key、用户状态后，如果接口仍读旧状态，优先清 Redis `apikey:auth:*`。
5. 每次改账号 `credentials.model_mapping` 或 `concurrency` 后，优先重启 `sub2api` 容器刷新进程内快照。
6. 运维监控的近 1 小时 SLA/错误率会被历史错误拖累，修复后需要等窗口滚动或切换更短时间范围再看。
7. 如果后续再次出现长时间 502，先查 `ops_error_logs.upstream_error_message` 是否仍为 `http2: timeout awaiting response headers`；这类属于上游超时，不要再误判成 `"*": "*"` 映射问题。

## 14. 本轮新增优化目标（2026-05-25）

### 目标

将 OpenAI `/v1/responses` 单账号“像死掉一样不动”的等待时间压到 30 秒以内。优先解决“请求已经发到上游，但迟迟等不到响应头，导致本地一直不切号”的问题。

### 现状判断

- 当前 handler 只有在 `Forward(...)` 返回错误后，才会进入 failover 切号逻辑。
- 现网日志已确认存在上游 `https://chatgpt.com/backend-api/codex/responses` 长时间无响应头，最终报 `http2: timeout awaiting response headers` 的情况。
- 因为错误返回太晚，导致单会话体感像“死掉”，即使还有其他可用账号也不会立刻切换。

### 实施步骤

1. 定位 `OpenAIGatewayService.Forward(...)` 内部 OpenAI HTTP 上游调用点。
2. 增加针对 OpenAI Responses 上游“响应头等待超时”的可配置超时控制，目标值不高于 30 秒。
3. 当命中该类超时且尚未向客户端写出字节时，将其包装为 `UpstreamFailoverError`，让 handler 走现有切号逻辑。
4. 保持“已经写出流内容时不得切号”的保护逻辑不变，避免流拼接损坏。
5. 运行目标测试与相关回归测试，记录结果。

### 预期修改文件

- `backend/internal/service/openai_gateway_service.go`
- `backend/internal/service/openai_gateway_service_test.go`
- 如需要配置项：`backend/internal/config/config.go`

### 验证方式

- 先新增失败测试：模拟 OpenAI 上游响应头超时，期望返回 `UpstreamFailoverError`。
- 实现后重跑目标测试，确认由红转绿。
- 补跑 OpenAI Gateway 相关测试，确认未破坏现有 failover 行为。

### 风险与修正

- 风险：超时阈值过短，误伤本可成功的慢请求。
  - 修正：先以“30 秒以内”为上限，优先从 20-30 秒区间实现，必要时再调。
- 风险：把已开始流式输出的请求错误地包装成切号错误，导致双流拼接。
  - 修正：仅在“未向客户端写出任何字节”时允许该超时触发 failover。
- 风险：只改 Responses，遗漏 Chat Completions 或其他 OpenAI 入口的一致性。
  - 修正：本轮先限定 `/v1/responses` 主痛点，避免范围失控。

### 本轮实施结果

- 已新增 `TestOpenAIGatewayService_ForwardUpstreamTimeoutReturnsFailover`，先红后绿：初始错误为 `upstream request failed: context deadline exceeded`，修复后返回 `UpstreamFailoverError`。
- 已新增 `TestOpenAIGatewayService_OpenAIPassthroughTimeoutReturnsFailover`，验证 OAuth passthrough 路径命中同类超时时也会返回 `UpstreamFailoverError`。
- 已新增超时识别逻辑：`context deadline exceeded`、`net.Error.Timeout()`、`timeout awaiting response headers` 统一视为 OpenAI 上游响应头超时，并在尚未写出客户端字节时触发 failover。
- 已将默认 `gateway.response_header_timeout` 从 `600` 秒收敛到 `30` 秒。
- 已将 `repository/http_upstream.go` 的内部回退默认响应头超时从 `300s` 收敛到 `30s`，避免配置默认值与实现默认值打架。

### 本轮验证结果

- `go test ./internal/service -run TestOpenAIGatewayService_ForwardUpstreamTimeoutReturnsFailover -count=1` 通过。
- `go test ./internal/service -run TestOpenAIGatewayService_OpenAIPassthroughTimeoutReturnsFailover -count=1` 通过。
- `go test ./internal/service -run 'TestOpenAIStreaming(ReadErrorBeforeOutputReturnsFailover|ResponseFailedBeforeOutputReturnsFailover|ResponseFailedBeforeOutputCapacityErrorReturnsFailover)' -count=1` 通过。
- `go test ./internal/service -run 'TestOpenAIGatewayService_(ResponsesUnknownModelDoesNotFallbackToGPT54|OAuthMessagesBridgeDoesNotInjectDefaultInstructions|ForwardUpstreamTimeoutReturnsFailover|OpenAIPassthroughTimeoutReturnsFailover)' -count=1` 通过。
- `go test ./internal/repository -run 'TestHTTPUpstreamSuite/(TestDefaultResponseHeaderTimeout|TestCustomResponseHeaderTimeout)' -count=1` 通过。
