# Talk Lab 管理员后台对接文档

## 1. 文档目标

本文档提供给管理员后台开发工程师使用，说明后台需要对接的 API、参数、返回结果和页面建议。

管理员后台本阶段主要需要支持：

1. 管理 `LearningPathTemplate`。
2. 查看学生生成的 `AssignmentPackage`。
3. 查看 Package 生成详情和错误信息。
4. 删除异常 Package。
5. 对失败或异常 Package 执行 retry generation。

## 2. 管理端功能范围

### 2.1 LearningPathTemplate 管理

管理员可以：

- 查看模板列表。
- 创建模板。
- 查看模板详情。
- 更新模板。
- 停用/归档模板。

模板用于学生端展示和 RTC prompt 组装。

### 2.2 AssignmentPackage 管理

管理员可以：

- 查看所有学生生成的 Package。
- 按学生、模板、状态筛选。
- 查看 Package 内部 item 和生成出来的 Assignment。
- 查看 Dify 请求、Dify 返回、错误信息。
- 删除任意状态 Package。
- 对 Package 重新执行生成任务。

注意：

- 老师暂不管理学生自创建 Package。
- 管理员删除 Package 是高风险操作，前端建议二次确认。

## 3. API 路由总览

### LearningPathTemplate

```http
GET    /api/admin/v1/learning_path_templates
GET    /api/admin/v1/learning_path_templates/:id
POST   /api/admin/v1/learning_path_templates
PATCH  /api/admin/v1/learning_path_templates/:id
DELETE /api/admin/v1/learning_path_templates/:id
```

### AssignmentPackage

```http
GET    /api/admin/v1/assignment_packages
GET    /api/admin/v1/assignment_packages/:id
DELETE /api/admin/v1/assignment_packages/:id
POST   /api/admin/v1/assignment_packages/:id/retry_generation
```

## 4. LearningPathTemplate API

## 4.1 获取模板列表

```http
GET /api/admin/v1/learning_path_templates
```

可选参数：

```text
status=draft | active | archived
category=talk_lab_package
```

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
      "status": "active",
      "dify_config": {
        "app_key": "app-xxx"
      },
      "usage_policy": {},
      "created_by_id": "uuid",
      "created_at": "2026-07-03T10:00:00.000Z",
      "updated_at": "2026-07-03T10:00:00.000Z"
    }
  ]
}
```

字段说明：

- `status`
  - `draft`：草稿，学生端不可见。
  - `active`：启用，学生端可见。
  - `archived`：归档，学生端不可见。
- `category`
  - 当前建议使用 `talk_lab_package`。
- `prompt_config`
  - 给前端学生端组装 RTC prompt 使用。
  - 后端不限制内部结构。
- `dify_config`
  - 给后端调用 Dify Package Generator 使用。
  - 推荐至少配置 `app_key`。
- `usage_policy`
  - 预留字段，目前不限制学生使用次数。

## 4.2 获取模板详情

```http
GET /api/admin/v1/learning_path_templates/:id
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
    "status": "active",
    "dify_config": {
      "app_key": "app-xxx"
    },
    "usage_policy": {},
    "created_by_id": "uuid",
    "created_at": "2026-07-03T10:00:00.000Z",
    "updated_at": "2026-07-03T10:00:00.000Z"
  }
}
```

## 4.3 创建模板

```http
POST /api/admin/v1/learning_path_templates
```

请求示例：

```json
{
  "learning_path_template": {
    "title": "Travel",
    "description": "Practice travel conversations.",
    "status": "active",
    "level": "CEFR B1",
    "locale": "en",
    "category": "talk_lab_package",
    "position": 1,
    "prompt_config": {
      "scenario": "Travel conversation",
      "student_goal": "Talk about travel plans and past trips.",
      "rtc_instructions": [
        "Ask follow-up questions.",
        "Encourage detailed answers."
      ]
    },
    "dify_config": {
      "app_key": "app-xxx"
    },
    "usage_policy": {}
  }
}
```

必填建议：

- `title`
- `category`
- `prompt_config`
- `dify_config.app_key`

后端校验：

- `title` 必填。
- `category` 必填。
- `prompt_config`、`dify_config`、`usage_policy` 必须是 JSON object。

成功返回：

```json
{
  "success": true,
  "learning_path_template": {
    "id": "uuid",
    "title": "Travel",
    "status": "active",
    "prompt_config": {},
    "dify_config": {},
    "usage_policy": {},
    "created_at": "2026-07-03T10:00:00.000Z",
    "updated_at": "2026-07-03T10:00:00.000Z"
  }
}
```

失败返回：

```json
{
  "success": false,
  "errors": ["Title can't be blank"]
}
```

HTTP status：

```text
422
```

## 4.4 更新模板

```http
PATCH /api/admin/v1/learning_path_templates/:id
```

请求参数与创建模板相同，所有字段均可局部更新。

请求示例：

```json
{
  "learning_path_template": {
    "title": "Travel Speaking Practice",
    "status": "active",
    "position": 2,
    "prompt_config": {
      "scenario": "Travel conversation"
    },
    "dify_config": {
      "app_key": "app-new"
    }
  }
}
```

返回示例：

```json
{
  "success": true,
  "learning_path_template": {
    "id": "uuid",
    "title": "Travel Speaking Practice",
    "status": "active",
    "position": 2,
    "prompt_config": {
      "scenario": "Travel conversation"
    },
    "dify_config": {
      "app_key": "app-new"
    }
  }
}
```

## 4.5 归档模板

```http
DELETE /api/admin/v1/learning_path_templates/:id
```

说明：

- 当前不是物理删除。
- 后端会把模板状态改为 `archived`。
- archived 模板不会出现在学生端模板列表。

返回示例：

```json
{
  "success": true,
  "learning_path_template": {
    "id": "uuid",
    "status": "archived"
  }
}
```

## 5. AssignmentPackage 管理 API

## 5.1 获取 Package 列表

```http
GET /api/admin/v1/assignment_packages
```

可选参数：

```text
status=generating | active | completed | failed | archived
general_user_id=uuid
learning_path_template_id=uuid
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
        "essay_assignment": {}
      },
      "student": {
        "id": "uuid",
        "email": "student@example.com",
        "nickname": "Student A"
      },
      "learning_path_template": {
        "id": "uuid",
        "title": "Travel",
        "description": "Practice travel conversations.",
        "prompt_config": {}
      },
      "created_at": "2026-07-03T10:00:00.000Z",
      "updated_at": "2026-07-03T10:20:00.000Z"
    }
  ]
}
```

后台页面建议：

- 显示学生、模板、状态、进度、创建时间。
- 对 `failed` 状态突出显示错误入口。
- 对 `generating` 状态显示“生成中”。
- 对任意状态提供管理员删除，但需要二次确认。

## 5.2 获取 Package 详情

```http
GET /api/admin/v1/assignment_packages/:id
```

用途：

- 查看完整生成记录。
- 查看 source conversation。
- 查看 Dify request/response。
- 查看错误信息。
- 查看 Package 内 item 和对应 Assignment。

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
    "student": {
      "id": "uuid",
      "email": "student@example.com",
      "nickname": "Student A"
    },
    "learning_path_template": {
      "id": "uuid",
      "title": "Travel",
      "description": "Practice travel conversations.",
      "prompt_config": {}
    },
    "source_conversation": {
      "conversation_id": "rtc-session-id",
      "transcript": "Student: ...\nAI: ...",
      "turns": [],
      "student_audio_urls": [],
      "ai_audio_urls": []
    },
    "dify_request": {
      "template_title": "Travel",
      "transcript": "Student: ...\nAI: ..."
    },
    "dify_response": {
      "data": {
        "outputs": {}
      }
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
    ],
    "created_at": "2026-07-03T10:00:00.000Z",
    "updated_at": "2026-07-03T10:20:00.000Z"
  }
}
```

字段说明：

- `source_conversation`：学生用模板生成 Package 前的 RTC 对话记录。
- `dify_request`：后端发给 Dify 的输入。
- `dify_response`：Dify 返回内容。
- `error`：生成失败时保存错误信息。
- `items`：Package 内作业顺序、锁定状态、完成状态。

## 5.3 删除 Package

```http
DELETE /api/admin/v1/assignment_packages/:id
```

说明：

- 管理员可以删除任意状态 Package。
- 删除 Package 会清理关联 item 和生成出来的 Assignment。
- 前端必须做二次确认。

成功返回：

```json
{
  "success": true,
  "message": "AssignmentPackage deleted successfully"
}
```

失败返回：

```json
{
  "success": false,
  "error": "AssignmentPackage not found"
}
```

## 5.4 重试生成 Package

```http
POST /api/admin/v1/assignment_packages/:id/retry_generation
```

用途：

- Package 生成失败后，管理员可以重试。
- 也可用于排查 Dify 配置修复后的重新生成。

处理逻辑：

- 后端将 Package 状态改为 `generating`。
- 清空 `error`。
- 重新进入 `AssignmentPackageGenerationJob`。
- 生成成功后会重建 Package items。

返回示例：

```json
{
  "success": true,
  "assignment_package": {
    "id": "uuid",
    "title": "Travel Practice",
    "status": "generating",
    "progress": {
      "total_items": 0,
      "completed_items": 0,
      "current_position": null,
      "completion_percentage": 0
    },
    "error": {}
  }
}
```

后台处理建议：

- 点击 retry 前二次确认。
- retry 后刷新详情或轮询详情接口。
- 如果再次失败，详情里的 `error` 会显示失败原因。

## 6. Package 状态说明

```text
generating  正在生成
active      已生成，可使用
completed   学生已完成全部 item
failed      生成失败
archived    预留归档状态
```

后台展示建议：

- `generating`：蓝色/进行中。
- `active`：绿色/可使用。
- `completed`：灰色或完成态。
- `failed`：红色/需要处理。
- `archived`：灰色/归档。

## 7. Template 状态说明

```text
draft     草稿，学生不可见
active    启用，学生可见
archived  归档，学生不可见
```

后台展示建议：

- 默认只显示非 archived，或提供 status filter。
- archived 不物理删除，方便保留历史关系。

## 8. Dify 配置说明

模板中推荐配置：

```json
{
  "dify_config": {
    "app_key": "app-xxx"
  }
}
```

后端读取顺序：

1. `dify_config.app_key`
2. `dify_config.package_generator_app_key`
3. 环境变量 `ASSIGNMENT_PACKAGE_GENERATOR_APP_KEY`
4. 环境变量 `assignment_package_generator_app_key`

管理员后台建议：

- 创建或更新模板时，提示 `dify_config.app_key` 是生成学习包的 Dify workflow key。
- 如果缺失，学生创建 Package 后会进入 `failed`。

## 9. Dify 返回内容要求

Dify 应返回 JSON，结构建议：

```json
{
  "title": "Travel Practice",
  "description": "Practice travel English.",
  "summary": {
    "goal": "fluency"
  },
  "assignments": [
    {
      "category": "talk_lab_speaking",
      "title": "Talk about a trip",
      "topic": "Travel",
      "assignment": "Discuss a past trip.",
      "hints": "Use past tense.",
      "rubric": {
        "name": "Talk Lab Speaking"
      },
      "meta": {}
    }
  ]
}
```

规则：

- `assignments` 必须至少有一个支持的 Assignment category。
- 不支持的 category 会被后端跳过。
- 如果全部 category 都不支持，Package 会失败。
- `talk_lab_speaking` 的评分 app key 由后端固定规则写入，不需要 Dify 返回。

## 10. 后台页面建议

### 10.1 模板列表页

字段：

- 标题
- 状态
- 等级
- 语言
- 分类
- 排序
- 更新时间

操作：

- 新增
- 编辑
- 归档
- 查看详情

### 10.2 模板编辑页

表单：

- `title`
- `description`
- `status`
- `level`
- `locale`
- `category`
- `position`
- `prompt_config` JSON editor
- `dify_config` JSON editor
- `usage_policy` JSON editor

建议：

- JSON editor 需要校验必须是 object。
- `status=active` 后学生端可见。

### 10.3 Package 列表页

筛选：

- 状态
- 学生
- 模板

字段：

- Package 标题
- 学生
- 模板
- 状态
- 总 item 数
- 已完成 item 数
- 当前 position
- 创建时间
- 更新时间

操作：

- 查看详情
- 删除
- failed 时 retry

### 10.4 Package 详情页

区域：

- 基础信息
- 学生信息
- 模板信息
- 进度信息
- Source conversation
- Dify request
- Dify response
- Error
- Items 列表

建议：

- `source_conversation`、`dify_request`、`dify_response`、`error` 使用 JSON viewer。
- item 列表展示 Assignment code，方便管理员排查。

## 11. 管理端对接检查清单

1. 可以创建 `LearningPathTemplate`。
2. `active` 模板能在学生端看到。
3. `archived` 模板不会在学生端看到。
4. 可以编辑 `prompt_config` 和 `dify_config`。
5. 可以查看所有学生 Assignment Package。
6. 可以按状态、学生、模板筛选 Package。
7. 可以查看 Package source conversation。
8. 可以查看 Dify request/response。
9. 可以查看 failed Package 的 error。
10. 可以 retry failed Package。
11. 可以删除任意状态 Package，且前端有二次确认。
