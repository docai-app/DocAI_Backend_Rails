# Talk Lab — 后端 Dify Workflow Mock 架构方案

> **文档版本**：v1.0  
> **日期**：2026-07-07  
> **状态**：**已审核 — 可进入编码（Phase 1）**  
> **文档位置**：`DocAI_Backend_Rails/docs/`（Mock 方案与实现代码同属后端仓库）  
> **受众**：PM / 后端 / 前端 / QA

## 关联文档

| 文档 | 关系 |
|------|------|
| [Talk Lab 前端对接指南](./talk_lab_frontend_integration_guide.md) | API 与持久化契约 |
| [Talk Lab 需求方案](./talk_lab_speaking_assignment_package_requirement_plan.md) | 业务规则与数据模型 |
| [Talk Lab Admin 对接](./talk_lab_admin_integration_guide.md) | Dify 配置与返回要求 |
| [essay-checker 前端进度审核](../../essay-checker/docs/20260706-talk-lab-speaking-progress-review.md) | 前端已移除 Mock |
| [Dify Workflow Demo Prompt](../../essay-checker/docs/20260706-talk-lab-dify-workflow-prompt-demos.md) | Mock 出参 JSON 与真实 Dify 合约对齐 |

---

## 1. 背景与目标

### 1.1 现状

| 层级 | 状态 |
|------|------|
| **essay-checker 前端** | 已移除 Assignment Package / RTC Mock；按真实 API + Volc 运行 |
| **DocAI Rails 业务 API** | Talk Lab / Package / `my_assignments` 等已就绪 |
| **Dify Workflow** | PM 尚未配置正式 Prompt；三处 Workflow 未上线 |
| **端到端** | 前端提交后，后端 Sidekiq 调用 Dify → **无有效返回** → Package `failed` 或 Grading `stopped` |

### 1.2 本方案目标

在 **不改动前端**、**不重构现有 Dify 调用链路** 的前提下，于 **Rails 后端** 增加一层可开关的 Dify Mock，使以下流程可先跑通：

```
RTC 对话 → Rails 持久化 → Sidekiq →「模拟 Dify 返回」→ 解析/入库 → 前端展示
```

### 1.3 成功标准（Mock 阶段）

1. Quick Start：RTC 结束 → `POST assignment_packages` → Package `generating` → 数秒内 `active`，含 **4 个 `talk_lab_speaking` item**。
2. Package 内作业：start item → RTC → `POST essay_gradings` → Grading `pending` → Sidekiq 后变 **`graded`**，含分数与评估字段。
3. `my_assignments`、Package detail、grading 详情页可展示 Mock 产出数据。
4. 关闭 Mock 后（**一行配置**），同一套代码路径走真实 Dify，无需改 Service 编排。

---

## 2. 核心原则（架构决策）

### D1 — 前端零 Mock，后端承接

- essay-checker **不再**注入假 Package、假 token、假 grading id。
- 所有「假装 Dify 已响应」的逻辑 **仅在 DocAI_Backend_Rails**。

### D2 — 拦截在 Dify HTTP 边界，不改业务编排

现有编排 **保持不变**：

| 流程 | 现有链路（不动） |
|------|------------------|
| Package 生成 | `AssignmentPackageGenerationJob` → `GenerationService` → `DifyGenerationClient#call` → `CreateFromDifyResponseService` |
| Talk Lab 评分 | `EssayGradingJob` → `EssayGradingService#run_workflows` → `execute_workflow_streaming` → `process_streaming_response` → `update_final_status` |

Mock **只替换**「Dify HTTP 响应」，不跳过 Job、不跳过 `CreateFromDifyResponseService`、不手写旁路写库。

### D3 — 返回形态与真实 Dify 一致

Mock 必须返回与生产相同的 **外层结构**，确保下游解析器零修改：

- Package：`DifyGenerationClient` 期望的 `{ 'data' => { 'outputs' => { 'text' => <package_json> } } }` 形态。
- Grading / General Context：`EssayGradingService#process_streaming_response` 期望的 SSE chunk 数组（含 `workflow_finished` + `outputs.text`）。

### D4 — 单一开关，一行关闭

```ruby
# 关闭 Mock、恢复真实 Dify：改为 false 或删除该行
ENV['TALK_LAB_DIFY_MOCK'] == 'true'
```

实现上集中在 **`TalkLabSpeaking::DifyMock::Policy.enabled?`**，所有拦截点只调这一处。

### D5 — Mock 数据独立文件

```
DocAI_Backend_Rails/
  app/services/talk_lab_speaking/dify_mock/
    policy.rb          # enabled? 与环境变量
    responses.rb       # 三份 fixture + template_title 替换
```

### D6 — 可观测性

Mock 命中时：

- `assignment_packages.dify_response` / `essay_gradings.grading` 写入数据中带 `"_source": "talk_lab_dify_mock"`。
- Rails log 打 `[TalkLabDifyMock]` 前缀。

### D7 — 环境安全（已确认）

| 环境 | 策略 |
|------|------|
| `development` / `staging` | 允许 `TALK_LAB_DIFY_MOCK=true` |
| `production` | **`TALK_LAB_DIFY_MOCK=true` 时 boot 直接 raise**，禁止误开 |

---

## 3. 范围

### 3.1 In Scope

| # | Workflow | 拦截点 | Mock 行为 |
|---|----------|--------|-----------|
| W1 | Assignment Package Generator | `DifyGenerationClient#call` | 固定 4 个 `talk_lab_speaking`；title 含 `template_title` |
| W2 | Talk Lab Grading | `EssayGradingService#execute_workflow_streaming` | grading `outputs`（`text` + `score`） |
| W3 | Talk Lab General Context | 同上（general_context task） | `studentFeedback` 等字段 |

### 3.2 Out of Scope

- essay-checker 前端 Mock（已删除，不恢复）。
- Dify 正式 Prompt 配置（PM 后续）。
- transcript 动态生成不同作业（首期固定 fixture + title 替换）。
- `revised_essay`、非 Talk Lab category 的 Mock。

---

## 4. 总体架构

（分层图、时序图同 v0.1，见 §4.1–4.3；实现细节不变。）

### 4.1 分层图

```
essay-checker（真实前端）→ Rails 业务层（不变）→ Dify 客户端层（Mock 分支）→ Dify（Mock 期间不调）
```

### 4.2–4.3 时序

Package 生成与 Talk Lab 评分时序与 v0.1 一致：`GenerationJob` / `EssayGradingJob` → HTTP 边界 Mock → 现有 parser 入库。

---

## 5. 拦截点设计（实现规格）

### 5.1 W1 — Package Generator

**文件**：`app/services/assignment_packages/dify_generation_client.rb`

```ruby
if TalkLabSpeaking::DifyMock::Policy.enabled?
  return TalkLabSpeaking::DifyMock::Responses.package_dify_response(inputs: inputs)
end
```

**下游**：`CreateFromDifyResponseService` **零修改**。

### 5.2 W2 / W3 — Grading + General Context

**文件**：`app/services/essay_grading_service.rb`

```ruby
if talk_lab_speaking? && TalkLabSpeaking::DifyMock::Policy.enabled?
  stage = workflow_stage_from_task_id(task_id)
  return [TalkLabSpeaking::DifyMock::Responses.workflow_stream_chunks(stage: stage), task_id]
end
```

**下游**：`process_streaming_response`、`update_final_status` **零修改**。

---

## 6. Mock 数据规格

> JSON 字段详解见 [essay-checker Dify Demo Prompt](../../essay-checker/docs/20260706-talk-lab-dify-workflow-prompt-demos.md)。

### 6.1 W1 — Package Payload

**已确认策略**：

- **固定 4 个** `talk_lab_speaking` assignment（满足 3–5 要求）。
- 其余字段为 fixture；**仅**将 Package `title` 中的模板标题替换为入参 `template_title`（`responses.rb` 内一行 gsub）。
- 不根据 transcript 动态生成内容。

（JSON 示例同 v0.1 §6.1，此处不重复粘贴；实现时写入 `responses.rb`。）

### 6.2 W2 — Grading Payload

简化 fixture：含 `overall_score`、`sentence1/2`、`priority_improvements`；`outputs.score` 含四维 criteria（见 v0.1 §6.2）。

### 6.3 W3 — General Context Payload

简化 fixture：含 `studentFeedback.overall`、`detailedFeedback`、`sections`；带 `_source: talk_lab_dify_mock`（见 v0.1 §6.3）。

---

## 7. 配置与一键切换

| 变量 | Mock 联调建议 |
|------|---------------|
| `TALK_LAB_DIFY_MOCK=true` | development / staging 开启 |
| `TALK_LAB_DIFY_MOCK=false` | 一行关闭，走真实 Dify |

首期 **仅总开关**；细分开关（package / grading / general_context）在 `policy.rb` 注释预留，不实现。

---

## 8. 文件与模块组织（Rails）

```
DocAI_Backend_Rails/
  docs/
    talk_lab_backend_dify_mock_architecture.md   ← 本文档
  app/services/talk_lab_speaking/dify_mock/
    policy.rb
    responses.rb
  app/services/assignment_packages/dify_generation_client.rb
  app/services/essay_grading_service.rb
  spec/services/talk_lab_speaking/dify_mock_*.rb
```

PM 修改 Mock 文案时 **只改 `responses.rb`**。

---

## 9. 分阶段实施计划

### Phase 0 — 方案审核 ✅ 已完成

- 文档定稿于 `DocAI_Backend_Rails/docs/`。
- §13 全部按推荐方案确认。

### Phase 1 — Mock 基础设施（0.5–1 天）← **下一步**

| 任务 | 说明 |
|------|------|
| `TalkLabSpeaking::DifyMock::Policy` | `enabled?` + production boot raise |
| `TalkLabSpeaking::DifyMock::Responses` | 三份 fixture + `template_title` 替换 |
| 单元测试 | parser 可消费 Mock 返回 |
| `.env.example` | 补充 `TALK_LAB_DIFY_MOCK` |

### Phase 2 — Package Generator（0.5 天）

改 `DifyGenerationClient#call`；验收 Quick Start → Package `active` + 4 items。

### Phase 3 — Talk Lab Grading（0.5–1 天）

改 `EssayGradingService#execute_workflow_streaming`；验收 `graded` + grading/general_context 入库。

### Phase 4 — 端到端联调（1 天）

老师 Assignment + Quick Start Package 全链路；关 Mock 烟雾测试。

### Phase 5 — 切换真实 Dify

PM Prompt 就绪 → `TALK_LAB_DIFY_MOCK=false` → 对比 Mock 与真实产出。

---

## 10. 验收标准（Mock 阶段）

- [ ] Mock 开启时不发 Talk Lab 相关 Dify HTTP 请求
- [ ] Package：`active`，4 个 `talk_lab_speaking` item，顺序解锁正常
- [ ] Grading：最终 `graded`，`grading.data` / `general_context.data` 可解析
- [ ] 前端无 Mock，全流程真实 API
- [ ] `TALK_LAB_DIFY_MOCK=false` 一行恢复真实 Dify
- [ ] production + Mock 开启 → boot fail

**Mock 阶段不阻塞**：`talk_lab_speaking` 专用 grading 报告前端页（先验收 `graded` 状态与 DB 数据）。

---

## 11. 风险与缓解

| 风险 | 缓解 |
|------|------|
| Mock JSON 与真实 Dify 漂移 | 以 Demo Prompt 文档为契约；Phase 5 对比 |
| 前端报告页未就绪 | 不阻塞 Mock 阶段；并行开发 |
| 误开 production Mock | boot raise |
| 关 Mock 时 Dify 未就绪 | 预期失败；staging 先配 Dify 再关闭 Mock |

---

## 12. 扩展路线（Mock 之后）

动态 Mock、录制回放、Contract Test、Partial Mock、Admin Mock badge — 见 v0.1 §12，按需迭代。

---

## 13. 已确认决策（2026-07-07）

| # | 决策项 | 结论 |
|---|--------|------|
| 1 | **Mock 文档位置** | **`DocAI_Backend_Rails/docs/`**（本文档）；实现代码同仓库 |
| 2 | **Package title** | **是** — 用入参 `template_title` 替换 Package title，其余 fixture 固定 |
| 3 | **Package item 数量** | **固定 4 个** `talk_lab_speaking` |
| 4 | **production 误开 Mock** | **boot 时 raise**，拒绝启动 |
| 5 | **grading 报告前端页** | **不阻塞** Mock 阶段；先验证 `graded` 与入库 |
| 6 | **关 Mock 后 Dify 未就绪** | **接受失败**；staging 先配 Dify 再关 Mock |
| 7 | **`_source` 标记** | **是** — 写入 `talk_lab_dify_mock` 便于排查 |
| 8 | **拦截点与开关** | HTTP 边界拦截 + 总开关 `TALK_LAB_DIFY_MOCK`（推荐方案） |
| 9 | **Mock 数据文件** | 独立 `responses.rb`，PM 可改文案 |
| 10 | **编排链路** | 不跳过 Job / parser，与真实 Dify 同路径 |

---

## 14. 与前端现状对齐

essay-checker（2026-07-06）已移除全部前端 Mock，Scenario 始终调用 Rails API。

```
前端：真实 UI + 真实 API 入参
后端：真实持久化 + Mock Dify 出参（可开关）
Dify：PM Prompt 就绪后接入
```

---

## 15. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v0.1 | 2026-07-06 | 初稿 |
| v1.0 | 2026-07-07 | PM 审核：文档迁至后端；§13 全部按推荐方案确认；可进入 Phase 1 编码 |

---

## 附录 A — 实现伪代码

```ruby
# app/services/talk_lab_speaking/dify_mock/policy.rb
module TalkLabSpeaking
  module DifyMock
    module Policy
      def self.enabled?
        return false if Rails.env.production? && mock_env_requested?
        return false unless mock_env_requested?
        true
      end

      def self.mock_env_requested?
        %w[true 1].include?(ENV['TALK_LAB_DIFY_MOCK'].to_s.downcase)
      end

      def self.verify_production!
        return unless Rails.env.production? && mock_env_requested?
        raise 'TALK_LAB_DIFY_MOCK must not be enabled in production'
      end
    end
  end
end
```

```ruby
# dify_generation_client.rb / essay_grading_service.rb — 拦截点同 v0.1 附录
```

```bash
# Mock 联调
TALK_LAB_DIFY_MOCK=true

# 一行关闭
TALK_LAB_DIFY_MOCK=false
```
