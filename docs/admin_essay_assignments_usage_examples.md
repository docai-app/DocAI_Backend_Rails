# 管理员作业管理API使用示例

## 1. 作业概览统计

```bash
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments/overview" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json"
```

## 2. 获取作业列表（带搜索和过滤）

```bash
# 基本列表
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"

# 搜索IELTS相关作业
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments?search=IELTS" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"

# 按类别过滤essay类型作业
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments?category=essay" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"

# 按提交数量降序排列
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments?sort_by=submissions_count&sort_order=desc" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"

# 复合查询：搜索特定创建者的essay类型作业
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments?creator_id=12345&category=essay&page=1&per_page=10" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"
```

## 3. 获取作业详情

```bash
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments/abc123" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"
```

## 4. 查看作业的所有提交记录

```bash
# 获取所有提交
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments/abc123/submissions" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"

# 只查看已评分的提交
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments/abc123/submissions?status=graded" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"

# 搜索特定学生的提交
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments/abc123/submissions?student_search=张三" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"
```

## 5. 更新作业信息

```bash
curl -X PATCH "http://localhost:3000/api/admin/v1/essay_assignments/abc123" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "essay_assignment": {
      "title": "Updated IELTS Writing Task 1",
      "topic": "Updated topic description",
      "answer_visible": false,
      "remark": "Updated remark for this assignment",
      "hints": "New hints for students"
    }
  }'
```

## 6. 获取辅助数据

```bash
# 获取所有作业类别
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments/categories" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"

# 获取所有创建者
curl -X GET "http://localhost:3000/api/admin/v1/essay_assignments/creators" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"
```

## 前端集成示例（JavaScript）

```javascript
class EssayAssignmentAdmin {
  constructor(baseURL, token) {
    this.baseURL = baseURL;
    this.token = token;
  }

  async getOverview() {
    const response = await fetch(`${this.baseURL}/api/admin/v1/essay_assignments/overview`, {
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json'
      }
    });
    return response.json();
  }

  async getAssignments(filters = {}) {
    const params = new URLSearchParams(filters);
    const response = await fetch(`${this.baseURL}/api/admin/v1/essay_assignments?${params}`, {
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json'
      }
    });
    return response.json();
  }

  async getAssignmentDetail(id) {
    const response = await fetch(`${this.baseURL}/api/admin/v1/essay_assignments/${id}`, {
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json'
      }
    });
    return response.json();
  }

  async getSubmissions(assignmentId, filters = {}) {
    const params = new URLSearchParams(filters);
    const response = await fetch(`${this.baseURL}/api/admin/v1/essay_assignments/${assignmentId}/submissions?${params}`, {
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json'
      }
    });
    return response.json();
  }

  async updateAssignment(id, data) {
    const response = await fetch(`${this.baseURL}/api/admin/v1/essay_assignments/${id}`, {
      method: 'PATCH',
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ essay_assignment: data })
    });
    return response.json();
  }
}

// 使用示例
const admin = new EssayAssignmentAdmin('http://localhost:3000', 'your_token_here');

// 获取概览
admin.getOverview().then(data => console.log(data));

// 搜索作业
admin.getAssignments({ 
  search: 'IELTS', 
  category: 'essay', 
  page: 1, 
  per_page: 20 
}).then(data => console.log(data));

// 更新作业
admin.updateAssignment('abc123', {
  title: 'New Title',
  answer_visible: false
}).then(data => console.log(data));
```

## 响应数据结构示例

### 概览统计响应
```json
{
  "success": true,
  "data": {
    "overview": {
      "total_assignments": 150,
      "total_submissions": 1250,
      "recent_assignments": 15,
      "category_stats": {
        "Essay": 80,
        "Comprehension": 50,
        "Speaking conversation": 20
      },
      "category_percentages": {
        "Essay": 53.33,
        "Comprehension": 33.33,
        "Speaking conversation": 13.34
      },
      "submission_stats": {
        "pending": 45,
        "graded": 980,
        "grading": 225
      },
      "top_assignments": [
        {
          "id": "abc123",
          "title": "IELTS Writing Task 1",
          "topic": "Data Analysis",
          "submissions_count": 156
        }
      ]
    }
  }
}
```

### 作业列表响应
```json
{
  "success": true,
  "data": {
    "assignments": [
      {
        "id": "abc123",
        "title": "IELTS Writing Task 1",
        "topic": "Data Analysis and Chart Description",
        "assignment": "Write a report describing the data...",
        "category": "essay",
        "code": "a1b2c3",
        "answer_visible": true,
        "remark": "Focus on vocabulary",
        "created_at": "2025-01-01T10:00:00Z",
        "updated_at": "2025-01-05T15:30:00Z",
        "submissions_count": 156,
        "creator": {
          "id": "user123",
          "nickname": "Teacher Wang",
          "email": "teacher@example.com"
        },
        "community": {
          "id": "comm456",
          "name": "IELTS Study Group",
          "code": "IELTS01"
        }
      }
    ],
    "pagination": {
      "current_page": 1,
      "total_pages": 8,
      "total_count": 150,
      "per_page": 20
    }
  }
}
```