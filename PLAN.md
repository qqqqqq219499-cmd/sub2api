# PLAN

## 目标

修复 OpenAI/Codex API 调用中单个会话长时间不产出首 token、导致监控 TTFT/P99 被一个卡死会话拖到十几分钟的问题。

## 当前事实

- 监控截图显示 `TTFT P99` 约 1220 秒，`请求时长 P99` 约 1249 秒。
- HTTP 流式路径已有 `gateway.stream_data_interval_timeout`，默认 180 秒，只能处理“无上游数据”。
- WebSocket relay 的 idle timeout 按任意上下游活动刷新；若上游持续发送非 token 状态帧，idle timeout 不会触发，但客户端仍无可见输出。

## 计划

- [x] 定位 API 服务仓库 `E:\xm\sub2api\sub2api-src`。
- [x] 检查现有未提交改动，避免回滚用户修改。
- [x] 新增 WebSocket relay 首 token 超时回归测试。
- [x] 新增 HTTP `/v1/responses` 流式首 token 超时回归测试。
- [x] 实现首 token 超时与配置入口。
- [x] 跑相关 Go 测试验证。

## 风险

- 当前仓库已有未提交改动：`backend/internal/config/config.go`、`backend/internal/service/account.go`、`backend/internal/service/token_refresh_service.go` 等。后续只追加必要变更，不回滚这些内容。
- 首 token 超时过短会误杀真正排队但仍可能成功的请求；默认值需要保守。

---

## 追加任务：OpenAI/Codex 7d 额度低者优先

### 目标

在同一人工 `priority` 档位内，让 OpenAI/Codex OAuth 账号按 `codex_7d_used_percent` 越高越优先调度，从而优先用完 7d 剩余额度更少的账号。

### 计划

- [x] 确认现有调度路径：旧负载感知路径、OpenAI 专用负载路径、高级调度 Top-K。
- [x] 先补排序/Top-K 回归测试，确认现有逻辑不会按 7d 剩余额度排序。
- [x] 实现共享的 `OpenAICodex7dUsedPercentForScheduling`，过期快照或已重置窗口按 0 处理。
- [x] 在同 `priority` 内，把 7d 已用百分比高的账号排到低负载/LRU 前面。
- [x] 跑相关 Go 测试验证。

### 风险

- 该策略只在已有 `codex_usage_updated_at` 且快照未过期时生效；无快照账号按 0 处理。
- `priority` 仍是最高人工控制项；低优先级兜底号不会因为 7d 用量高而抢过高优先级主用号。

---

## 上线记录

- [x] 本机通过 `go test -tags unit ./internal/service`。
- [x] 上传当前源码快照到服务器新构建目录 `/home/ubuntu/sub2api-builds/20260527222147-codex-7d-scheduler`。
- [x] 服务器构建镜像 `sub2api:v0.1.131-codex-7d-20260527222539`。
- [x] 备份线上 compose 为 `/opt/sub2api/docker-compose.yml.bak.20260527224330`。
- [x] 仅重建并启动 `sub2api` 服务，Postgres/Redis/Caddy 未重建。
- [x] 线上容器健康检查为 `healthy`，版本输出 `Sub2API 0.1.131 (commit: codex-7d-scheduler, built: 2026-05-27T14:31:22Z)`。

---

## 官方 0.1.132 同步检查

- [x] 2026-05-27 拉取官方 `origin/main`，最新为 `v0.1.132` 后的 `89d96f4b`。
- [x] 将本地补丁 rebase 到官方 `origin/main` 之后，保留为单个本地提交。
- [x] 官方新增 `gateway.openai_response_header_timeout`，负责等待上游响应头；与本地 `stream_first_token_timeout` / `openai_ws.first_token_timeout_seconds` 的首个可见 token 超时不是重复补丁，已同时保留。
- [x] 官方新增 OpenAI WS rate-limit failover，冲突处采用官方新版 relay 结构，只把本地 `FirstTokenTimeout` 接入官方 `RelayOptions`。
- [x] 官方已有 `codex_7d_used_percent` 数据写入和展示，但未提供“同 priority 下 7d 已用百分比高者优先调度”；本地调度补丁仍保留。
- [x] 官方未提供 `token_refresh.openai_background_refresh_enabled`，本地 OpenAI 后台刷新默认关闭补丁仍保留。
- [x] 验证通过：`go test -count=1 -tags unit ./internal/service`、`go test -count=1 ./internal/config`、`go test -count=1 ./...`。
- [x] 2026-05-27 已上线 `sub2api:v0.1.132-codex-patches-20260527232530`。
- [x] 服务器构建目录：`/home/ubuntu/sub2api-builds/20260527232514-v132-codex-patches`。
- [x] `/opt/sub2api/docker-compose.yml` 备份：`/opt/sub2api/docker-compose.yml.bak.20260527234156`。
- [x] 仅重建 `sub2api` 服务；上线后容器 `healthy`，版本输出 `Sub2API 0.1.132 (commit: ef545d6e, built: 2026-05-27T15:30:57Z)`，本地 `/health` 返回 `{"status":"ok"}`，public settings 返回 `version=0.1.132`。

---

## GHCR 安全发布方案

目标：后续不要再在 2G 生产服务器上本地构建镜像；改为 GitHub Actions 构建并推送 GHCR，服务器只拉取指定镜像、切换 `sub2api` 服务、健康检查，失败自动回滚。

### 计划

- [x] 新增 GitHub Actions workflow：`.github/workflows/custom-ghcr-image.yml`。
- [x] workflow 支持手动输入 `version`、可选 `image_repository`、可选 `image_tag`，默认生成 `v<version>-codex-<short_sha>`。
- [x] workflow 默认先跑 `go test -count=1 ./...`，通过后再构建并推送 GHCR 镜像。
- [x] Dockerfile 增加 `FRONTEND_NODE_OPTIONS` build arg，默认 `--max-old-space-size=2048`，避免前端构建 OOM 需要临时改 Dockerfile。
- [x] 新增服务器部署脚本：`deploy/deploy-ghcr-image.sh`。
- [x] 部署脚本只替换 compose 中 `sub2api` 服务的镜像，只重建 `sub2api`，不重建 Postgres/Redis/Caddy。
- [x] 部署脚本支持健康检查、版本/commit 校验、失败恢复 compose 备份并回滚旧镜像。
- [x] 文档：`deploy/GHCR_DEPLOYMENT.md` 和 `deploy/README.md`。

### 后续发布命令

GitHub Actions 构建成功后，在服务器执行：

```bash
cd /opt/sub2api
bash /path/to/deploy-ghcr-image.sh \
  --image ghcr.io/<owner>/<repo>:v0.1.132-codex-1d890031 \
  --expected-version 0.1.132 \
  --expected-commit 1d890031
```

### 验证

- [x] `D:\Program Files\Git\bin\bash.exe -n deploy/deploy-ghcr-image.sh`
- [x] Python/PyYAML 解析 `.github/workflows/custom-ghcr-image.yml`
- [x] `git diff --check`
- [x] `go test -count=1 ./...`

### GitHub 分支

- [x] 已添加 fork 远端：`qfork=https://github.com/qqqqqq219499-cmd/sub2api.git`。
- [x] 未覆盖 fork 的 `main`，因为该分支仍在 `0.1.130-windowstats` 自定义线。
- [x] 已推送安全分支：`codex/v132-ghcr-deploy`。
- [x] PR 地址：`https://github.com/qqqqqq219499-cmd/sub2api/pull/new/codex/v132-ghcr-deploy`。

---

## 追加任务：OpenAI/Codex 调度与有限轮询

### 目标

修复调度缓存看不到 Codex 5h/7d 快照的问题，并调整 OpenAI/Codex 调度策略：

- `priority=99` 作为保护/备用池，不参与普通调度优先规则。
- 普通账号同 priority 下优先使用 7d 已用比例更高者；7d 相同再按创建时间 FIFO。
- 额度已耗尽但没有运行时限流状态的账号，也要被调度排除。
- Codex 5h 用量快照 `>95%` 时提前视为限流，避免打到临界账号。
- 允许后台轮询 Codex 用量快照，但只轮询最近 24 小时内被调用过的普通 OpenAI OAuth 账号，且 `priority=99` 不参与。

### 计划

- [x] 补 scheduler metadata 回归测试，确认 `codex_*` 和 `created_at` 不被缓存瘦身过滤。
- [x] 补普通排序、高级 scheduler、OpenAI 专用 load-aware 排序测试。
- [x] 用 `priority=99` 替代写死账号 `1/2` 的保护池逻辑。
- [x] 补 `5h=100%` 且 `rate_limit_reset_at` 为空时不可调度的测试。
- [x] 补有限后台 Codex 快照轮询测试：24 小时内被调用过才轮询，`priority=99` 跳过。
- [x] 实现有限后台 Codex 快照轮询。
- [x] 补 Codex 5h `>95%` 提前限流测试，并保持 `95.0%` 边界可调度。
- [x] 实现 Codex 5h `>95%` 提前限流。
- [x] 跑相关 Go 测试与 `git diff --check`。

### 风险

- Codex 快照探测会请求 ChatGPT Codex backend；必须避免全量扫冷账号。
- `last_used_at` 是延迟批量写入，刚被调用的账号可能要等一次 flush 后才进入后台轮询候选；请求路径返回头仍会即时更新快照。
- 2026-05-28 已上线镜像 `sub2api:v0.1.132-codex-quota-17c97ff1-20260528053111`；只重建 `sub2api` 服务，Postgres/Redis/Caddy 未重建。

### 上线记录

- [x] 代码补丁对当前线上源码目录 `/home/ubuntu/sub2api-builds/20260527232514-v132-codex-patches` 执行 `git apply --check` 通过；`PLAN.md` 因服务器构建目录账本不同未作为冲突依据。
- [x] 本机验证通过：`go test -count=1 -tags unit ./internal/repository ./internal/service`、`go test -count=1 ./internal/service`、`go test -count=1 ./cmd/server`、`git diff --check`。
- [x] 本地提交：`17c97ff1 fix: tune codex quota scheduling`。
- [x] 上传源码快照并在服务器构建目录 `/home/ubuntu/sub2api-builds/20260528053111-v132-codex-quota-17c97ff1` 构建镜像 `sub2api:v0.1.132-codex-quota-17c97ff1-20260528053111`。
- [x] 备份线上 compose：`/opt/sub2api/docker-compose.yml.bak.20260528055154`。
- [x] 仅重建 `sub2api` 服务；上线后容器归属 `/opt/sub2api`，容器 `healthy`，`restart=0`，版本输出 `Sub2API 0.1.132 (commit: 17c97ff1, built: 2026-05-27T21:37:18Z)`，本机和公网 `/health` 均返回 `{"status":"ok"}`。
