# Sentence Puzzle Draft 與 PDF Backend 部署交接

## 目的

本次 backend 更新支援 Sentence Puzzle 中途保存、重新載入、沿用同一筆 draft 正式提交，以及單份／批量 PDF 報告。

## API 變更

新增：

```http
GET /api/v1/essay_assignments/:assignment_code/essay_gradings/current_draft
```

用途是取得目前登入學生在指定 Sentence Puzzle assignment 的最新 draft。沒有 draft 時返回：

```json
{
  "success": true,
  "essay_grading": null
}
```

沿用現有 endpoint：

```http
POST /api/v1/essay_assignments/:assignment_code/essay_gradings.json
PUT /api/v1/essay_gradings/:grading_id.json
GET /api/v1/essay_gradings/:grading_id/download_report
GET /api/v1/essay_assignments/:assignment_id/download_reports
```

## 草稿規則

- `essay_grading.status = draft` 時，Sentence Puzzle concern 不可以改成 graded。
- `sentence_puzzle_attempt.status = draft` 時保存完整 answers 及 progress。
- 同一學生對同一 assignment 再次 POST draft 時，backend 會重用最新 draft。
- PUT draft 時更新同一筆 grading。
- 正式提交時把同一筆 draft 改成 graded。
- 正式提交時，backend 會按 assignment 內保存的 questions 與 block IDs 重新組句、判斷正誤及計算 score／total，不信任 frontend 傳入的分數或 `is_correct`。
- 無效、重複或不完整的 block ID 排列會按錯誤答案處理；嘗試次數會限制在 assignment 設定範圍內。
- Draft 不更新 AssignmentStudentAssignment 的完成狀態。
- Draft 不包含在老師 submission list 或批量 PDF。
- 新建 draft 會抵消 Rails counter cache 的自動加一；draft 轉為 graded 時才正式增加提交數。

## Progress 格式

```json
{
  "current_question_id": "question_3",
  "current_question_order": 3,
  "selected_block_order": ["block_2", "block_1"],
  "attempts_by_question": {
    "question_1": 1,
    "question_2": 2,
    "question_3": 1
  },
  "feedback": null,
  "started_at": "2026-08-24T09:50:00Z",
  "saved_at": "2026-08-24T10:00:00Z"
}
```

Strong params 已加入以上欄位。

## PDF 修正

原本 `generate_sentence_puzzle_pdf` 在 renderer 內先執行 `.render`，外層 action 再執行 `.render`，會造成返回類型錯誤。現在 renderer 返回 `Prawn::Document`，由下載 action 統一 render。

報告包括：

- 學校 Logo
- 學生及提交時班別資料
- Score、Full Score、Accuracy
- Questions、Submitted time
- Student sentence、Correct sentence
- Correct / Wrong
- Attempts used

已加入 Noto Sans TC 與 DejaVu Sans fallback。

首頁沿用 Essay、Comprehension、Sentence Builder 等報告共用的 `draw_unified_report_header`、資料格、Title box、頁尾、Arial／Noto Sans 字型及藍灰色 palette，不建立新的報告風格。正文沿用其他練習報告的題號、學生答案及綠色正確答案層級，只有 Result 使用綠／紅色區分狀態。

Sentence Puzzle 沒有 Full／Simplified 版本，因此首頁不顯示 Report Type，Overall Score 會橫跨整行。每題使用適合低年級閱讀的淺藍灰卡片，清楚分隔 Your sentence、Correct sentence、Result 及 Attempts；報告不顯示 Answer revealed。每題會保持完整，不會在頁尾被拆成兩部分，續頁也不加 continued 標題。

`Submitted time` 使用 draft 正式轉為 graded 時的 `updated_at`，不會錯誤顯示第一次保存草稿的時間。

## 修改檔案

- `app/controllers/api/v1/essay_gradings_controller.rb`
- `app/controllers/concerns/sentence_puzzle_submissions.rb`
- `config/routes.rb`
- `test/integration/sentence_puzzle_draft_and_report_test.rb`

## 測試

```bash
bundle exec rails test test/integration/sentence_puzzle_draft_and_report_test.rb
```

測試覆蓋：

- 第一次建立 draft
- 重複 POST 沿用 draft
- current_draft 恢復資料
- PUT 正式提交同一筆 grading
- 草稿消失、正式 grading 保留
- 單份 PDF 返回 `%PDF`
- 批量 ZIP 包含有效 PDF
- Backend 拒絕偽造 score、正確句子、`is_correct`、重複 block IDs 及超出上限的 attempts
- PDF 文字層不包含 Report Type、Answer revealed 或 continued，並支援 `&`、`<` 等特殊字元

已使用獨立 PostgreSQL 測試資料庫實際執行，結果：

```text
2 runs, 64 assertions, 0 failures, 0 errors, 0 skips
```

## 部署

1. 先部署 backend。
2. 執行 integration test。
3. 用測試學生保存 draft 並重新打開。
4. 確認 final submit 使用相同 grading ID。
5. 測試單份及批量 PDF。
6. 完成後才部署配套 frontend。

本功能不需要 migration。
