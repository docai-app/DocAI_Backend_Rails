# Talk Lab Speaking 与 Assignment Package 可执行需求方案

## 1. 背景与目标

AIEnglish 后端当前以 `EssayAssignment` 作为作业定义，以 `EssayGrading` 作为学生提交/评分记录。老师可以创建 Assignment 并分配给学生，学生也可以通过 Assignment code 进入作业。

本方案新增两条能力：

1. 新增 `talk_lab_speaking` Assignment category。学生进入作业后与 RTC 多轮对话，前端负责根据 Assignment 信息组装 RTC prompt；学生结束对话后，后端保存文字对话、学生录音、AI 录音，并通过 Sidekiq 调用 Dify 生成评分、评估信息和报告，结果更新到 `EssayGrading`。
2. 新增学生自创建学习包流程。管理员配置一组可见的“标签/模板”，学生选择模板后与 RTC 对话，结束后由 Dify 返回结构化 JSON，后端据此创建一个 Assignment Package 和其中多个有序 Assignment。学生必须按顺序完成 Package 内 Assignment；完成全部后，该 Package 不再出现在 `api/v1/essay_assignments/my_assignments`，但可通过新的历史/汇总 API 查询。

本阶段只实现单一 account 维度的学生自创建 Package；“学习者资料 profile”和“模板使用次数限制”暂不实现，但数据结构和 service 边界需预留扩展点。

## 2. 现状观察

当前代码中的关键事实：

- `EssayAssignment.category` 是 Rails integer enum，当前值为 `essay, comprehension, speaking_conversation, speaking_essay, sentence_builder, speaking_pronunciation, listening, sentence_puzzle`。
- `EssayGrading#need_to_run_workflow?` 当前只包含 `essay, speaking_essay, speaking_conversation, sentence_builder`。
- `EssayGradingJob` 负责从 `EssayGrading` 进入 `EssayGradingService` 调用 Dify。
- `speaking_conversation` 已有保存预设问题答案与音频 URL 的模式，可作为 `talk_lab_speaking` 音频持久化与提交动作的参考。
- `api/v1/essay_assignments/my_assignments` 目前只返回老师分配给学生的 `AssignmentStudentAssignment`，不包含学生自创建 Package。
- `AssignmentStudentAssignment` 使用非 draft 的 `EssayGrading` 判断完成，可复用“完成提交才解锁下一题”的业务语义。

架构风险：

- category 使用 integer enum，新增 enum 必须只追加在末尾，不能插入中间，否则旧数据 category 数值会错位。
- 学生自创建 Assignment 与老师创建 Assignment 在 ownership、可见性、分配状态上语义不同，不建议强行复用 `AssignmentStudentAssignment` 表表达 Package 内顺序。
- RTC 对话的 transcript 与多段录音文件可能较大，建议正文 JSON 和媒体 URL 分离，并限制列表接口返回体积。

## 3. 术语与推荐命名

### 3.1 新 category

推荐名称：`talk_lab_speaking`

用途：自由 RTC 对话型 speaking Assignment。区别于现有 `speaking_conversation`：

- `speaking_conversation` 偏预设问题/固定表单提交。
- `talk_lab_speaking` 偏实时多轮对话，Assignment 或 Template 只提供 prompt 材料，最终评分来自完整对话记录。

### 3.2 管理员配置的“标签”

确认模型名：`LearningPathTemplate`

使用 `LearningPathTemplate` 而不是 `TalkLabTemplate`，因为这个入口未来不一定只绑定 talk lab，也可能扩展为其他学习路径生成模板。

职责：

- 由系统管理员维护。
- 学生前端可查看启用中的模板。
- 模板包含标题、描述、目标、难度、主题、prompt 配置、Dify app key/workflow key、可见性和排序。
- 学生点击模板后，前端根据模板信息组装 RTC prompt。

### 3.3 Dify 生成出来的新模型

推荐模型名：`AssignmentPackage`

职责：

- 表示一次由学生通过模板和 RTC 对话生成的学习包。
- 归属于创建学生 `general_user`，后期可选归属于 `learner_profile`。
- 包含多个有序 Package Items，每个 item 指向一个 `EssayAssignment`。
- 记录整体进度、当前可做的 Assignment、生成来源、Dify 原始输出和摘要。

推荐子模型名：`AssignmentPackageItem`

职责：

- 保存 Package 内 Assignment 的顺序、解锁状态、完成状态。
- 指向 `assignment_package` 和 `essay_assignment`。
- 可缓存该 item 对应学生的 `essay_grading_id`、完成时间、状态，避免每次深 join。

## 4. 核心业务流程

### 4.1 老师创建 `talk_lab_speaking` Assignment

1. 老师创建 Assignment，category 为 `talk_lab_speaking`。
2. Assignment 保存标题、topic、rubric、meta 等信息。
3. 老师分配给学生，或学生通过 code 进入。
4. 前端获取 Assignment 后，使用 Assignment 信息组装 RTC prompt 并启动对话。
5. 学生手动结束对话。
6. 前端提交 transcript、学生录音、AI 录音、对话统计信息到后端。
7. 后端创建或更新 `EssayGrading`，保存对话文本与媒体 URL，状态为 `pending`。
8. Sidekiq 调用 Dify 评分 workflow。
9. Dify 返回评分和评估内容，后端更新 `EssayGrading.grading/general_context/meta/score/status`。
10. 若该 Assignment 来自老师分配，则更新 `AssignmentStudentAssignment` 完成状态。
11. 若该 Assignment 来自 Assignment Package，则更新 Package item 状态并解锁下一项。

### 4.2 学生通过模板创建 Assignment Package

1. 管理员创建并启用 `LearningPathTemplate`。
2. 学生在前端看到所有可用模板。
3. 学生点击模板进入 RTC 页面。
4. 前端根据模板信息组装 RTC prompt。
5. 学生结束对话后，前端提交 transcript 与录音。
6. 后端创建一条 `AssignmentPackageGeneration` 或直接使用 service 执行生成任务，保存生成输入和媒体 URL。
7. Sidekiq 调用 Dify package generator workflow。
8. Dify 返回 JSON，后端校验 schema。
9. 后端在事务中创建：
   - `AssignmentPackage`
   - 多个 `EssayAssignment`
   - 多个 `AssignmentPackageItem`
10. `api/v1/essay_assignments/my_assignments` 返回老师分配 Assignment 和未完成的 Assignment Package。
11. 学生进入 Package detail，只能打开第一个未完成且已解锁的 Assignment。
12. 完成当前 Assignment 对应 `EssayGrading` 后，Package 更新进度并解锁下一项。
13. Package 全部完成后，不再出现在 `my_assignments`，但仍可在 Package 历史 API 查询 summary。

## 5. 数据模型方案

### 5.1 `EssayAssignment`

新增：

- category enum 末尾追加 `talk_lab_speaking`。
- `general_user_id` 对学生自创建 Assignment 表示创建学生；对老师创建 Assignment 保持现有语义。
- 建议在 `meta` 中增加来源字段，避免新增过多 Assignment 字段：

```json
{
  "source_type": "teacher_assignment | assignment_package",
  "assignment_package_id": "uuid",
  "assignment_package_item_id": "uuid",
  "talk_lab_speaking": {
    "scenario": "...",
    "role": "...",
    "objectives": [],
    "rtc_prompt_materials": {},
    "grading_app_key": "...",
    "general_context_app_key": "..."
  }
}
```

注意：

- 列表接口不应返回过大的 prompt/transcript 配置，可沿用 `EssayAssignment.meta_for_list_response` 过滤大字段。
- 自创建 Assignment 不建议加入老师分配表 `AssignmentStudentAssignment`，以免混淆“老师分配”和“学习包步骤”。

### 5.2 `EssayGrading`

复用 `EssayGrading` 作为 `talk_lab_speaking` 的提交和评分记录。

建议保存结构：

- `essay`: 用于 Dify 的纯文本 transcript 汇总，方便复用现有 `EssayGradingService`。
- `grading`: 保存 Dify 评分输出。
- `general_context`: 保存 Dify 总结/评估输出。
- `meta`: 保存 RTC 结构化信息与媒体 URL。

示例：

```json
{
  "talk_lab_speaking": {
    "conversation_id": "frontend-or-rtc-session-id",
    "started_at": "2026-07-02T10:00:00Z",
    "ended_at": "2026-07-02T10:08:00Z",
    "duration_seconds": 480,
    "turns": [
      {
        "role": "student",
        "text": "I want to talk about travel.",
        "started_at": "...",
        "ended_at": "...",
        "audio_url": "https://..."
      },
      {
        "role": "ai",
        "text": "Great, where would you like to go?",
        "started_at": "...",
        "ended_at": "...",
        "audio_url": "https://..."
      }
    ],
    "student_audio_urls": [],
    "ai_audio_urls": [],
    "raw_rtc_payload": {}
  },
  "assignment_package_id": "uuid",
  "assignment_package_item_id": "uuid"
}
```

媒体保存建议：

- 第一阶段由前端负责为每个 turn 的录音生成 URL，后端只保存 URL，不接收或转存大体积 base64。
- RTC 录音按 turn 分段提交，学生和 AI 的每一段录音都保存独立 URL，避免一次性生成大文件。
- 后端仍保留兼容能力：如后续前端改为上传 base64/data URL，可沿用或扩展 `SpeakingConversationAudioStorageService` 做转存。
- 不建议将 base64 长期保存进 DB。

### 5.3 `LearningPathTemplate`

字段建议：

- `id: uuid`
- `title: string`
- `description: text`
- `status: integer enum`：`draft, active, archived`
- `level: string`
- `locale: string`
- `category: string`：预留不同模板类型，首期可为 `talk_lab_package`
- `prompt_config: jsonb`：前端组装 RTC prompt 的材料。
- `dify_config: jsonb`：package generator workflow app key、输入字段映射。
- `usage_policy: jsonb`：预留次数限制，如 daily/monthly/total limit。
- `position: integer`
- `created_by_id: uuid`
- `created_at: datetime`
- `updated_at: datetime`

### 5.4 `AssignmentPackage`

字段建议：

- `id: uuid`
- `general_user_id: uuid, null: false`
- `learner_profile_id: uuid, null: true`：后期切换学习者使用。
- `learning_path_template_id: uuid, null: true`
- `title: string`
- `description: text`
- `summary: jsonb, default: {}`
- `status: integer enum`：`generating, active, completed, failed, archived`
- `progress: jsonb, default: {}`：缓存总数、完成数、当前 item。
- `source_conversation: jsonb, default: {}`：生成 Package 的 RTC transcript 和音频 URL。
- `dify_request: jsonb, default: {}`
- `dify_response: jsonb, default: {}`
- `error: jsonb, default: {}`
- `created_at: datetime`
- `updated_at: datetime`

`progress` 示例：

```json
{
  "total_items": 3,
  "completed_items": 1,
  "current_position": 2,
  "completion_percentage": 33
}
```

### 5.5 `AssignmentPackageItem`

字段建议：

- `id: uuid`
- `assignment_package_id: uuid, null: false`
- `essay_assignment_id: uuid, null: false`
- `position: integer, null: false`
- `status: integer enum`：`locked, available, completed, skipped`
- `essay_grading_id: uuid, null: true`
- `unlocked_at: datetime`
- `completed_at: datetime`
- `title: string`：可选冗余，方便列表。
- `category: string`：可选冗余，方便列表。
- `meta: jsonb, default: {}`
- `created_at: datetime`
- `updated_at: datetime`

约束：

- unique index：`assignment_package_id, position`
- unique index：`assignment_package_id, essay_assignment_id`
- index：`assignment_package_id, status`

## 6. Dify JSON 合约

后端应要求 Dify 返回严格 JSON，而不是自然语言混合文本。建议 schema：

```json
{
  "title": "Travel Speaking Sprint",
  "description": "A three-step practice package about travel planning.",
  "summary": {
    "learner_goal": "Improve fluency when discussing travel.",
    "recommended_level": "CEFR B1"
  },
  "assignments": [
    {
      "position": 1,
      "category": "talk_lab_speaking",
      "title": "Talk about a past trip",
      "topic": "Describe a memorable trip.",
      "assignment": "Have a conversation about a past travel experience.",
      "hints": "Focus on time expressions and reasons.",
      "rubric": {
        "app_key": {
          "grading": "app-xxx",
          "general_context": "app-yyy"
        }
      },
      "meta": {
        "talk_lab_speaking": {
          "objectives": ["fluency", "detail"],
          "rtc_prompt_materials": {}
        }
      }
    }
  ]
}
```

校验规则：

- `title` 必填。
- `assignments` 必须是 1 到建议上限 10 项。
- 每个 assignment 的 `category` 不做业务白名单限制，但必须属于系统现有 `EssayAssignment.category` enum；不属于 Assignment category 的项目不创建，记录到 Package 生成日志或 skipped 列表。
- 所有 Assignment 必须具备当前模型 validation 所需字段：`title, topic, assignment, rubric, category`。
- 如果 Dify 返回的 Assignment category 为 `talk_lab_speaking`，后端忽略 Dify 中可能携带的评分 app key，并固定写入系统配置的 `talk_lab_speaking` Dify 评分 app key。
- 后端只接受 Dify 返回的数据字段白名单，忽略未知字段。
- Dify 返回非法 JSON 时，Package 状态为 `failed`，保存原始响应和错误信息。
- Package 生成失败后，学生端不复用本次失败会话，需重新开始 RTC；管理员后台可提供 retry 能力用于排查或重跑。

## 7. API 草案

### 7.1 模板 API

学生端：

- `GET /api/v1/learning_path_templates`
- `GET /api/v1/learning_path_templates/:id`

管理员端：

- `GET /api/admin/v1/learning_path_templates`
- `POST /api/admin/v1/learning_path_templates`
- `PATCH /api/admin/v1/learning_path_templates/:id`
- `DELETE /api/admin/v1/learning_path_templates/:id` 或 archive

### 7.2 Package 生成 API

建议异步：

- `POST /api/v1/assignment_packages`

请求：

```json
{
  "learning_path_template_id": "uuid",
  "learner_profile_id": null,
  "conversation": {
    "transcript": "...",
    "turns": [],
    "student_audio_urls": [],
    "ai_audio_urls": [],
    "duration_seconds": 480
  }
}
```

响应：

```json
{
  "success": true,
  "assignment_package": {
    "id": "uuid",
    "status": "generating"
  }
}
```

查询生成结果：

- `GET /api/v1/assignment_packages/:id`
  - 允许 Package owner 访问；管理员也可访问。

删除失败 Package：

- `DELETE /api/v1/assignment_packages/:id`
  - 学生只可删除自己名下 `failed` 状态的 Package。
  - 学生删除非 `failed` Package 返回 403 或 422，并说明当前状态不可删除。
  - 管理员可删除任意状态 Package；建议后台操作记录 audit log。

### 7.3 Package 列表与历史

- `GET /api/v1/assignment_packages`
  - 默认返回当前用户所有 Package，可按 `status` 过滤。
  - 包含 summary 和 progress。

- `GET /api/v1/assignment_packages/:id`
  - 返回 package、items、每个 item 的 lock/completion 状态、可进入的 assignment 信息。
  - 学生只能查看自己拥有的 Package；管理员可以查看。

### 7.4 Package 内 Assignment 访问控制

推荐新增：

- `GET /api/v1/assignment_packages/:package_id/items/:item_id/start`

职责：

- 校验当前用户拥有 Package。
- 管理员访问时可跳过 owner 限制，但仍需返回 item 当前 lock/completion 状态。
- 校验 item 已解锁。
- 返回对应 `essay_assignment` 的前端所需信息。

也可在现有 Assignment show/read 接口加权限判断：

- 若 Assignment 来源是 `assignment_package`，只有 owner 可见。
- 管理员可查看 Assignment Package 生成出来的 Assignment。
- 若 item locked，返回 403。

### 7.5 `talk_lab_speaking` 提交 API

可复用 `POST /api/v1/essay_assignments/:code/essay_gradings`，也可新增更语义化的 member action。

推荐第一阶段复用现有创建入口，并在 `essay_grading_params` 增加 `talk_lab_speaking` 白名单：

```json
{
  "essay_grading": {
    "status": "pending",
    "essay": "Student: ...\nAI: ...",
    "meta": {
      "talk_lab_speaking": {
        "conversation_id": "...",
        "turns": [],
        "student_audio_urls": [],
        "ai_audio_urls": []
      }
    }
  }
}
```

如需要更语义化地处理 RTC 对话结束动作，建议新增：

- `POST /api/v1/essay_gradings/:id/talk_lab_speaking/submit`

由该 action 接收前端已生成的分 turn 音频 URL、组装 transcript、切换状态并 enqueue job。

### 7.6 `my_assignments` 聚合返回

当前接口保留原路径：

- `GET /api/v1/essay_assignments/my_assignments`

返回应扩展为 mixed feed：

```json
{
  "success": true,
  "assignments": [
    {
      "type": "teacher_assignment",
      "id": "...",
      "essay_assignment": {}
    },
    {
      "type": "assignment_package",
      "id": "...",
      "title": "...",
      "description": "...",
      "status": "active",
      "progress": {
        "total_items": 3,
        "completed_items": 1,
        "current_position": 2
      },
      "current_item": {
        "id": "...",
        "essay_assignment": {}
      }
    }
  ],
  "meta": {}
}
```

规则：

- 只返回未完成的 active/generating Package。
- completed Package 不出现在 `my_assignments`。
- 老师分配 Assignment 不受 learner profile 切换影响。
- 自创建 Package 后期按 `learner_profile_id` 过滤；当前阶段可接受空 profile。

## 8. 权限与可见性

老师创建 Assignment：

- 沿用现有老师权限与 feature 权限。
- 新增 `talk_lab_speaking` 到用户可用 feature 白名单。

学生自创建 Package：

- 学生只能查看和操作自己的 Package。
- Package detail 只允许 Package owner 学生访问；管理员也可查看，用于客服、审核和问题排查。
- Package 生成出来的 Assignment 对 Package owner 学生可见；管理员也可查看，用于客服、审核和问题排查。
- 老师暂不需要管理学生自创建 Package 内的 Assignment，也不进入老师 assignment 管理流程。
- Package 内 item locked 时不可提交，即使知道 Assignment code 也应阻止。
- 管理员可查看模板与必要的 Package 生成日志。

删除规则：

- 学生只允许删除 `failed` 状态的 Assignment Package。
- `generating, active, completed, archived` 等其他状态学生不可删除，避免删除正在生成中、已开始完成或已有学习记录的数据。
- 管理员可以删除 Assignment Package，用于后台清理、客服处理和异常数据修复。
- 管理员删除时建议采用软删除或 archive 优先；如果需要物理删除，应明确级联影响：Package items、Package 生成的 Assignments、相关 EssayGradings、音频 URL 引用与审计日志。

code 访问风险：

- 当前 Assignment code 是公开入口。对 `source_type = assignment_package` 的 Assignment，建议不允许通过 code 被其他用户直接进入；或要求当前用户必须是 Package owner。

## 9. 进度与解锁规则

完成判定：

- 对某 item 对应 Assignment，存在当前学生的非 draft `EssayGrading`，并且状态达到业务要求。
- 当前阶段确认使用 `status != draft` 即完成，包含 `pending, graded, stopped`。这样某个 Assignment 评分或外部服务出错时，不会阻塞学生继续完成 Package 后续步骤。

解锁：

- Package 创建后，position = 1 的 item 状态为 `available`，其余为 `locked`。
- 当前 item 完成后，下一个 `locked` item 变为 `available`。
- 全部 item completed 后，Package 状态为 `completed`。

触发点：

- `EssayGradingsController#create` 成功保存非 draft 后。
- `EssayGrading` 从 draft 变 pending 后。
- 不等待 Dify 评分完成才解锁下一项；只要非 draft `EssayGrading` 创建或提交成功即可触发 Package 进度更新。

建议封装 service：

- `AssignmentPackages::ProgressUpdater.call(essay_grading)`
- `AssignmentPackages::CompletionPolicy.completed?(essay_grading)`：集中判断某个 `EssayGrading` 是否算完成。当前实现为 `!essay_grading.draft?`；后续如果改为 `draft` 和 `pending` 都不算完成，只需要调整该 policy，避免散落修改 controller、model callback 和 progress updater。

## 10. 异步任务与 Service 划分

建议新增：

- `TalkLabSpeaking::SubmissionService`
  - 规范化 transcript。
  - 保存前端提交的学生和 AI 分 turn 音频 URL。
  - 写入 `EssayGrading.meta`。
  - enqueue `EssayGradingJob`。

- `AssignmentPackages::GenerationJob`
  - 调用 Dify package generator workflow。
  - 处理失败和管理员 retry。
  - 学生端失败后不 retry 原会话，提示重新开始 RTC。

- `AssignmentPackages::CreateFromDifyResponseService`
  - JSON 解析与 schema 校验。
  - 事务创建 Package、Assignments、Items。

- `AssignmentPackages::ProgressUpdater`
  - 根据 `EssayGrading` 更新 item 和 package progress。

- `AssignmentPackages::AccessPolicy`
  - 判断 Package owner、item lock、Assignment 可访问性。

`EssayGradingService` 扩展：

- `need_to_run_workflow?` 加入 `talk_lab_speaking`。
- `grading_request_payload` 针对 `talk_lab_speaking` 使用 transcript、turns summary、duration 等输入。
- `talk_lab_speaking` 的 Dify 评分 app key 为系统固定配置；当 Package Generator 返回 `talk_lab_speaking` Assignment 时，创建 Assignment 阶段统一写入固定 app key。

## 11. 学习者资料与次数限制预留

### 11.1 Learner Profile 预留

后续模型建议：`LearnerProfile`

字段：

- `general_user_id`
- `name`
- `level`
- `age_group`
- `goals`
- `preferences`
- `meta`

当前阶段预留：

- `assignment_packages.learner_profile_id nullable`
- API 请求接受 `learner_profile_id`，当前可以忽略或校验为 nil。
- Service 方法参数保留 `learner_profile: nil`。

行为：

- 老师分配 Assignment 属于 account，不按 learner profile 过滤。
- Assignment Package 属于 learner profile；当前 profile 为空表示 account 默认学习者。

### 11.2 使用次数限制预留

后续模型建议：

- `LearningPathTemplateUsage`

字段：

- `general_user_id`
- `learner_profile_id`
- `learning_path_template_id`
- `assignment_package_id`
- `status`
- `used_at`
- `meta`

当前阶段预留：

- `LearningPathTemplate#usage_policy`
- `AssignmentPackage` 保存 template id 与用户 id。
- `AssignmentPackages::UsagePolicy` service 返回 allow，暂不阻止。
- 当前阶段学生自创建 Assignment/Package 不消耗老师、学校或学生账号配额；后续再通过 `usage_policy` 与 usage 记录扩展限制方案。

## 12. 分阶段实施计划

### Phase 0：方案确认

产出：

- 已确认命名：`LearningPathTemplate` / `AssignmentPackage` / `talk_lab_speaking`。
- 已确认 Dify Package Generator 返回的 Assignment category 不做业务白名单限制，但必须属于系统 Assignment category。
- 已确认 Package 内 Assignment 管理员和学生可见，老师暂不做管理要求。
- 已确认完成口径：非 draft 的 `EssayGrading` 都算完成。
- 已确认 RTC 录音按 turn 分段，由前端生成学生和 AI 录音 URL，后端保存 URL。
- 已确认 Package 生成失败后学生重新开始 RTC，管理员可 retry。
- 已确认学生自创建 Assignment 暂不消耗任何配额或额度。

### Phase 1：`talk_lab_speaking` Assignment

范围：

- 追加 category enum。
- 扩展 `GeneralUser` feature 白名单。
- 扩展 create/show/list 参数与 meta 过滤。
- 新增或扩展 `EssayGrading` 提交 API，保存 transcript 和学生/AI 音频 URL。
- 扩展 `EssayGradingService` 和 Sidekiq 工作流。
- 报告展示先复用 speaking conversation/essay 的 JSON 输出风格。

验收：

- 老师可创建 `talk_lab_speaking` Assignment。
- 学生可提交一次 RTC 对话记录。
- 后端可保存 transcript、student audio URL、AI audio URL。
- Sidekiq 调用 Dify 后更新 `EssayGrading` 为 graded 或 stopped。

### Phase 2：模板与 Package 生成

范围：

- 新增 `LearningPathTemplate` 管理员 CRUD 和学生列表 API。
- 新增 `AssignmentPackage`、`AssignmentPackageItem`。
- 新增 Package 生成 API 与异步任务。
- 实现 Dify JSON schema 校验和事务创建。

验收：

- 学生选择模板并完成生成对话后，能生成 Package。
- Package 内有多个有序 Assignment。
- Dify 失败时 Package 状态为 failed 且可查看错误摘要。
- Package 生成失败后，学生重新开始 RTC；管理员可以 retry 生成任务。

### Phase 3：Package 进度与 `my_assignments` 聚合

范围：

- Package detail API，允许 owner 和管理员访问，禁止其他学生访问。
- Package 删除 API，学生只可删除 failed Package，管理员可删除任意状态 Package。
- Package item 解锁规则。
- `AssignmentPackages::CompletionPolicy`，集中封装 item 完成判定。
- `my_assignments` 返回老师分配 Assignment + 未完成 Package。
- 完成全部 item 后 Package 不再出现在 `my_assignments`。
- 新增 Package 历史/summary API。

验收：

- 学生只能打开当前可做 item。
- 完成第一个 Assignment 后自动解锁第二个。
- 修改完成状态口径时只需要调整 completion policy，不需要改多个 controller/service。
- 学生不能删除 generating/active/completed/archived Package；管理员可以删除。
- 完成全部后只在历史 API 中出现。

### Phase 4：扩展预留落地

范围：

- Learner Profile 模型与切换。
- Package 按 learner profile 隔离。
- 模板使用次数限制。
- 更完整的统计、管理员审计和报表。

## 13. 测试策略

模型测试：

- category enum 追加不破坏旧 category。
- Package item 顺序唯一。
- Package progress 计算正确。
- `AssignmentPackages::CompletionPolicy` 当前以非 draft 判断完成，后续调整状态规则时只改 policy。

请求测试：

- 学生查看模板列表。
- 学生创建 Package generation。
- Package detail 允许 owner 和管理员访问，禁止其他学生访问。
- 学生只可删除自己的 failed Package，不能删除 generating/active/completed/archived Package。
- 管理员可删除任意状态 Package，并记录后台操作。
- locked item 不可访问。
- `my_assignments` 混合返回逻辑。

Service 测试：

- Dify 合法 JSON 创建 Package 成功。
- Dify 非法 JSON 标记 failed。
- talk lab transcript 正确写入 `essay` 和 `meta`。
- 学生和 AI 分 turn 音频 URL 正确写入 `meta`，不落库 base64。

回归测试：

- 现有 essay/speaking_conversation/sentence_puzzle 提交不受影响。
- 老师分配作业完成状态不受 Package 逻辑影响。

## 14. 已确认业务决策

1. `talk_lab_speaking` 的 Dify 评分 app key 是系统固定配置。Dify Package Generator 返回的 Assignment 如果是 `talk_lab_speaking`，后端创建时统一写入固定 app key。
2. Dify Package Generator 返回的 Assignment category 不做额外业务限制；只要属于系统 `EssayAssignment.category` 就允许创建，不属于 Assignment category 的条目不创建。
3. Package 内 Assignment 对学生和管理员可见；老师暂不做管理要求。
4. Package detail 允许 owner 和管理员访问，禁止其他学生访问。
5. 学生只允许删除自己名下 `failed` 状态的 Assignment Package；其他状态学生不可删除，管理员可以删除。
6. Package 进度完成口径当前为非 draft `EssayGrading` 即完成，包含 `pending, graded, stopped`；实现时必须集中在 completion policy，方便后续改为排除 `pending` 等状态。
7. RTC 录音按 turn 分段提交，每次录音都生成 URL，避免一次性生成大文件。
8. 学生和 AI 的对话录音 URL 都由前端生成，后端负责保存 URL 和 turn 结构。
9. Package 生成失败后，学生重新开始 RTC；管理员后台可以 retry。
10. 学生自创建 Assignment 暂不消耗任何额度、次数或学校/老师配额，后续再设计限制方案。

## 15. 推荐决策摘要

- 新 Assignment category 使用 `talk_lab_speaking`，并只追加到 enum 末尾。
- 管理员配置入口命名为 `LearningPathTemplate`，避免未来只绑定 “Talk Lab 标签”。
- 学生生成结果命名为 `AssignmentPackage`，子项为 `AssignmentPackageItem`。
- Package 内 Assignment 不复用老师分配表，单独用 Package item 表表达顺序、锁定和进度。
- `EssayGrading` 继续作为所有 Assignment 的提交/评分记录，`talk_lab_speaking` 的 transcript 放 `essay`，结构化 RTC 信息和音频 URL 放 `meta`。
- `talk_lab_speaking` 使用固定 Dify app key；Package Generator 只负责决定是否生成该类型 Assignment 和对应内容。
- `my_assignments` 改为混合 feed，返回老师分配 Assignment 和未完成 Assignment Package；完整历史由新的 Package API 提供。
