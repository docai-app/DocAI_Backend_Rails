# 总 Admin 主批改 Rerun：明确覆盖旧任务

## 交付状态与原因

2026-09-17，本地 Rails Backend `development` 修改。**未 push、未部署；本次没有重跑正式记录，也没有新增或修改 migration／数据库结构。** 工作区已有的 Comprehension 草稿改动独立保留，不属于此补丁。

用户要求总 Admin 能人工重跑被 `unknown` 等状态挡住的主批改。旧实现把普通重试的安全门槛也用于 Admin，导致已经失联的任务无法通过管理页面重新发起；批量接口还只接受 pending/stopped。

新策略区分「自动判断是否应恢复」与「管理员明确要求重新批改」。Admin 主 Rerun 不再按任务状态拒绝请求，但认证、记录存在性、事务一致性和学生答案保护继续生效。这不是关闭全部安全检查。

## 接口与具体规则

- `POST /api/admin/v1/essay_gradings/:id/rerun_workflow`
- `POST /api/admin/v1/essay_gradings/bulk_rerun_workflow`

这两个已受 Admin 身份验证保护的入口调用 `EssayGenerationRun.request_admin_rerun!`，不是从请求参数读取一个可供普通用户传入的 force 开关。

1. queued、running、checking、retry_wait、unknown、ready、failed、cancelled 均可由 Admin 发起新一轮；主记录 pending、stopped、graded、draft 也不再被批量接口拒绝。不存在的记录仍返回失败，批量逐项报告。
2. 在同一 grading 行锁／事务内更换主任务 token、清空本轮完成阶段和未知结果上下文，重设本轮重试预算；主记录变为 pending。每次明确的 Admin 请求算新一轮，仍沿用每轮最多 3 次执行规则，不是无限自动重试。
3. 旧 queue 投递不能领取新任务；已在执行的旧任务不能保存阶段结果、错误摘要或更新新任务状态。完成通知发送前也核对当前 token，避免旧 worker 因新任务已 ready 而误发通知。已经发送中的外部请求／通知不能撤回。
4. 如有 active 的补充练习任务，同一事务内先更换其 token。已有内容通过完整练习验证时保留 ready；否则标记 cancelled，主批改成功后再重新排该练习。主批改未成功不会提前启动新的练习。
5. 所有已保存的补充练习答案均保留；有答案时不重生练习。不会因主 Rerun 删除学生作答或历史成绩记录。若历史题目自身损坏但已有答案，本补丁不自动清理该冲突。
6. 现有有效练习继续重用；不会因为作文重跑就强行换题。主批改原内容在新结果验证并保存前保留，但状态为 pending，不代表旧内容是本轮结果。
7. `meta.admin_reruns` 保留最近 20 次操作摘要：时间、旧阶段状态、尝试次数、旧 Dify run ID。无密钥、作文正文或学生个人资料；现有 meta 字段保留。当前 Admin 服务 token 不提供个人操作者身份，不能宣称有个人级审计。

## 边界与风险

- **这是人工覆盖，不是确认原 Dify 已失败。** 已发给 Dify 的旧调用可能仍继续执行并计费；新调用也可能计费。token 只控制本系统采纳哪次结果，不保证取消外部运算。
- 连续多次 Admin 请求会替换前次 token。若前次尚未领取，旧 queue 项为无操作；若已调用 Dify，可能同时产生外部成本。前端现有请求期间按钮锁应保留，不自动重送结果不明的 POST。
- 正常进入现有 queue，不设管理员优先队列，不抢占其他学生的作业。Redis／worker 故障仍可能影响实际执行；接口的 `Workflow rerun requested` 表示请求及持久化任务已接受，不代表 Dify 或批改已完成。原有 outbox/失联恢复能力不变。
- 学生／老师普通 retry、自动失败重试、定期恢复的 unknown 安全规则不变。不能把 Admin override 用于这些入口。
- **独立的 `rerun_supplement_practice_workflow` 不在本次主 Rerun 放宽范围内**，其 active/unknown、主批改状态及已有答案保护仍生效。
- 不新增任何 assignment 类型的专属 workflow。沿用原主 Rerun 支持的处理路径，不能据此声称所有题型的供应商链路已重新验收。
- 总 Admin 前端未修改：现有 pending/stopped/graded 的按钮和批量 API 可以使用新的后端行为。单行 draft 按钮是否展示仍由现有 UI 决定；后端接口不再拒绝该状态。
- 无需新的环境变量或 migration；**需要部署 Backend web 和 worker 的配套代码后才生效**，仅改本地不会解除线上限制。

## 文件范围

- `app/models/essay_generation_run.rb`：Admin 专用入口、token 替换、关联练习处理、轻量审计。
- `app/controllers/api/admin/v1/essay_gradings_controller.rb`、`app/services/admin/essay_gradings/bulk_rerun_workflow_service.rb`：接入覆盖入口；去除批量状态白名单；成功文案不再宣称已经完成。
- `app/services/essay_grading_service.rb`：异常摘要写入也须校验当前 token。
- `app/sidekiq/essay_generation_job.rb`：完成通知前增加 token 检查。
- 新增 `test/integration/admin_grading_override_test.rb`；更新恢复边界及真实数据库并发测试。
- 更新 `AGENTS.md` 和原可靠性说明，明确 Admin 与普通重试的不同边界。

## 本地验证

首次针对测试：28 tests / 273 assertions，零失败。补充异常摘要及通知竞争测试后，联合回归 **111 tests / 1,080 assertions，0 failures / 0 errors / 0 skips**。

最后以固定不同顺序 `--seed 917` 重跑 Admin／恢复边界／并发，并加入既有 Comprehension 草稿 session/concurrency 测试：**44 tests / 420 assertions，零失败、错误或跳过**。两轮覆盖有重叠，不能相加当成独立测试总数。`git diff --check` 通过。

联合文件：`admin_grading_override_test`、`essay_generation_recovery_edges_test`、`essay_generation_concurrency_test`、`essay_generation_reliability_test`、`essay_generation_reconciler_test`、`essay_generation_schema_test`、`admin_api_authentication_test`、`operations_reporting_test`（位于 test/integration），以及 `dify_workflow_recovery_test`、`essay_generation_queue_snapshot_test`（位于 test/services）。

使用 Ruby 3.1.0、`RAILS_ENV=test`、`LISTENING_RAILS_ISOLATED_TEST=1`、`PARALLEL_WORKERS=1`、测试用 Azure/JWT 占位值，清除 DATABASE_URL/VECTOR_DATABASE_URL。数据库是现有 loopback 55439 的 `listening_rails_isolated_test`。Sidekiq fake、Dify/SMTP 受控替身；并发测试用真实 PostgreSQL 行锁。不是正式 Dify、生产队列或收件验收。测试启动存在既有 wkhtmltopdf、rswag、重复常量及正则警告，未作为本次修改范围关闭警告。

## 工程师发布与验收

1. 单独审查本补丁与目标分支差异；不要混入本地 Comprehension、Listening、output 或其他未验收内容。按授权推送后记录精确 commit；本文不代表已经 push。
2. 确认 Admin API 真正要求有效管理身份。未登录、普通学生/教师 JWT 均不得使用覆盖入口。
3. 安全切换对应 web/worker，避免旧版本继续写入；不为发布而强杀正在执行的 Dify 工作，不清空 Redis 或其他人的队列。本轮部署仍暂停，待用户另行确认。
4. 在测试环境用专用记录验收单笔与批量 unknown/running/graded 重跑；实际队列只有最新 token 可执行；旧结果不能覆盖新批改。确认带已保存补充练习答案的主重跑保留原答案。
5. 核对正常批改、普通学生 retry、最终失败邮件和恢复报告无回归。不要通过破坏正式 Dify 设置制造失败。
6. 如需回退，先协调 worker，保留数据与审计；回退会恢复 Admin unknown 状态的旧限制，不应删除任务、答案或新审计字段。
