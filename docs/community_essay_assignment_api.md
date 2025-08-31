# Community与EssayAssignment关联功能API文档

## 新增功能概述

本文档描述了Community与EssayAssignment关联功能的API接口，实现了以下核心需求：

1. **创建EssayAssignment时指定Community** - 在Community ID下创建作业
2. **通过Community ID获取所有EssayAssignment** - 查看Community内的所有作业

## API接口详情

### 1. 创建EssayAssignment并指定Community

**端点**: `POST /api/v1/essay_assignments`

**请求头**: 
```
Authorization: Bearer <token>
Content-Type: application/json
```

**请求体**:
```json
{
  "essay_assignment": {
    "title": "作业标题",
    "topic": "作业主题",
    "assignment": "作业内容",
    "category": "essay",
    "hints": "提示信息",
    "answer_visible": true,
    "community_id": "community-uuid-here",
    "rubric": {
      "name": "评分标准名称",
      "app_key": {
        "grading": "grading-key",
        "general_context": "context-key"
      }
    },
    "meta": {
      "custom_field": "自定义数据"
    }
  }
}
```

**成功响应** (201 Created):
```json
{
  "success": true,
  "essay_assignment": {
    "id": "assignment-uuid",
    "title": "作业标题",
    "topic": "作业主题",
    "assignment": "作业内容",
    "category": "essay",
    "code": "ABC123",
    "community_id": "community-uuid-here",
    "community": {
      "id": "community-uuid-here",
      "name": "Community名称",
      "code": "COMM01"
    },
    "created_at": "2025-08-25T10:00:00Z",
    "updated_at": "2025-08-25T10:00:00Z"
  }
}
```

**错误响应**:
- `404` Community not found
- `403` Access denied. You must be a member or creator of this community
- `422` Validation errors

### 2. 获取用户的EssayAssignment（支持Community筛选）

**端点**: `GET /api/v1/essay_assignments`

**查询参数**:
- `community_id` (可选): Community UUID
- `category` (可选): 作业类型筛选
- `page` (可选): 分页页码

**示例请求**:
```
GET /api/v1/essay_assignments?community_id=community-uuid&category=essay&page=1
```

**成功响应** (200 OK):
```json
{
  "success": true,
  "essay_assignments": [
    {
      "id": "assignment-uuid",
      "title": "作业标题",
      "topic": "作业主题",
      "category": "essay",
      "code": "ABC123",
      "community_id": "community-uuid",
      "community": {
        "id": "community-uuid",
        "name": "Community名称",
        "code": "COMM01"
      },
      "created_at": "2025-08-25T10:00:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "next_page": null,
    "prev_page": null,
    "total_pages": 1,
    "total_count": 1
  }
}
```

### 3. 通过Community ID获取所有EssayAssignment

**端点**: `GET /api/v1/essay_assignments/by_community/:community_id`

**路径参数**:
- `community_id`: Community的UUID

**查询参数**:
- `category` (可选): 作业类型筛选
- `page` (可选): 分页页码

**示例请求**:
```
GET /api/v1/essay_assignments/by_community/community-uuid-here?category=essay&page=1
```

**成功响应** (200 OK):
```json
{
  "success": true,
  "community": {
    "id": "community-uuid",
    "name": "Community名称",
    "code": "COMM01",
    "description": "Community描述"
  },
  "essay_assignments": [
    {
      "id": "assignment-uuid",
      "title": "作业标题",
      "topic": "作业主题",
      "category": "essay",
      "code": "ABC123",
      "hints": "提示信息",
      "answer_visible": true,
      "number_of_submission": 5,
      "creator": {
        "id": "user-uuid",
        "nickname": "创建者昵称",
        "email": "creator@example.com"
      },
      "community": {
        "id": "community-uuid",
        "name": "Community名称",
        "code": "COMM01"
      },
      "created_at": "2025-08-25T10:00:00Z",
      "updated_at": "2025-08-25T10:00:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "next_page": null,
    "prev_page": null,
    "total_pages": 1,
    "total_count": 1
  }
}
```

**错误响应**:
- `400` Community ID is required
- `404` Community not found
- `403` Access denied to this community

### 4. 通过Community获取EssayAssignment（Communities控制器）

**端点**: `GET /api/v1/communities/:id/essay_assignments`

**路径参数**:
- `id`: Community的UUID

**查询参数**:
- `category` (可选): 作业类型筛选
- `page` (可选): 分页页码，默认1
- `per_page` (可选): 每页数量，默认20

**示例请求**:
```
GET /api/v1/communities/community-uuid/essay_assignments?category=essay&page=1&per_page=10
```

**成功响应** (200 OK):
```json
{
  "status": "success",
  "data": {
    "community": {
      "id": "community-uuid",
      "name": "Community名称",
      "code": "COMM01",
      "description": "Community描述"
    },
    "essay_assignments": [
      {
        "id": "assignment-uuid",
        "title": "作业标题",
        "topic": "作业主题",
        "category": "essay",
        "code": "ABC123",
        "hints": "提示信息",
        "answer_visible": true,
        "number_of_submission": 5,
        "creator": {
          "id": "user-uuid",
          "nickname": "创建者昵称",
          "email": "creator@example.com"
        },
        "created_at": "2025-08-25T10:00:00Z",
        "updated_at": "2025-08-25T10:00:00Z"
      }
    ],
    "meta": {
      "total_count": 25,
      "page": 1,
      "per_page": 10
    }
  }
}
```

## 权限控制

### Community访问权限
- **创建者权限**: Community的创建者可以创建、查看、修改Community下的所有EssayAssignment
- **成员权限**: Community成员可以查看Community下的所有EssayAssignment，并可以在Community内创建新的EssayAssignment
- **非成员**: 无法访问Community内容

### EssayAssignment创建权限
1. 必须是已认证用户
2. 如果指定了`community_id`，必须是该Community的创建者或成员
3. 如果不指定`community_id`，可以创建个人作业

## 业务逻辑

### 创建流程
1. 验证用户认证状态
2. 如果指定了`community_id`：
   - 验证Community是否存在
   - 验证用户是否有权限访问该Community
3. 创建EssayAssignment并关联到Community
4. 返回包含Community信息的完整响应

### 查询流程
1. 验证用户认证状态
2. 验证Community是否存在
3. 验证用户是否有权限访问该Community
4. 查询Community下的所有EssayAssignment
5. 支持分类筛选和分页
6. 返回包含创建者信息的详细数据

## 数据库关系

```
Community (1) ←→ (many) EssayAssignment
```

- `essay_assignments.community_id` 外键关联到 `communities.id`
- 关联为可选（`optional: true`），支持个人作业不属于任何Community
- 删除Community时，关联的EssayAssignment的`community_id`会被设置为NULL（`dependent: :nullify`）

## 错误处理

### 常见错误场景
1. **Community不存在**: 返回404错误
2. **权限不足**: 返回403错误，用户不是Community成员或创建者
3. **参数缺失**: 返回400错误，缺少必需的参数
4. **验证失败**: 返回422错误，数据验证不通过

### 错误响应格式
```json
{
  "success": false,
  "error": "错误信息描述"
}
```

## 使用示例

### 场景1: 在Community中创建作业
```bash
curl -X POST "https://api.example.com/api/v1/essay_assignments" \
  -H "Authorization: Bearer your-token" \
  -H "Content-Type: application/json" \
  -d '{
    "essay_assignment": {
      "title": "英语写作练习1",
      "topic": "环境保护",
      "assignment": "写一篇关于环境保护的短文",
      "category": "essay",
      "community_id": "your-community-uuid"
    }
  }'
```

### 场景2: 查看Community中的所有作业
```bash
curl -X GET "https://api.example.com/api/v1/communities/your-community-uuid/essay_assignments?category=essay" \
  -H "Authorization: Bearer your-token"
```

### 场景3: 按Community筛选用户作业
```bash
curl -X GET "https://api.example.com/api/v1/essay_assignments?community_id=your-community-uuid" \
  -H "Authorization: Bearer your-token"
```

这些功能完全实现了Community与EssayAssignment的关联需求，支持灵活的权限控制和数据查询。