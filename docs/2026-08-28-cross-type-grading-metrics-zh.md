# 2026-08-28 — 跨作业评分摘要一致性修复

## 背景和范围

前次兼容反引号后，详情页能恢复 Score/Grammar，但 assignment 的提交列表仍可能显示旧的 0 / 9 / 0。本次继续修复列表、详情、前端排序/平均分/Excel 使用不同规则的问题。此前修复见 [JSON 与补充练习兼容说明](2026-08-28-grading-json-supplement-pdf-compatibility-zh.md)。

本次基于 `bf074a3`，目标分支 `bobby-codex-backend`。不修改数据库，不重新批改、不重跑 AI、不更新学生提交、不发布成绩、不部署 production。

## 统一读取规则

新增只读 `EssayGradingMetrics`，由以下入口共用：

- `GET /api/v1/essay_assignments/:id` 的紧凑提交摘要，经 `EssayGradingSubmissionPayloadBuilder`。
- `GET /api/v1/essay_gradings/:id` 的详情评分。
- School API 的 assignment submissions，继续使用同一个 payload builder。

原有字段保留，并增加 `metrics_version: 1`：

| 字段 | 约定 |
| --- | --- |
| `score`、`overall_score` | 同一有效总分；缺失/无法识别为 null，真实零为 0 |
| `full_score`、列表 `the_full_score` | 有依据的满分；缺失为 null |
| `number_of_suggestion` | 有效错误数量；不能判定时为 null；不适用类型为 null |
| `scores` | 规范化后的 criterion/band 分项，不包含完整反馈正文 |
| `metrics_version` | 1 表示以上 null 具有权威性，客户端不得再拿旧字段或默认零覆盖 |

数值只接受有限数字/可解析数字字符串；布尔、空值、无效文本不转成 0。兼容原有外层代码围栏、单反引号和双重编码；损坏的数据不猜测修复。

## 各类型处理

- **Essay / Speaking Conversation**：优先已保存的 teacher review score，否则解析原始文本。有效 grammar 中重算 Suggestions，不再让历史缓存的 0 覆盖结果。老师明确保存的空错误列表仍是 0。Conversation 原有界面没有总分列，本次不新增。
- **Sentence Builder**：老师已保存的 grammar sentences 优先于原 AI/native score。明确 `isCorrect` / `is_correct` 优先；否则空 errors 或全部 Correct 标记为正确。每句最多记一分。没有完整可判定的句子集合，不能算为 0 或缩小分母。优先作业配置的 vocab 数量作为满分，其次 native 满分，再次完整结果数。空老师覆盖不回退原 AI 分数。原生 score 存在且没有老师覆盖时仍可读取。
- **Speaking Essay**：支持 native report、meta report、原始文本中的 scores/旧版 Overall Score；老师改判优先，保留明确 Full Score。确实存在 IELTS band score 时才使用 9 作为 band 满分，不能把缺失数据变成 0/9。
- **Sentence Puzzle**：读取 meta attempt、grading attempt、grading.meta attempt、兼容后的旧文本 attempt、旧 sentence_puzzle 字段。列表与详情同源，未知不伪造零。
- **Comprehension**：优先 full_score，旧资料缺该字段时才以 questions_count 补充。正常明确分数不变。
- **Listening**：保留有效 score/full_score；缺失分数为 null。
- **Speaking Pronunciation**：满分维持已定义的 100；保存的分数保持小数，不再在列表 to_i 截断；缺失 score 为 null。

这不是重新设计评分算法。无法恢复的原始记录仍需要人工检查；不会凭推测补造分数。

## 权限、性能和兼容性

- 原有 owner/shared/student 的授权及 release-score 逻辑未变。
- 学年筛选、分页、派发、学生 403 修复均不改动。
- assignment 列表仍返回紧凑摘要，不追加每条 grading 的详情请求、不加载所有年份。
- Web 列表已预加载 assignment；School submissions 补齐该预加载，避免 Sentence Builder 读取 vocab 时逐条查 assignment。
- GET 仅从已有数据计算，无 UPDATE、无异步重批改任务；集成测试逐条比对读取前后记录完全不变。
- 新客户端有旧响应兼容路径，但旧客户端可能自行把 null 显示成 0，所以前后端应配套部署。
- 微信原生小程序仓库未修改；共用 API 的评分值同步修正，原生 UI 是否仍有 `|| 0` 需要其维护者验收。网页及小程序内嵌 WebView 使用本次 frontend 修复。
- 本次不是所有历史导出/统计 API 的改造；验证范围为上述读取入口和网页 assignment 的 Excel/统计展示。School API 原有数据库 score 排序不是本次浏览器端排序实现。

## 回归测试与安全环境

使用独立本地 PostgreSQL 测试库 `codex_grading_json_test_20260828`，显式 `RAILS_ENV=test`、本地 `DATABASE_URL` 和 `TEST_VECTOR_DATABASE_URL`，Ruby 3.1.0。没有连接生产数据库执行测试。不要把这些测试改为 production 环境运行。

核心用例在 `test/integration/assignment_grading_summary_test.rb`，真实经过带测试 JWT 的 Rails API，不是单纯模拟返回值：

- 8 个类型分别验证真实 0 与缺失值。
- Essay 普通/单反引号/围栏/object/双重编码，列表和详情相同。
- Teacher override、空覆盖、Sentence Builder 部分或损坏结果。
- Speaking Essay wrapped band、显式满分、老师覆盖。
- Puzzle 多种旧/新位置。
- Comprehension full_score-only、questions_count fallback。
- Pronunciation 小数。
- 断言分数/满分/建议数/分项/版本一致，以及 GET 不改数据。

完整相关回归包含 JSON parser、补充练习读取/保存/提交/PDF、学生授权、共享、Release Scores、学年过滤/回填、Puzzle draft/report。命令文件清单：

```text
test/services/ai_json_parser_test.rb
test/services/grading_json_consumers_test.rb
test/integration/supplement_practice_json_compatibility_test.rb
test/integration/assigned_essay_assignment_access_test.rb
test/controllers/api/v1/essay_assignments_controller_test.rb
test/integration/essay_assignment_shares_api_test.rb
test/services/essay_assignment_share_service_test.rb
test/services/essay_assignment_academic_year_filter_test.rb
test/services/student_academic_year_filter_test.rb
test/services/student_academic_year_filter_integration_test.rb
test/migrations/add_school_academic_year_to_essay_assignments_test.rb
test/integration/sentence_puzzle_draft_and_report_test.rb
test/integration/assignment_grading_summary_test.rb
```

在已配置上述隔离环境后，运行 `ruby -rlogger -rbundler/setup bin/rails test <以上文件> --seed <seed>`。

最终验证记录见本文件末尾。已有 wkhtmltopdf 路径、Rswag 和 HABTM 启动警告不属于本次新增失败。

## 部署与线上验收（尚未执行）

1. 部署目标 backend 分支，再部署配套 frontend。此增量没有 migration、backfill 或数据清理步骤。
2. 用获授权老师账号打开用户报告的 assignment，比较异常提交的列表与详情 Suggestions / Full Score / Score，并导出 Excel。
3. 确认摘要和详情都有 metrics_version=1；没有该字段时先确认服务进程是否实际更新。
4. 正确记录、真实 0 分、损坏记录各验证一次；损坏记录应提示不可用/显示空值，不能再次伪装 0 分。
5. 测试老师改判保存后刷新列表，以及学生已发布/未发布成绩和共享权限。
6. 在桌面、手机和小程序 WebView 各检查；原生微信 UI 另由该端验收。
7. 不应为了显示分数而重新提交、重新发布成绩或重批改生产记录。

尚未使用用户真实生产登录态读取并验收所报告记录。HTTP 200 页面壳不证明真实数据正确。本地 API 回归是已知构造数据，不能描述为 production 已恢复。

回滚用本增量提交的 revert 并重新部署；配套 frontend 一并回滚可恢复旧显示。无需数据库回滚，先前 JSON/PDF 和学年/权限修复保持不变。

## 最终验证记录

2026-08-28 本地验证：

- 完整相关回归随机种子 2817、2818、2819：每轮 162 tests / 1,270 assertions，0 failures、0 errors、0 skips。
- 前端配套回归 83 tests，通过；包含实际组件/导出/排序执行。
- 新服务 Ruby 语法及两仓库 git diff --check 通过。
- Frontend TypeScript、targeted ESLint（0 errors，2 条原有 Hook warnings）、production build 通过。
- 本地 production-mode Next 服务 3001 已启动，assignment 路由 HTTP 200；这只证明页面壳可用，不代表已登录验收真实 API 数据。
- 推送前重新 fetch，对应目标分支没有远端未合并提交；不 force push。
- 没有执行 production 部署、migration、重批改或生产写入。
