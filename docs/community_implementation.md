# Community功能实现总结

## 1. 数据库设计

### Communities表
- `id` (uuid): 主键
- `name` (string): Community名称，必需，最大100字符
- `description` (text): 描述，最大1000字符
- `meta` (jsonb): 元数据
- `general_user_id` (uuid): 创建者ID，外键关联general_users
- `code` (string): 6位唯一验证码，用户加入Community的凭证
- `created_at`, `updated_at`: 时间戳
- `cover`: ActiveStorage附件，Community封面图

### CommunityMemberships表（中间表）
- `id` (uuid): 主键
- `community_id` (uuid): Community ID
- `general_user_id` (uuid): 用户ID
- `meta` (jsonb): 元数据，包含role、joined_at等
- `created_at`, `updated_at`: 时间戳
- 唯一索引：`[community_id, general_user_id]`

### EssayAssignments表修改
- 添加 `community_id` (uuid): 可选的外键关联communities

## 2. 模型关系

### Community模型
- `belongs_to :general_user` (创建者)
- `has_many :community_memberships, dependent: :destroy`
- `has_many :members, through: :community_memberships, source: :general_user`
- `has_many :essay_assignments, dependent: :nullify`
- `has_one_attached :cover` (封面图)

### GeneralUser模型新增关联
- `has_many :created_communities, class_name: 'Community', dependent: :destroy`
- `has_many :community_memberships, dependent: :destroy`
- `has_many :joined_communities, through: :community_memberships, source: :community`

### EssayAssignment模型新增关联
- `belongs_to :community, optional: true`

### CommunityMembership模型
- `belongs_to :community`
- `belongs_to :general_user`
- 支持角色：member, moderator

## 3. API端点

### Community管理
- `GET /api/v1/communities` - 获取用户的所有Community
- `GET /api/v1/communities/:id` - 获取单个Community详情
- `POST /api/v1/communities` - 创建新Community
- `PATCH /api/v1/communities/:id` - 更新Community（仅创建者）
- `DELETE /api/v1/communities/:id` - 删除Community（仅创建者）

### Community加入/离开
- `POST /api/v1/communities/join_by_code` - 通过code加入Community
- `DELETE /api/v1/communities/:id/leave` - 离开Community

### Community信息查询
- `GET /api/v1/communities/:id/members` - 获取成员列表
- `GET /api/v1/communities/:id/stats` - 获取统计信息（仅创建者）
- `GET /api/v1/communities/search_by_code` - 通过code搜索Community

## 4. 核心功能

### Community创建
- 自动生成6位唯一验证码
- 支持上传封面图片（JPEG/PNG，最大5MB）
- 创建者自动成为Community管理员

### 用户加入机制
- 用户通过6位code加入Community
- 防重复加入
- 自动设置加入时间

### 权限控制
- 创建者可以管理Community（更新、删除、查看统计）
- 成员可以查看Community详情和成员列表
- 创建者不能离开自己的Community

### 统计功能
- 成员数量统计
- 作业数量统计
- 最近作业列表

## 5. 业务逻辑

### GeneralUser新增方法
- `join_community(code)` - 加入Community
- `leave_community(community)` - 离开Community
- `member_of?(community)` - 检查是否为成员
- `creator_of?(community)` - 检查是否为创建者
- `accessible_communities` - 获取可访问的所有Community

### Community核心方法
- `creator?(user)` - 检查是否为创建者
- `member?(user)` - 检查是否为成员
- `add_member(user)` - 添加成员
- `remove_member(user)` - 移除成员
- `members_count` - 成员数量
- `essay_assignments_count` - 作业数量
- `stats` - 统计信息
- `find_by_code(code)` - 通过code查找

## 6. 扩展性设计

### 为未来功能预留
- meta字段可存储额外配置
- CommunityMembership支持角色扩展
- Community可关联Course、Event等其他模型
- 支持Community层级结构（通过meta字段）

### 文件存储
- 使用ActiveStorage管理封面图片
- 支持Microsoft存储服务
- 自动生成图片URL

## 7. API响应格式

### 成功响应
```json
{
  "status": "success",
  "data": {
    "id": "uuid",
    "name": "Community名称",
    "description": "描述",
    "code": "ABC123",
    "cover_url": "图片URL",
    "creator": {
      "id": "uuid",
      "nickname": "创建者昵称",
      "email": "邮箱"
    },
    "members_count": 10,
    "essay_assignments_count": 5,
    "is_creator": true,
    "is_member": false,
    "created_at": "时间戳",
    "updated_at": "时间戳"
  }
}
```

### 错误响应
```json
{
  "status": "error",
  "message": "错误信息",
  "errors": ["具体错误列表"]
}
```

## 8. 安全考虑

- 所有API需要用户认证
- 权限检查（创建者/成员权限区分）
- 防止重复加入
- 文件上传安全验证
- Code唯一性保证

## 9. 测试覆盖

- 模型验证测试
- 关联关系测试
- 回调函数测试
- 业务逻辑方法测试
- 权限控制测试

这个实现完全满足用户需求，提供了完整的Community管理功能，包括创建、加入、管理等核心功能，同时为未来扩展预留了充分的空间。