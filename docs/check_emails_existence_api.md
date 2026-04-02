# Check Emails Existence API 功能说明

## 概述
新增了一个 API 端点，用于检查 CSV 文件中的邮箱地址在数据库中的存在状态。此功能可以帮助管理员在批量导入用户之前，预先了解哪些邮箱已存在、哪些不存在、以及哪些格式无效。

## API 端点
```
POST /api/admin/v1/general_users/check_emails_existence
```

## 请求参数
- `file` (required): CSV 文件，必须包含 `email` 列

## CSV 文件格式
```csv
email
user1@example.com
user2@test.com
admin@docai.com
student@school.edu
invalid-email-format
```

## 响应格式
### 成功响应 (200 OK)
```json
{
  "success": true,
  "summary": {
    "total_processed": 9,
    "existing_count": 3,
    "non_existing_count": 5,
    "invalid_count": 1
  },
  "existing_emails": [
    "admin@docai.com",
    "user1@example.com",
    "teacher@university.org"
  ],
  "non_existing_emails": [
    "user2@test.com",
    "student@school.edu",
    "nonexistent@fake.com",
    "another.user@domain.co.uk",
    "test123@gmail.com"
  ],
  "invalid_emails": [
    "invalid-email-format"
  ]
}
```

### 错误响应
#### 文件未找到 (400 Bad Request)
```json
{
  "success": false,
  "error": "File not found"
}
```

#### CSV 格式错误 (400 Bad Request)
```json
{
  "success": false,
  "error": "CSV format error: Illegal quoting in line 1."
}
```

#### 服务器错误 (500 Internal Server Error)
```json
{
  "success": false,
  "error": "Internal server error message"
}
```

## 功能特性

### 1. 邮箱去重
- 自动去除重复的邮箱地址
- 统计中只显示唯一邮箱数量

### 2. 邮箱格式验证
- 使用正则表达式验证邮箱格式
- 无效格式的邮箱会被单独分类

### 3. 存在性检查
- 检查邮箱是否已在 `general_users` 表中存在
- 区分已存在和不存在的邮箱

### 4. 详细统计
- `total_processed`: 处理的唯一邮箱总数
- `existing_count`: 数据库中已存在的邮箱数量
- `non_existing_count`: 数据库中不存在的邮箱数量
- `invalid_count`: 格式无效的邮箱数量

## 使用场景

### 1. 批量导入前验证
```bash
# 在执行批量导入之前，先检查邮箱状态
curl -X POST \\
  http://your-server.com/api/admin/v1/general_users/check_emails_existence \\
  -H 'Authorization: Bearer YOUR_TOKEN' \\
  -F 'file=@emails_to_check.csv'
```

### 2. 数据清理
- 识别重复的邮箱地址
- 找出格式错误的邮箱
- 确定哪些用户已经在系统中

### 3. 导入策略制定
- 根据检查结果决定是否需要跳过某些邮箱
- 为不存在的邮箱准备创建操作
- 为已存在的邮箱准备更新操作

## 实现细节

### 邮箱格式验证规则
```ruby
/\\A[\\w+\\-.]+@[a-z\\d\\-]+(\\.[a-z\\d\\-]+)*\\.[a-z]+\\z/i
```

### 性能优化
- 使用 `Set` 数据结构进行去重，提高处理效率
- 使用 `exists?` 方法进行数据库查询，减少内存使用
- 批量处理，避免逐个查询

### 错误处理
- 捕获 CSV 解析错误
- 处理文件访问异常
- 提供详细的错误信息

## 测试用例

### 测试文件: `sample_emails_check.csv`
已在项目中创建了示例文件，包含各种测试场景：
- 存在的邮箱
- 不存在的邮箱  
- 无效格式的邮箱

### 建议测试步骤
1. 使用示例 CSV 文件测试基本功能
2. 测试空文件的处理
3. 测试格式错误的 CSV 文件
4. 测试大量邮箱的性能表现

## 注意事项

1. **权限要求**: 需要管理员权限才能访问此端点
2. **文件大小**: 建议限制 CSV 文件大小，避免超时
3. **邮箱格式**: 只接受标准的邮箱格式
4. **大小写**: 邮箱地址会转换为小写进行比较
5. **编码**: CSV 文件应使用 UTF-8 编码

## 相关方法
- `batch_create`: 批量创建用户
- `batch_create_aienglish_user`: 批量创建 AIEnglish 用户
- `batch_update_aienglish_user`: 批量更新 AIEnglish 用户

建议在使用批量操作之前，先使用 `check_emails_existence` 进行预检查。