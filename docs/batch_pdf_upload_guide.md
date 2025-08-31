# 批量PDF上传功能使用指南

## 概述

批量PDF上传功能允许教师一次性上传多个PDF文件，系统会自动：
1. 从文件名提取学生email
2. 使用OCR技术提取PDF内容作为学生作业
3. 为每个学生创建对应的EssayGrading记录
4. 返回找不到email学生的名单列表

## API端点

**POST** `/api/v1/essay_assignments/{essay_assignment_id}/essay_gradings/batch_upload_pdfs`

### 请求参数

- **essay_assignment_id** (路径参数): 作业的唯一代码
- **pdf_files** (表单数据): PDF文件数组，支持多文件上传

### 权限要求

- 用户必须是AI English用户
- 用户角色必须是 `teacher` 或 `admin`
- 需要有效的JWT认证

## 使用方法

### 1. 准备PDF文件

- 确保PDF文件名格式为：`student_email.pdf`
- 例如：`student1@example.com.pdf`, `student2@example.com.pdf`
- PDF文件应包含学生的作业内容

### 2. 调用API

```bash
curl -X POST \
  "https://your-domain.com/api/v1/essay_assignments/ASMT-001/essay_gradings/batch_upload_pdfs" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -F "pdf_files=@student1@example.com.pdf" \
  -F "pdf_files=@student2@example.com.pdf" \
  -F "pdf_files=@student3@example.com.pdf"
```

### 3. 响应示例

#### 成功响应 (201 Created)

```json
{
  "success": true,
  "message": "Successfully processed 3 PDF files",
  "processed_count": 3,
  "successful_gradings": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "student_email": "student1@example.com",
      "student_name": "张三",
      "status": "pending",
      "created_at": "2023-10-27T10:00:00.000Z"
    },
    {
      "id": "456e7890-e89b-12d3-a456-426614174000",
      "student_email": "student2@example.com",
      "student_name": "李四",
      "status": "pending",
      "created_at": "2023-10-27T10:00:01.000Z"
    }
  ],
  "not_found_emails": [
    "unknown@example.com",
    "invalid@example.com"
  ]
}
```

#### 部分失败响应 (422 Unprocessable Entity)

```json
{
  "success": false,
  "error": "Failed to process some PDF files",
  "processed_count": 2,
  "errors": [
    "Student not found for email: unknown@example.com",
    "Could not extract content from PDF for student: invalid@example.com"
  ],
  "successful_gradings": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "student_email": "student1@example.com",
      "student_name": "张三",
      "status": "pending",
      "created_at": "2023-10-27T10:00:00.000Z"
    }
  ],
  "not_found_emails": [
    "unknown@example.com",
    "invalid@example.com"
  ]
}
```

## 工作流程

1. **文件验证**: 检查上传的文件是否为PDF格式
2. **权限检查**: 验证用户是否有批量上传权限
3. **文件名解析**: 从文件名提取学生email
4. **学生查找**: 根据email查找对应的学生用户
5. **重复检查**: 检查学生是否已有该作业的评分记录
6. **内容提取**: 使用PDF-Reader提取文本内容，必要时使用Azure OCR
7. **记录创建**: 创建EssayGrading记录并附加PDF文件到 `has_one_attached :file`
8. **事件跟踪**: 记录作业提交事件
9. **结果返回**: 返回成功创建的记录和找不到的email列表

## 错误处理

### 常见错误类型

- **400 Bad Request**: 缺少PDF文件或文件格式错误
- **401 Unauthorized**: 用户未认证
- **403 Forbidden**: 用户权限不足
- **404 Not Found**: 作业不存在
- **422 Unprocessable Entity**: 处理失败（部分成功）
- **500 Internal Server Error**: 服务器内部错误

### 错误原因

- 学生email在系统中不存在（会记录在 `not_found_emails` 中）
- PDF文件无法读取或内容为空
- 学生已有该作业的评分记录
- 文件格式不支持

## 技术实现

### 核心组件

- **BatchPdfEssayService**: 主要的业务逻辑服务
- **PDF-Reader**: PDF文本提取
- **Azure OCR**: 备选的OCR服务（当PDF-Reader失败时）
- **Active Storage**: 文件存储管理（Azure Storage集成）

### 性能考虑

- 支持异步处理（通过Sidekiq）
- 批量处理多个文件
- 错误隔离（单个文件失败不影响其他文件）
- Active Storage提供高效的文件管理和访问

## 最佳实践

1. **文件命名**: 使用标准email格式作为文件名
2. **文件大小**: 建议单个PDF文件不超过10MB
3. **内容质量**: 确保PDF内容清晰可读
4. **批量大小**: 建议单次上传不超过50个文件
5. **错误处理**: 检查响应中的错误信息和找不到的email列表

## 注意事项

- 文件名必须与学生email完全匹配（区分大小写）
- 系统会自动跳过已有评分记录的学生
- PDF内容提取失败的文件会被标记为错误
- 成功创建的记录会触发正常的作业评分流程
- 所有PDF文件通过Active Storage管理，支持Azure Storage云存储
- 找不到email的学生会记录在 `not_found_emails` 数组中

## 故障排除

### 常见问题

1. **权限错误**: 检查用户角色和AI English功能权限
2. **文件格式错误**: 确保上传的是PDF文件
3. **学生不存在**: 检查email是否在系统中注册
4. **内容提取失败**: 检查PDF是否包含可提取的文本

### 调试信息

- 查看Rails日志获取详细错误信息
- 检查PDF文件是否损坏或受密码保护
- 验证学生用户数据完整性
- 检查 `not_found_emails` 数组中的email列表
