# Talk Lab Speaking 与 Assignment Package 前端对接文档

## 1. 文档目标

本文档提供给前端开发工程师使用，说明后端目前已完成的功能、涉及的 API、请求参数、返回结构和建议对接顺序。

本轮后端主要完成三类能力：

1. 新增 `talk_lab_speaking` 作业类型。
2. 学生可通过 `LearningPathTemplate` 创建自己的 `AssignmentPackage`。
3. 学生的 `my_assignments` 会同时返回老师分配作业和未完成的 Assignment Package。

## 2. 已完成后端改动概览

### 2.1 新增作业类型

新增 Assignment category：

```text
talk_lab_speaking
```

用途：

- 学生进入作业后与 RTC/AI 多轮对话。
- 前端负责根据作业或模板内容组装 RTC prompt。
- 对话结束后，前端提交文字 transcript、turn 列表、学生录音 URL、AI 录音 URL。
- 后端保存到 `EssayGrading`，并通过 Dify 生成评分和报告。

### 2.2 新增学生学习包能力

新增概念：

- `LearningPathTemplate`：管理员配置的学习模板，学生可以选择。
- `AssignmentPackage`：学生通过模板和 RTC 对话生成出来的一组有顺序的作业。
- `AssignmentPackageItem`：Package 内的单个作业步骤。

Package 内作业按顺序解锁：

- 第一个 item 默认可开始。
- 当前 item 完成后，自动解锁下一个 item。
- 当前阶段只要对应 `EssayGrading` 不是 `draft`，就算完成。

### 2.3 前端需要关注的后端代码

主要新增/修改位置：

- `app/controllers/api/v1/learning_path_templates_controller.rb`
- `app/controllers/api/v1/assignment_packages_controller.rb`
- `app/controllers/api/v1/my_assignments_controller.rb`
- `app/controllers/api/v1/essay_gradings_controller.rb`
- `app/services/talk_lab_speaking/conversation_payload_builder.rb`
- `app/services/assignment_packages/*`
- `app/models/assignment_package.rb`
- `app/models/assignment_package_item.rb`
- `app/models/learning_path_template.rb`

## 3. 推荐前端对接阶段

### Phase 1：对接 Talk Lab Speaking 作业提交

目标：

- 前端能打开 `talk_lab_speaking` Assignment。
- RTC 对话结束后能提交 `EssayGrading`。
- 后端能保存 transcript 和每个 turn 的录音 URL。

涉及 API：

- `POST /api/v1/essay_assignments/:essay_assignment_id/essay_gradings`

注意：

- 路径里的 `essay_assignment_id` 仍使用 Assignment `code`，保持现有接口习惯。
- 如果该 Assignment 来源于 Package，必须是当前已解锁 item，否则后端返回 403。

### Phase 2：对接学习模板和生成 Package

目标：

- 学生可看到管理员配置的模板。
- 学生选择模板后进入 RTC 页面。
- RTC 对话结束后创建 Assignment Package。
- 后端异步调用 Dify 生成 Package 内作业。

涉及 API：

- `GET /api/v1/learning_path_templates`
- `GET /api/v1/learning_path_templates/:id`
- `POST /api/v1/assignment_packages`
- `GET /api/v1/assignment_packages/:id`

### Phase 3：对接 Package 顺序学习流程

目标：

- `my_assignments` 同时展示老师布置作业和学生自创建 Package。
- Package detail 页面展示 item 列表。
- 只允许进入已解锁 item。
- 完成当前作业后，刷新 Package detail 可以看到下一个 item 解锁。

涉及 API：

- `GET /api/v1/essay_assignments/my_assignments`
- `GET /api/v1/assignment_packages/:id`
- `GET /api/v1/assignment_packages/:id/items/:item_id/start`
- `DELETE /api/v1/assignment_packages/:id`

## 4. API 详细说明

## 4.1 获取学习模板列表

```http
GET /api/v1/learning_path_templates
```

用途：

- 学生查看可用模板。
- 前端用模板的 `prompt_config` 组装 RTC prompt。

请求参数：

无。

返回示例：

```json
{
  "success": true,
  "learning_path_templates": [
    {
      "id": "uuid",
      "title": "Travel",
      "description": "Practice travel conversations.",
      "level": "CEFR B1",
      "locale": "en",
      "category": "talk_lab_package",
      "prompt_config": {
        "scenario": "Travel conversation",
        "goals": ["fluency", "details"]
      },
      "position": 1,
      "created_at": "2026-07-03T10:00:00.000Z",
      "updated_at": "2026-07-03T10:00:00.000Z"
    }
  ]
}
```

前端处理建议：

- 只展示返回列表即可，后端只返回 active 模板。
- `prompt_config` 不做固定结构假设，按后台配置渲染或传给 RTC prompt builder。

## 4.2 获取单个学习模板

```http
GET /api/v1/learning_path_templates/:id
```

返回示例：

```json
{
  "success": true,
  "learning_path_template": {
    "id": "uuid",
    "title": "Travel",
    "description": "Practice travel conversations.",
    "level": "CEFR B1",
    "locale": "en",
    "category": "talk_lab_package",
    "prompt_config": {},
    "position": 1,
    "created_at": "2026-07-03T10:00:00.000Z",
    "updated_at": "2026-07-03T10:00:00.000Z"
  }
}
```

错误：

```json
{
  "success": false,
  "error": "LearningPathTemplate not found"
}
```

## 4.3 创建 Assignment Package

```http
POST /api/v1/assignment_packages
```

用途：

- 学生选择模板完成 RTC 对话后，提交对话内容。
- 后端先创建一个 `generating` 状态的 Package。
- 后端异步调用 Dify 生成 Package 内作业。

请求参数：

```json
{
  "assignment_package": {
    "learning_path_template_id": "uuid",
    "learner_profile_id": null,
    "conversation": {
      "conversation_id": "rtc-session-id",
      "transcript": "Student: ...\nAI: ...",
      "started_at": "2026-07-03T10:00:00Z",
      "ended_at": "2026-07-03T10:08:00Z",
      "duration_seconds": 480,
      "student_audio_urls": [
        "https://cdn.example.com/student-turn-1.webm"
      ],
      "ai_audio_urls": [
        "https://cdn.example.com/ai-turn-1.webm"
      ],
      "turns": [
        {
          "turn_index": 1,
          "role": "student",
          "text": "I want to talk about travel.",
          "audio_url": "https://cdn.example.com/student-turn-1.webm",
          "started_at": "2026-07-03T10:00:05Z",
          "ended_at": "2026-07-03T10:00:12Z",
          "duration_seconds": 7
        },
        {
          "turn_index": 2,
          "role": "ai",
          "text": "Great. Where would you like to go?",
          "audio_url": "https://cdn.example.com/ai-turn-1.webm",
          "started_at": "2026-07-03T10:00:13Z",
          "ended_at": "2026-07-03T10:00:18Z",
          "duration_seconds": 5
        }
      ],
      "raw_rtc_payload": {}
    }
  }
}
```

参数说明：

- `learning_path_template_id`：必填，模板 ID。
- `learner_profile_id`：预留字段，目前可以传 `null` 或不传。
- `conversation.transcript`：建议传完整 transcript；如果不传，后端会尝试用 turns 自动组装。
- `turns[].role`：建议使用 `student` 或 `ai`。后端也兼容 `assistant`，会标准化成 `ai`。
- `turns[].audio_url`：前端生成的每一轮录音 URL。
- 学生和 AI 录音 URL 都由前端生成，后端只保存 URL。

返回示例：

```json
{
  "success": true,
  "assignment_package": {
    "id": "uuid",
    "title": "Generating learning package",
    "description": "Practice travel conversations.",
    "status": "generating",
    "summary": {},
    "progress": {
      "total_items": 0,
      "completed_items": 0,
      "current_position": null,
      "completion_percentage": 0
    },
    "learning_path_template_id": "uuid",
    "learner_profile_id": null,
    "current_item": null,
    "created_at": "2026-07-03T10:08:00.000Z",
    "updated_at": "2026-07-03T10:08:00.000Z"
  }
}
```

前端处理建议：

- 创建成功后进入 Package detail 页面。
- Package 初始状态通常是 `generating`，前端可轮询 `GET /api/v1/assignment_packages/:id`。

## 4.4 获取 Assignment Package 列表

```http
GET /api/v1/assignment_packages
```

可选参数：

```text
status=generating | active | completed | failed | archived
```

返回示例：

```json
{
  "success": true,
  "assignment_packages": [
    {
      "id": "uuid",
      "title": "Travel Practice",
      "description": "Practice travel English.",
      "status": "active",
      "summary": {
        "goal": "fluency"
      },
      "progress": {
        "total_items": 3,
        "completed_items": 1,
        "current_position": 2,
        "completion_percentage": 33
      },
      "learning_path_template_id": "uuid",
      "learner_profile_id": null,
      "current_item": {
        "id": "uuid",
        "position": 2,
        "status": "available",
        "locked": false,
        "can_start": true,
        "essay_assignment": {
          "id": "uuid",
          "title": "Talk about a trip",
          "topic": "Travel",
          "category": "talk_lab_speaking",
          "code": "abc123",
          "assignment": "Discuss a past trip."
        }
      },
      "created_at": "2026-07-03T10:08:00.000Z",
      "updated_at": "2026-07-03T10:10:00.000Z"
    }
  ]
}
```

## 4.5 获取 Assignment Package 详情

```http
GET /api/v1/assignment_packages/:id
```

用途：

- Package detail 页面。
- 展示 item 列表、锁定状态和当前进度。

返回示例：

```json
{
  "success": true,
  "assignment_package": {
    "id": "uuid",
    "title": "Travel Practice",
    "description": "Practice travel English.",
    "status": "active",
    "summary": {},
    "progress": {
      "total_items": 3,
      "completed_items": 1,
      "current_position": 2,
      "completion_percentage": 33
    },
    "current_item": {
      "id": "uuid",
      "position": 2,
      "status": "available",
      "locked": false,
      "can_start": true,
      "essay_assignment": {}
    },
    "source_conversation": {
      "transcript": "Student: ...\nAI: ...",
      "turns": []
    },
    "error": {},
    "items": [
      {
        "id": "uuid",
        "position": 1,
        "status": "completed",
        "essay_grading_id": "uuid",
        "locked": false,
        "can_start": true,
        "title": "Talk about a trip",
        "category": "talk_lab_speaking",
        "essay_assignment": {
          "id": "uuid",
          "title": "Talk about a trip",
          "topic": "Travel",
          "category": "talk_lab_speaking",
          "code": "abc123",
          "assignment": "Discuss a past trip."
        },
        "unlocked_at": "2026-07-03T10:10:00.000Z",
        "completed_at": "2026-07-03T10:20:00.000Z",
        "created_at": "2026-07-03T10:10:00.000Z",
        "updated_at": "2026-07-03T10:20:00.000Z"
      }
    ]
  }
}
```

状态说明：

- `generating`：正在生成作业，前端可显示 loading 并轮询。
- `active`：已生成，可以开始练习。
- `completed`：全部 item 已完成。
- `failed`：生成失败，学生可删除并重新开始 RTC。
- `archived`：预留状态。

## 4.6 开始 Package 内某个 item

```http
GET /api/v1/assignment_packages/:id/items/:item_id/start
```

用途：

- 前端在进入 Package 内作业页面前调用。
- 后端校验 item 是否解锁。

返回成功：

```json
{
  "success": true,
  "assignment_package_item": {
    "id": "uuid",
    "position": 2,
    "status": "available",
    "locked": false,
    "can_start": true,
    "essay_assignment": {
      "id": "uuid",
      "title": "Talk about a trip",
      "topic": "Travel",
      "category": "talk_lab_speaking",
      "code": "abc123",
      "assignment": "Discuss a past trip."
    }
  },
  "essay_assignment": {
    "id": "uuid",
    "title": "Talk about a trip",
    "topic": "Travel",
    "category": "talk_lab_speaking",
    "code": "abc123",
    "assignment": "Discuss a past trip.",
    "meta": {}
  }
}
```

locked 时返回：

```json
{
  "success": false,
  "error": "AssignmentPackageItem is locked."
}
```

HTTP status：

```text
403
```

前端处理建议：

- 如果 `can_start=false` 或 API 返回 403，不允许进入作业页。
- 如果成功，使用返回的 `essay_assignment.code` 进入现有作业提交流程。

## 4.7 删除失败 Package

```http
DELETE /api/v1/assignment_packages/:id
```

规则：

- 学生只能删除自己的 `failed` Package。
- `generating`、`active`、`completed`、`archived` 不允许学生删除。

成功：

```json
{
  "success": true,
  "message": "AssignmentPackage deleted successfully"
}
```

非 failed 删除：

```json
{
  "success": false,
  "error": "Only failed assignment packages can be deleted by students."
}
```

HTTP status：

```text
422
```

## 4.8 我的作业混合列表

```http
GET /api/v1/essay_assignments/my_assignments
```

变化：

该接口现在会返回两种 `type`：

- `teacher_assignment`
- `assignment_package`

请求参数：

```text
page=1
per_page=25
status=assigned | completed | overdue
```

注意：

- `status` 只影响老师分配作业筛选。
- Package 目前返回 `generating`、`active`、`failed`，不返回 `completed`。

返回示例：

```json
{
  "success": true,
  "assignments": [
    {
      "type": "teacher_assignment",
      "id": "uuid",
      "essay_assignment": {
        "id": "uuid",
        "title": "Essay Assignment",
        "topic": "Technology",
        "category": "essay",
        "code": "abc123"
      },
      "status": "assigned",
      "deadline": null,
      "is_overdue": false,
      "days_remaining": null,
      "has_submission": false,
      "completed_at": null,
      "created_at": "2026-07-03T10:00:00.000Z",
      "updated_at": "2026-07-03T10:00:00.000Z"
    },
    {
      "type": "assignment_package",
      "id": "uuid",
      "title": "Travel Practice",
      "description": "Practice travel English.",
      "status": "active",
      "summary": {},
      "progress": {
        "total_items": 3,
        "completed_items": 1,
        "current_position": 2,
        "completion_percentage": 33
      },
      "current_item": {
        "id": "uuid",
        "position": 2,
        "status": "available",
        "locked": false,
        "can_start": true,
        "essay_assignment": {}
      },
      "created_at": "2026-07-03T10:08:00.000Z",
      "updated_at": "2026-07-03T10:10:00.000Z"
    }
  ],
  "meta": {
    "pagination": {
      "current_page": 1,
      "next_page": null,
      "prev_page": null,
      "total_pages": 1,
      "total_count": 2
    },
    "statistics": {
      "assigned_count": 1,
      "completed_count": 0,
      "overdue_count": 0,
      "assignment_packages_count": 1
    }
  }
}
```

前端处理建议：

- 根据 `type` 渲染不同卡片。
- `teacher_assignment` 维持原有逻辑。
- `assignment_package` 点击进入 Package detail。
- completed Package 不在该接口出现，如需历史列表，使用 `GET /api/v1/assignment_packages?status=completed` 或不带 status 获取所有。

## 4.9 提交 Talk Lab Speaking 作业

```http
POST /api/v1/essay_assignments/:essay_assignment_code/essay_gradings
```

请求示例：

```json
{
  "essay_grading": {
    "status": "pending",
    "using_time": 480,
    "meta": {
      "talk_lab_speaking": {
        "conversation_id": "rtc-session-id",
        "transcript": "Student: ...\nAI: ...",
        "started_at": "2026-07-03T10:00:00Z",
        "ended_at": "2026-07-03T10:08:00Z",
        "duration_seconds": 480,
        "student_audio_urls": ["https://cdn.example.com/student-1.webm"],
        "ai_audio_urls": ["https://cdn.example.com/ai-1.webm"],
        "turns": [
          {
            "turn_index": 1,
            "role": "student",
            "text": "I want to talk about travel.",
            "audio_url": "https://cdn.example.com/student-1.webm"
          },
          {
            "turn_index": 2,
            "role": "ai",
            "text": "Great. Where would you like to go?",
            "audio_url": "https://cdn.example.com/ai-1.webm"
          }
        ]
      }
    }
  }
}
```

返回示例：

```json
{
  "success": true,
  "essay_grading": {
    "id": "uuid",
    "essay": "Student: ...\nAI: ...",
    "status": "pending",
    "meta": {
      "talk_lab_speaking": {
        "conversation_id": "rtc-session-id",
        "transcript": "Student: ...\nAI: ...",
        "turns": [],
        "student_audio_urls": [],
        "ai_audio_urls": []
      }
    }
  }
}
```

注意：

- 如果 `essay_grading.essay` 没传，后端会使用 `turns` 自动组装 transcript。
- Package 内作业提交成功后，会自动更新 Package 进度并解锁下一个 item。
- 如果 item 是 locked，即使知道 assignment code，也会返回 403。

## 5. 前端页面建议

### 5.1 学习模板列表页

数据来源：

- `GET /api/v1/learning_path_templates`

交互：

- 点击模板进入 RTC 对话页面。
- 前端根据 `prompt_config` 和模板基础信息组装 prompt。

### 5.2 Package 生成中页面

数据来源：

- 创建后拿到 `assignment_package.id`
- 轮询 `GET /api/v1/assignment_packages/:id`

状态处理：

- `generating`：显示生成中。
- `active`：显示 item 列表。
- `failed`：显示失败，允许删除并重新开始。

### 5.3 Package Detail 页面

数据来源：

- `GET /api/v1/assignment_packages/:id`

交互：

- item `can_start=true` 才能点击。
- 点击 item 先调用 start API，再进入对应 category 的作业页面。

### 5.4 我的作业页面

数据来源：

- `GET /api/v1/essay_assignments/my_assignments`

渲染：

- `type=teacher_assignment`：使用现有 Assignment 卡片。
- `type=assignment_package`：展示 Package 标题、进度、当前 item。

## 6. 错误处理建议

常见错误：

```json
{
  "success": false,
  "error": "LearningPathTemplate not found"
}
```

```json
{
  "success": false,
  "error": "AssignmentPackageItem is locked."
}
```

```json
{
  "success": false,
  "error": "Only failed assignment packages can be deleted by students."
}
```

建议：

- 403 locked：提示“请先完成前一个任务”。
- 404 package/template：提示资源不存在或已失效。
- failed Package：允许用户删除后重新开始 RTC。

## 7. 对接检查清单

1. 模板列表页可展示 active `LearningPathTemplate`。
2. RTC 结束后可创建 `AssignmentPackage`。
3. Package 生成中状态可轮询。
4. Package active 后可展示 item 顺序、锁定状态和当前可做 item。
5. locked item 不可点击。
6. start item 成功后进入对应 Assignment 页面。
7. `talk_lab_speaking` 可提交 transcript 和分 turn 音频 URL。
8. 完成当前 item 后刷新 Package detail，下一个 item 被解锁。
9. `my_assignments` 可同时渲染老师分配作业和 Assignment Package。
10. failed Package 可删除，其他状态不可删除。
