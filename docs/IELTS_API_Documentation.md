# AI ENGLISH - IELTS 看圖作文功能 API 文檔

## 概述

本文檔描述了AI ENGLISH項目中新增的IELTS看圖作文功能的所有API端點，包括圖片上傳、Sample Essay生成和AI評分功能。

## 認證

所有API端點都需要JWT Bearer Token認證：

```bash
Authorization: Bearer YOUR_JWT_TOKEN
```

---

## 1. 創建IELTS看圖作文作業

### **POST** `/api/v1/essay_assignments`

創建一個新的IELTS看圖作文作業，支援圖片上傳功能。

#### CURL 示例

```bash
curl -X POST "https://your-api-domain.com/api/v1/essay_assignments" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: multipart/form-data" \
  -F "essay_assignment[topic]=Describe the changes in transportation modes from 1990 to 2020" \
  -F "essay_assignment[assignment]=The chart below shows the percentage of people using different types of transportation in a city from 1990 to 2020. Summarise the information by selecting and reporting the main features, and make comparisons where relevant." \
  -F "essay_assignment[title]=IELTS Task 1 - Transportation Chart Analysis" \
  -F "essay_assignment[category]=essay" \
  -F "essay_assignment[graph_image]=@/path/to/chart.jpg" \
  -F "essay_assignment[rubric][name]=IELTS Task 1" \
  -F "essay_assignment[rubric][app_key][grading]=your_ielts_grading_api_key" \
  -F "essay_assignment[rubric][app_key][general_context]=your_general_context_api_key" \
  -F "essay_assignment[rubric][app_key][sample_essay]=your_sample_essay_api_key"
```

#### 請求參數

| 參數 | 類型 | 必需 | 描述 |
|------|------|------|------|
| `essay_assignment[topic]` | String | 是 | 作業主題 |
| `essay_assignment[assignment]` | Text | 是 | 作業描述和要求 |
| `essay_assignment[title]` | String | 是 | 作業標題 |
| `essay_assignment[category]` | String | 是 | 作業類型，使用 "essay" |
| `essay_assignment[graph_image]` | File | 是 | 圖表文件（僅支援JPG格式，最大10MB） |
| `essay_assignment[rubric][name]` | String | 是 | 評分標準名稱 |
| `essay_assignment[rubric][app_key][grading]` | String | 是 | Dify評分工作流API Key |
| `essay_assignment[rubric][app_key][sample_essay]` | String | 否 | Sample Essay生成API Key |

#### 成功響應 (201 Created)

```json
{
  "success": true,
  "essay_assignment": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "code": "ASMT-001",
    "topic": "Describe the changes in transportation modes from 1990 to 2020",
    "assignment": "The chart below shows the percentage of people using different types of transportation...",
    "title": "IELTS Task 1 - Transportation Chart Analysis",
    "category": "essay",
    "rubric": {
      "name": "IELTS Task 1",
      "app_key": {
        "grading": "your_ielts_grading_api_key",
        "general_context": "your_general_context_api_key",
        "sample_essay": "your_sample_essay_api_key"
      }
    },
    "graph_image_url": "https://yourstorage.blob.core.windows.net/uploads/chart.jpg",
    "created_at": "2024-01-15T10:30:00.000Z",
    "updated_at": "2024-01-15T10:30:00.000Z"
  }
}
```

#### 錯誤響應 (422 Unprocessable Entity)

```json
{
  "success": false,
  "errors": {
    "graph_image": ["must be a JPG file", "file size must be less than 10MB"],
    "topic": ["can't be blank"]
  }
}
```

---

## 2. 生成Sample Essay

### **POST** `/api/v1/essay_assignments/:id/generate_sample_essay`

為指定的IELTS作業生成Sample Essay。

#### CURL 示例

```bash
curl -X POST "https://your-api-domain.com/api/v1/essay_assignments/550e8400-e29b-41d4-a716-446655440000/generate_sample_essay" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json"
```

#### 路徑參數

| 參數 | 類型 | 必需 | 描述 |
|------|------|------|------|
| `id` | UUID | 是 | EssayAssignment的ID |

#### 成功響應 (200 OK)

```json
{
  "success": true,
  "sample_essay": {
    "content": "The chart illustrates the changes in transportation preferences among city residents between 1990 and 2020. Overall, there was a significant shift from private cars to public transportation and cycling...",
    "word_count": 157,
    "generated_at": "2024-01-15T10:35:00.000Z"
  },
  "message": "Sample essay generated successfully"
}
```

#### 錯誤響應

**403 Forbidden** - 沒有權限
```json
{
  "success": false,
  "error": "You are not authorized to generate sample essay for this assignment"
}
```

**404 Not Found** - 作業不存在
```json
{
  "success": false,
  "error": "EssayAssignment not found"
}
```

**422 Unprocessable Entity** - 缺少API Key
```json
{
  "success": false,
  "error": "Sample essay API key not configured for this assignment"
}
```

---

## 3. 查看作業詳情（含圖片和Sample Essay）

### **GET** `/api/v1/essay_assignments/:id/show_only`

獲取作業詳情，包括圖片URL和Sample Essay。

#### CURL 示例

```bash
curl -X GET "https://your-api-domain.com/api/v1/essay_assignments/550e8400-e29b-41d4-a716-446655440000/show_only" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json"
```

#### 成功響應 (200 OK)

```json
{
  "success": true,
  "essay_assignment": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "code": "ASMT-001",
    "topic": "Describe the changes in transportation modes from 1990 to 2020",
    "assignment": "The chart below shows the percentage of people using different types of transportation...",
    "title": "IELTS Task 1 - Transportation Chart Analysis",
    "category": "essay",
    "rubric": {
      "name": "IELTS Task 1",
      "app_key": {
        "grading": "your_ielts_grading_api_key",
        "general_context": "your_general_context_api_key",
        "sample_essay": "your_sample_essay_api_key"
      }
    },
    "graph_image_url": "https://yourstorage.blob.core.windows.net/uploads/chart.jpg",
    "sample_essay": {
      "content": "The chart illustrates the changes in transportation preferences...",
      "word_count": 157,
      "generated_at": "2024-01-15T10:35:00.000Z"
    },
    "created_at": "2024-01-15T10:30:00.000Z",
    "updated_at": "2024-01-15T10:35:00.000Z"
  }
}
```

---

## 4. 提交IELTS作文評分

### **POST** `/api/v1/essay_assignments/:essay_assignment_id/essay_gradings`

學生提交IELTS作文，系統會自動將圖片URL傳遞給AI進行評分。

#### CURL 示例

```bash
curl -X POST "https://your-api-domain.com/api/v1/essay_assignments/550e8400-e29b-41d4-a716-446655440000/essay_gradings" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "essay_grading": {
      "essay": "The chart displays significant changes in transportation usage patterns over a thirty-year period from 1990 to 2020. In 1990, private cars dominated with 60% usage, while public transport accounted for 25% and cycling only 15%. However, by 2020, the situation had changed dramatically. Public transportation increased to 40%, cycling rose to 30%, while private car usage decreased to 30%. This shift suggests growing environmental awareness and improved public transport infrastructure in the city."
    }
  }'
```

#### 請求參數

| 參數 | 類型 | 必需 | 描述 |
|------|------|------|------|
| `essay_grading[essay]` | Text | 是 | 學生提交的作文內容 |

#### 成功響應 (201 Created)

```json
{
  "success": true,
  "essay_grading": {
    "id": "660e8400-e29b-41d4-a716-446655440000",
    "essay": "The chart displays significant changes in transportation usage patterns...",
    "status": "processing",
    "created_at": "2024-01-15T11:00:00.000Z",
    "message": "Essay submitted successfully. AI grading in progress..."
  }
}
```

#### 評分完成後的響應結構

當AI評分完成後，可以通過 `GET /api/v1/essay_gradings/:id` 查看完整結果：

```json
{
  "success": true,
  "essay_grading": {
    "id": "660e8400-e29b-41d4-a716-446655440000",
    "essay": "The chart displays significant changes...",
    "status": "completed",
    "grading": {
      "overall_score": 6.5,
      "task_achievement": {
        "score": 6.0,
        "feedback": "The response addresses the task requirements adequately, identifying key trends in the data..."
      },
      "coherence_cohesion": {
        "score": 7.0,
        "feedback": "The essay is well-organized with clear progression of ideas..."
      },
      "lexical_resource": {
        "score": 6.5,
        "feedback": "Good range of vocabulary with some precise word choices..."
      },
      "grammatical_range": {
        "score": 6.5,
        "feedback": "Variety of sentence structures with mostly accurate grammar..."
      },
      "data_accuracy": {
        "score": 7.0,
        "feedback": "Most data points are accurately reported with appropriate comparisons...",
        "graph_analysis": "AI successfully analyzed the provided chart image and verified data accuracy"
      }
    },
    "created_at": "2024-01-15T11:00:00.000Z",
    "updated_at": "2024-01-15T11:02:30.000Z"
  }
}
```

---

## 5. 錯誤狀態碼參考

| 狀態碼 | 描述 | 常見原因 |
|--------|------|----------|
| 200 | 成功 | 請求成功處理 |
| 201 | 創建成功 | 資源成功創建 |
| 400 | 請求錯誤 | 請求格式錯誤或參數無效 |
| 401 | 未認證 | JWT Token缺失或無效 |
| 403 | 禁止訪問 | 沒有執行操作的權限 |
| 404 | 資源不存在 | 請求的資源不存在 |
| 422 | 無法處理 | 驗證失敗或業務邏輯錯誤 |
| 500 | 服務器錯誤 | 內部服務器錯誤 |

---

## 6. 技術實現細節

### 圖片處理
- **支援格式**: 僅JPG格式
- **檔案大小限制**: 最大10MB
- **儲存**: 使用Azure Storage
- **URL生成**: 自動生成可訪問的HTTP(S) URL

### AI評分整合
- 系統自動將圖片URL添加到Dify API調用的 `graph_image_url` 參數中
- AI可以分析圖片內容並驗證學生作文中的數據準確性
- 支援傳統文字作文和看圖作文的混合評分

### Sample Essay生成
- 使用獨立的Dify工作流生成Sample Essay
- 包含圖片URL以確保AI能夠基於具體圖表生成相關內容
- 生成的內容自動保存到作業的 `meta.sample_essay` 欄位

---

## 7. 前端整合建議

### 檔案上傳
```javascript
const formData = new FormData();
formData.append('essay_assignment[graph_image]', fileInput.files[0]);
// ... 添加其他參數
```

### 圖片預覽
```javascript
// 使用返回的 graph_image_url 顯示圖片預覽
<img src={assignment.graph_image_url} alt="Chart Preview" />
```

### Sample Essay顯示
```javascript
// 檢查是否有Sample Essay
if (assignment.sample_essay) {
  displaySampleEssay(assignment.sample_essay.content);
}
``` 