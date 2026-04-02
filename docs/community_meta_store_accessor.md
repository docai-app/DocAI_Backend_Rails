# Community Meta字段使用Store Accessor

## 📋 修改总结

已按照要求将Community模型的meta字段从`attribute :meta, :json, default: {}`和`validates :meta, presence: true`改为使用`store_accessor :meta`的方式。

## 🔧 修改内容

### 1. Community模型变更

**修改前：**
```ruby
class Community < ApplicationRecord
  # 设置属性默认值
  attribute :meta, :json, default: {}
  
  # 验证
  validates :meta, presence: true
end
```

**修改后：**
```ruby
class Community < ApplicationRecord
  # Meta字段访问器 - 为未来扩展预留空间
  store_accessor :meta, :community_type, :settings, :features, :permissions, :custom_fields
  
  # 验证（移除了meta的presence验证）
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 1000 }
  validates :code, presence: true, uniqueness: true, length: { is: 6 }
end
```

### 2. 数据库迁移

创建了新的迁移文件来允许meta字段为null：

```ruby
# db/migrate/20250825092003_change_communities_meta_nullable.rb
class ChangeCommunitiesMetaNullable < ActiveRecord::Migration[7.0]
  def change
    change_column_null :communities, :meta, true
  end
end
```

## 🚀 使用方法

### 基本用法

```ruby
# 创建Community
community = Community.create!(
  name: "学习社区",
  description: "这是一个学习交流的社区",
  general_user: current_user
)

# 使用store_accessor字段
community.community_type = "education"
community.settings = { allow_public_join: true, moderation: "auto" }
community.features = ["essay_assignments", "discussions", "file_sharing"]
community.permissions = { create_assignments: ["creator", "moderator"] }
community.custom_fields = { max_members: 100, theme: "blue" }
community.save!
```

### 读取数据

```ruby
# 直接访问store_accessor字段
puts community.community_type  # "education"
puts community.settings        # {"allow_public_join"=>true, "moderation"=>"auto"}
puts community.features        # ["essay_assignments", "discussions", "file_sharing"]

# 也可以直接访问meta字段
puts community.meta            # 包含所有存储的数据
```

### 在API中使用

```ruby
# 在Community控制器中
def community_params
  params.require(:community).permit(
    :name, :description, :cover,
    :community_type, :custom_fields,
    settings: {},
    features: [],
    permissions: {}
  )
end
```

## 🔄 API请求示例

### 创建带有meta字段的Community

```bash
POST /api/v1/communities
Content-Type: application/json
Authorization: Bearer <token>

{
  "community": {
    "name": "高级学习社区",
    "description": "专为高级学习者设计的社区",
    "community_type": "premium",
    "settings": {
      "allow_public_join": false,
      "moderation": "manual",
      "max_members": 50
    },
    "features": [
      "essay_assignments",
      "live_sessions",
      "progress_tracking"
    ],
    "permissions": {
      "create_assignments": ["creator", "moderator"],
      "moderate_content": ["creator", "moderator"],
      "invite_members": ["creator", "moderator", "member"]
    }
  }
}
```

### 响应示例

```json
{
  "status": "success",
  "data": {
    "id": "uuid-here",
    "name": "高级学习社区",
    "description": "专为高级学习者设计的社区",
    "code": "ABC123",
    "community_type": "premium",
    "settings": {
      "allow_public_join": false,
      "moderation": "manual",
      "max_members": 50
    },
    "features": [
      "essay_assignments",
      "live_sessions", 
      "progress_tracking"
    ],
    "permissions": {
      "create_assignments": ["creator", "moderator"],
      "moderate_content": ["creator", "moderator"],
      "invite_members": ["creator", "moderator", "member"]
    },
    "creator": {
      "id": "user-uuid",
      "nickname": "用户昵称"
    },
    "created_at": "2025-08-25T12:00:00Z"
  }
}
```

## 🎯 预留的扩展字段

根据Community模块开发规范，我们为未来的Course、Event等模型预留了以下扩展空间：

### 1. community_type（社区类型）
- `"education"` - 教育类社区
- `"business"` - 商业类社区
- `"hobby"` - 兴趣爱好社区
- `"course"` - 课程社区（为未来Course模块预留）
- `"event"` - 活动社区（为未来Event模块预留）

### 2. settings（设置）
```ruby
{
  "allow_public_join": true,           # 是否允许公开加入
  "moderation": "auto",                # 内容审核模式
  "max_members": 100,                  # 最大成员数
  "language": "zh-CN",                 # 社区语言
  "timezone": "Asia/Shanghai"          # 时区设置
}
```

### 3. features（功能特性）
```ruby
[
  "essay_assignments",                 # 作业功能
  "discussions",                       # 讨论功能
  "file_sharing",                      # 文件分享
  "live_sessions",                     # 直播会话（为Course预留）
  "events",                           # 活动功能（为Event预留）
  "progress_tracking",                # 进度跟踪
  "certificates"                      # 证书功能
]
```

### 4. permissions（权限配置）
```ruby
{
  "create_assignments": ["creator", "moderator"],
  "moderate_content": ["creator", "moderator"],
  "invite_members": ["creator", "moderator", "member"],
  "create_events": ["creator", "moderator"],        # 为Event预留
  "create_courses": ["creator"]                      # 为Course预留
}
```

### 5. custom_fields（自定义字段）
为特定使用场景预留的完全自定义字段。

## ⚠️ 注意事项

1. **数据库迁移**：在使用前请运行 `rails db:migrate` 来应用新的迁移
2. **向后兼容**：现有的Community记录不受影响，meta字段仍然存在
3. **null值处理**：由于移除了meta的presence验证，现在允许meta为null
4. **性能考虑**：store_accessor字段的查询需要使用JSONB查询语法

## 🔍 查询示例

```ruby
# 查询特定community_type的社区
Community.where("meta->>'community_type' = ?", "education")

# 查询包含特定功能的社区
Community.where("meta->'features' ? ?", "live_sessions")

# 查询设置了最大成员数的社区
Community.where("meta->'settings'->>'max_members' IS NOT NULL")
```

这种方式提供了更大的灵活性，完全符合Community模块开发规范中为未来Course、Event等模型预留扩展空间的要求。