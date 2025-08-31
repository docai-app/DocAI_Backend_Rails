# Dify 文件上傳整合技術文檔

## 📋 問題背景

### 原始問題
在實現 IELTS Task 1 功能時，遇到了以下錯誤：
```
"code": "invalid_param", "message": "Essay is required in input form", "status": 400
```

### 根本原因分析
根據 Dify 官方文檔，當 workflow 涉及文件或圖片時，需要採用**兩步驟流程**：
1. **先上傳文件** 到 `/files/upload` 端點獲取 `upload_file_id`
2. **再調用 workflow** 使用 `upload_file_id` 而不是直接的 URL

我們之前的實現直接傳遞圖片 URL，不符合 Dify 的要求。

## 🎯 解決方案設計

### 核心架構

```
IELTS Task 1 作業提交
       ↓
檢測 rubric.name == 'IELTS Task 1'
       ↓
調用 DifyFileUploadService
       ↓
1. 下載圖片文件
2. 上傳到 Dify 獲取 upload_file_id
3. 構建正確的參數格式
       ↓
調用 Dify Workflow
```

### 新建服務類

#### `DifyFileUploadService`
專門處理 Dify 文件上傳的服務類：

**主要功能：**
- 從 URL 下載文件
- 上傳到 Dify API
- 返回 `upload_file_id`
- 錯誤處理和回退機制

**API 端點：**
- Upload: `https://aienglish-dify.docai.net/v1/files/upload`
- Method: `POST`
- Content-Type: `multipart/form-data`

## 🔧 技術實現

### 1. 新增的服務類

#### `app/services/dify_file_upload_service.rb`

```ruby
class DifyFileUploadService
  # 上傳文件從 URL
  def upload_from_url(file_url, file_type = 'image')
    # 1. 下載文件到臨時文件
    # 2. 上傳到 Dify
    # 3. 返回 upload_file_id
  end

  # 構建正確的 multipart 請求
  def upload_file_to_dify(file, file_type)
    payload = {
      file: file,
      user: @user_id,
      type: determine_dify_file_type(file_type)
    }
    # POST 到 /files/upload
  end
end
```

### 2. 修改的服務類

#### `app/services/essay_grading_service.rb`

**關鍵修改：**
```ruby
def build_ielts_task_1_inputs
  # 新邏輯：先上傳文件
  graph_input = build_ielts_graph_input
  
  inputs = {
    graph: graph_input,  # 使用文件數組格式
    Essay: @essay_grading.essay,
    essay_topic: @essay_grading.topic
  }
end

def build_ielts_graph_input
  # 使用 DifyFileUploadService 上傳
  upload_service = DifyFileUploadService.new(@grading_app_key, @user_id)
  upload_result = upload_service.upload_from_url(graph_url, 'image')
  
  if upload_result.success?
    # 返回 Dify 期望的格式
    [{
      transfer_method: 'local_file',
      upload_file_id: upload_result.upload_file_id,
      type: 'image'
    }]
  else
    # 回退到原有邏輯
    [{
      transfer_method: 'remote_url',
      url: graph_url,
      type: 'image'
    }]
  end
end
```

#### `app/services/sample_essay_generation_service.rb`

採用相同的邏輯，確保兩個服務的一致性。

## 📊 參數格式對比

### 修改前（錯誤的格式）
```json
{
  "inputs": {
    "graph": "https://storage.blob.core.windows.net/uploads/chart.jpg",
    "essay": "學生作文內容",
    "essay_topic": "作文主題"
  }
}
```

### 修改後（正確的格式）
```json
{
  "inputs": {
    "graph": [{
      "transfer_method": "local_file",
      "upload_file_id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "image"
    }],
    "Essay": "學生作文內容",
    "essay_topic": "作文主題"
  }
}
```

## 🚀 錯誤處理與回退機制

### 多層錯誤處理

1. **網絡錯誤**：下載或上傳失敗
2. **API 錯誤**：Dify API 返回錯誤
3. **解析錯誤**：響應格式不正確

### 回退策略

當上傳失敗時，自動回退到原有的 `remote_url` 格式：

```ruby
rescue StandardError => e
  Rails.logger.error("[DifyFileUploadService] Error: #{e.message}")
  # 回退到 remote_url 格式
  [{
    transfer_method: 'remote_url',
    url: graph_url,
    type: 'image'
  }]
end
```

## 🔍 日誌監控

### 關鍵日誌訊息

**成功案例：**
```
[DifyFileUploadService] Starting file upload from URL: https://...
[DifyFileUploadService] File uploaded successfully, upload_file_id: 550e8400-e29b-41d4-a716-446655440000
[EssayGradingService] Successfully uploaded graph to Dify, upload_file_id: 550e8400-e29b-41d4-a716-446655440000
```

**失敗回退案例：**
```
[DifyFileUploadService] API request failed: HTTP 400
[EssayGradingService] Failed to upload graph to Dify: Upload failed
[EssayGradingService] Falling back to direct URL for graph
```

## 📈 性能考量

### 上傳時間
- 圖片下載：~1-3秒
- Dify 上傳：~2-5秒
- 總增加時間：~3-8秒

### 優化策略
1. **並行處理**：可以考慮在創建作業時預先上傳
2. **緩存機制**：相同圖片可以重用 `upload_file_id`
3. **超時控制**：設置合理的超時時間

## 🔒 安全考量

### API Key 管理
- 文件上傳使用相同的 Dify API key
- 確保 API key 有文件上傳權限

### 文件安全
- 臨時文件自動清理
- 僅支持允許的文件類型
- 文件大小限制

## 📋 測試與驗證

### 測試腳本
- `scripts/simple_dify_test.rb`：功能測試
- `scripts/test_dify_file_upload.rb`：完整測試（需 Rails 環境）

### 驗證步驟
1. 創建 IELTS Task 1 作業（包含圖片）
2. 學生提交作文
3. 檢查日誌中的 `upload_file_id`
4. 確認不再出現 "Essay is required" 錯誤

## 🎯 向後兼容性

### 保持兼容
- 非 IELTS Task 1 作業繼續使用原有邏輯
- 錯誤時自動回退到原有格式
- 不影響現有功能

### 智能路由
```ruby
if is_ielts_task_1?
  build_ielts_task_1_inputs  # 新邏輯
else
  # 原有邏輯保持不變
  { Essay: @essay_grading.essay, essaytopic: @essay_grading.topic }
end
```

## 📝 未來改進方向

1. **批量上傳**：支持多個文件的批量上傳
2. **緩存優化**：實現 `upload_file_id` 的緩存機制
3. **監控告警**：添加上傳失敗的告警機制
4. **性能優化**：考慮異步上傳策略

---

## 📚 相關文檔

- [Dify Workflow API 官方文檔](https://docs.dify.ai/guides/workflow)
- [IELTS Task 1 實現文檔](./IELTS_Task_1_Workflow_Implementation.md)
- [API 文檔](./IELTS_API_Documentation.md) 