# IELTS Task 1 Dify Workflow 實現文檔

## 📋 概述

本文檔描述了為 IELTS Task 1 作業類型實現特殊 Dify workflow 調用的技術解決方案。該實現以最少侵入性的方式擴展了現有的評分系統，同時保持向後兼容性。

## 🎯 問題背景

IELTS Task 1 作業需要傳遞三個特定參數給 Dify workflow：
- `graph`: 圖表圖片 URL
- `essay`: 學生提交的作文內容  
- `essay_topic`: 作文主題

而現有系統使用的是標準參數格式：
- `Essay`: 作文內容
- `essaytopic`: 作文主題
- `graph_image_url`: 圖片 URL

## 💡 解決方案設計

### 核心設計原則

1. **最小侵入性**: 僅修改必要的服務類，不改變數據庫結構
2. **向後兼容**: 現有的非 IELTS Task 1 作業繼續使用原有邏輯
3. **智能路由**: 根據 `rubric.name` 自動選擇參數格式
4. **統一處理**: 兩個相關服務類採用相同的檢測和處理邏輯

### 實現架構

```
EssayAssignment.rubric.name == 'IELTS Task 1'
           ↓
    智能路由邏輯
           ↓
    ├─ IELTS Task 1 → 特殊參數格式
    └─ 其他類型    → 標準參數格式
```

## 🔧 技術實現

### 1. EssayGradingService 修改

#### 新增方法

```ruby
# 判斷是否為 IELTS Task 1 作業
def is_ielts_task_1?
  @essay_grading.essay_assignment.rubric&.dig('name') == 'IELTS Task 1'
end

# 構建 IELTS Task 1 專用的 inputs 格式
def build_ielts_task_1_inputs
  {
    graph: get_ielts_graph_url,
    essay: @essay_grading.essay,
    essay_topic: @essay_grading.topic
  }
end

# 獲取 IELTS Task 1 圖片 URL
def get_ielts_graph_url
  if @essay_grading.essay_assignment.graph_image.attached?
    @essay_grading.essay_assignment.graph_image.url
  else
    Rails.logger.warn("[EssayGradingService] IELTS Task 1 assignment missing required graph image")
    nil
  end
end
```

#### 修改現有方法

```ruby
def grading_request_payload
  inputs = if @essay_grading.essay_assignment.category == 'sentence_builder'
             { sentence_builder: @essay_grading.sentence_builder_for_dify.to_json }
           elsif is_ielts_task_1?
             build_ielts_task_1_inputs  # 新增邏輯
           else
             { Essay: @essay_grading.essay, essaytopic: @essay_grading.topic }
           end

  # 向後兼容：僅非IELTS Task 1 需要舊格式圖片處理
  if !is_ielts_task_1? && @essay_grading.essay_assignment.graph_image.attached?
    inputs[:graph_image_url] = @essay_grading.essay_assignment.graph_image.url
  end

  { inputs:, response_mode: 'blocking', user: @user_id }.to_json
end
```

### 2. SampleEssayGenerationService 修改

採用相同的檢測邏輯和參數構建方式，確保一致性。

## 📊 參數對照表

| Workflow 類型 | graph 參數 | essay 參數 | topic 參數 | 圖片參數名 |
|--------------|------------|------------|------------|------------|
| IELTS Task 1 | `graph` | `essay` | `essay_topic` | `graph` |
| 標準作業 | - | `Essay` | `essaytopic` | `graph_image_url` |

## 🚀 使用示例

### IELTS Task 1 作業創建

```bash
curl -X POST "/api/v1/essay_assignments" \
  -F "essay_assignment[rubric][name]=IELTS Task 1" \
  -F "essay_assignment[rubric][app_key][grading]=your_ielts_key" \
  -F "essay_assignment[graph_image]=@chart.jpg" \
  -F "essay_assignment[topic]=Describe the transportation chart"
```

### 自動 Workflow 調用

當學生提交作文時，系統會自動：

1. 檢測 `rubric.name == 'IELTS Task 1'`
2. 使用特殊參數格式調用 Dify
3. 記錄詳細日誌便於調試

## 🔍 日誌監控

系統會記錄以下關鍵信息：

```
[EssayGradingService] Building IELTS Task 1 inputs for assignment 123
[EssayGradingService] Graph URL: https://storage.blob.core.windows.net/uploads/chart.jpg
[EssayGradingService] Essay length: 250
[EssayGradingService] Topic: Describe the transportation changes
```

## ✅ 向後兼容性保證

1. **現有作業**: 繼續使用原有的 `Essay`/`essaytopic` 參數格式
2. **圖片處理**: 非 IELTS Task 1 作業保持 `graph_image_url` 格式
3. **API 響應**: 前端無需任何修改
4. **數據庫**: 無需執行任何 migration

## 🧪 測試策略

創建了完整的測試套件 `test/services/ielts_task_1_workflow_test.rb`：

- ✅ IELTS Task 1 檢測邏輯
- ✅ 特殊參數格式構建
- ✅ 向後兼容性驗證
- ✅ 日誌記錄功能

## 🔧 部署步驟

1. **代碼部署**: 部署修改後的服務類
2. **配置檢查**: 確保 IELTS Task 1 的 API Key 配置正確
3. **功能測試**: 創建測試作業驗證 workflow 調用
4. **監控**: 檢查日誌確認參數傳遞正確

## 📈 性能影響

- **最小性能影響**: 僅新增輕量級條件判斷
- **無額外資料庫查詢**: 利用已加載的 assignment 數據
- **日誌可控**: 可根據需要調整日誌級別

## 🔒 安全考慮

- **API Key 隔離**: IELTS Task 1 使用獨立的 API Key
- **數據驗證**: 保持原有的參數驗證邏輯
- **錯誤處理**: 增強的錯誤日誌和異常處理

## 🎉 總結

此實現成功解決了 IELTS Task 1 的特殊 workflow 需求，同時：

- ✅ **零破壞性變更**: 現有功能完全不受影響
- ✅ **代碼可維護**: 清晰的邏輯分離和統一的處理方式
- ✅ **易於擴展**: 未來可輕松添加更多特殊類型的 workflow
- ✅ **生產就緒**: 完整的測試覆蓋和錯誤處理 