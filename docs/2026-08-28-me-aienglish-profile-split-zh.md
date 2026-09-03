# me/aienglish Profile 拆分

日期：2026-08-28  
范围：`DocAI_Backend_Rails` API  
前端消费与 Grading 滚动修复见：  
[`essay-checker/docs/2026-08-28-profile-split-and-grading-scroll-zh.md`](../../essay-checker/docs/2026-08-28-profile-split-and-grading-scroll-zh.md)

## 动机

原 `GET /api/v1/general_users/me/aienglish` 一次性组装：

- 用户基本字段
- 当前学校（含多套 logo URL）
- 全部 `teaching_assignments` / `enrollments`（及学生 teachers）

组织关系查询 + Active Storage logo 成本高，拖慢 essay-checker 首屏与 Join Assignment。

## API 变更

### 1. `GET /api/v1/general_users/me/aienglish`（轻量）

**Controller：** `GeneralUsersController#show_aienglish_profile`

响应形状（示意）：

```json
{
  "success": true,
  "user": {
    "id": "...",
    "email": "...",
    "nickname": "...",
    "meta": { "...": "不含 konnecai_tokens" },
    "recovery_email": null,
    "is_recovery_email_confirmed": false,
    "school": {
      "id": "...",
      "name": "...",
      "code": "...",
      "logo_small_url": "...",
      "logo_square_url": "..."
    }
  }
}
```

说明：

- **不再**在本接口返回 `teaching_assignments` / `enrollments` / `teachers`。
- `school` 取当前有效归属（优先 active 学年），结构为 `School#as_aienglish_ui_json`。

### 2. `GET /api/v1/general_users/me/aienglish/memberships`（新增）

**Route：**

```ruby
get 'me/aienglish/memberships', to: 'general_users#show_aienglish_memberships'
```

**Controller：** `GeneralUsersController#show_aienglish_memberships`

老师：

```json
{
  "success": true,
  "memberships": {
    "role": "teacher",
    "teaching_assignments": [
      {
        "id": "...",
        "school": { "id": "...", "name": "...", "code": "...", "logo_small_url": "...", "logo_square_url": "..." },
        "academic_year": { "id": "...", "name": "...", "status": "active" },
        "department": "...",
        "position": "...",
        "created_at": "..."
      }
    ]
  }
}
```

学生：

```json
{
  "success": true,
  "memberships": {
    "role": "student",
    "enrollments": [ /* school + academic_year + class_name/number */ ],
    "teachers": [ /* id, email, nickname, phone, timestamps */ ]
  }
}
```

非 AIEnglish 用户：`400` + `{ success: false, error: "User is not an AIEnglish user" }`。

## School JSON / Logo 精简

| 方法 | 作用 |
|------|------|
| `School#ui_logo_urls` | 仅 `logo_small_url`、`logo_square_url`（当前环境均等同 base URL，只算一次） |
| `School#as_aienglish_ui_json` | `id/name/code` + `ui_logo_urls`，供 profile / memberships 复用 |
| `School#all_logo_urls` | 仍保留兼容，内部委托 `ui_logo_urls`，避免重复生成多套 SAS |

目的：去掉 essay-checker 未使用的 thumbnail/large 等重复 URL 生成。

## 主要改动文件

| 文件 | 说明 |
|------|------|
| `config/routes.rb` | 注册 `me/aienglish/memberships` |
| `app/controllers/api/v1/general_users_controller.rb` | `show_aienglish_profile` / `show_aienglish_memberships` 及私有 JSON helpers |
| `app/models/school.rb` | `ui_logo_urls`、`as_aienglish_ui_json` |

## 兼容与发布

- **破坏性：** 旧前端若仍从 `me/aienglish` 读取 `teaching_assignments` / `enrollments`，学年与 Settings 会空。需前后端同批，或后端先发后 **立刻** 发依赖 `memberships` 的 essay-checker。
- 新前端：先拿轻量 profile，再按需拉 memberships；`membershipsReady` 控制学年相关 UI。
- Admin / 其他客户端若未使用上述字段，一般无感；若有脚本依赖旧大包字段，需改调 memberships。

## 自测清单

- [ ] 老师账号：profile 含 school logo；memberships 含全部 teaching_assignments
- [ ] 学生账号：memberships 含 enrollments + teachers
- [ ] 非 AIEnglish 用户两接口均 400
- [ ] essay-checker Join Assignment 在 memberships 未返回前可操作
- [ ] 学年切换、Settings 组织列表在 memberships 返回后正确
