# Essay／Comprehension Release Scores — Backend 實作與交接文件

更新日期：2026-08-27

## 1. 目前狀態

- Repository：`docai-backend-rails_fresh_2026-04-02`
- 工作分支：`bobby-codex-backend`
- 整合基線：`5f27c6a merge`
- Release Score 修改已納入 `bobby-codex-backend` 整合提交並推送至 GitHub；尚未確認 production 部署。
- 2026-08-27 已執行 `fetch --all --prune` 及 fast-forward；
  `origin/bobby-codex-backend`、`origin/development`、`origin/production` 均為
  `5f27c6a`，而本地工作分支與 origin 為 `0 ahead / 0 behind`。
- `5f27c6a` 已包含 `e979ebc feat: persist assignment academic years` 及此前學生／老師
  學年 filter 修正；本次後續整合提交在此基線上加入本文件描述的 Release Score 修改。
- `origin/main` 為 `dacfe74`，與自己的本地 tracking branch 一致，但並未包含上述學年 commits。
- `https://docai.m2mda.com` 及 `https://docai-dev.m2mda.com` 的 release endpoint 當時均回覆 routing `404`。

Frontend 文件：

```text
essay-checker repository:
docs/essay-comprehension-score-release-frontend-handoff-zh.md
```

## 2. 目的與範圍

老師可先隱藏 Essay／Comprehension 分數，人工檢查後再一次發布給學生。

支援：

- Essay：發布 overall score 及 scoring criteria。
- Comprehension：發布 score 及 correct answers。
- Owner 及有權限的 active shared teacher。
- 明確的 capability 及 release state response。
- Idempotent、concurrency-safe 的 release 操作。
- 記錄首次發布時間及操作者。

不支援：

- Speaking Essay、Speaking Conversation、Pronunciation、Sentence Builder、Sentence Puzzle 等其他類型。
- Unrelease／重新隱藏。
- 完整 audit history。
- 逐一 submission 發布。

## 3. API

### Request

```http
PATCH /api/v1/essay_assignments/:id/release_scores.json
Authorization: Bearer <general-user-jwt>
Accept: application/json
```

Request body 不需要 payload。

### 成功回應

```http
200 OK
```

```json
{
  "success": true,
  "message": "Scores released to students.",
  "essay_assignment": {},
  "score_release": {
    "supported": true,
    "released": true,
    "released_at": "2026-08-27T14:30:00Z"
  }
}
```

### 錯誤回應

| 狀況 | HTTP | 行為 |
| --- | --- | --- |
| 未登入／token 無效 | 401 | Devise authentication 阻止 request |
| 沒有 assignment access 或 release 權限 | 403 | `{ success: false, error: "Forbidden" }` |
| Assignment 類型不支援 | 422 | 回覆只支援 Essay／Comprehension |
| Model validation 失敗 | 422 | 回傳 validation errors |
| 路由未部署 | 404 | Rails `No route matches`；代表 backend 版本過舊 |

## 4. Assignment detail response

既有 show endpoint 額外在 `essay_assignment` 內回傳：

```json
{
  "can_release_scores": true,
  "score_release": {
    "supported": true,
    "released": false,
    "released_at": null
  }
}
```

欄位語義：

- `can_release_scores`：目前登入使用者是否能執行 release。
- `supported`：assignment category 是否支援此功能。
- `released`：學生目前是否能看到相應分數內容。
- `released_at`：首次成功發布時間；舊資料可能為 `null`。

Frontend 可使用 capability 控制按鈕，但不能把它視為安全邊界。PATCH endpoint 仍會重新授權。

## 5. Category 資料行為

### Essay

Essay 沿用既有 JSON metadata：

```json
{
  "score_visible": true,
  "score_released_at": "2026-08-27T14:30:00Z",
  "score_released_by_id": "general-user-uuid"
}
```

發布時只 merge 上述 release metadata，不覆蓋 `meta` 內其他設定。

狀態判斷：

```ruby
ActiveModel::Type::Boolean.new.cast(meta['score_visible']) == true
```

因此可兼容 boolean 與歷史字串值。

### Comprehension

Comprehension 沿用既有欄位：

```text
essay_assignments.answer_visible = true
```

同時在 `meta` merge：

```json
{
  "score_released_at": "2026-08-27T14:30:00Z",
  "score_released_by_id": "general-user-uuid"
}
```

發布狀態直接使用 `answer_visible?`。

### 行為矩陣

| Category | Released 判斷 | Release 寫入 | 學生端依據 |
| --- | --- | --- | --- |
| Essay | `meta.score_visible` | `meta.score_visible = true` | 原有 Essay score visibility |
| Comprehension | `answer_visible` | `answer_visible = true` | 原有 Comprehension answer／score visibility |
| 其他 | 永遠 false | 拒絕，422 | 無變更 |

## 6. Release metadata 與 audit

第一次成功 release 時保存：

```text
meta.score_released_at
meta.score_released_by_id
```

- `score_released_at` 使用 `Time.current.iso8601`。
- `score_released_by_id` 記錄實際操作的 owner 或 shared teacher。
- Metadata 只提供首次發布 reference，不是完整 audit trail。
- 如果日後需要 unrelease、再次 release 或完整變更紀錄，應建立獨立 audit table，不能只覆蓋現有 metadata。

本功能沒有 database migration。

## 7. 權限模型

Controller 使用：

```ruby
before_action :authenticate_general_user!
before_action :set_essay_assignment_with_access
before_action :authorize_essay_assignment_score_release!
```

Model capability：

```ruby
EssayAssignment#can_release_scores?(user)
```

規則：

1. Assignment owner 可以 release。
2. Active shared teacher 必須仍然：
   - 被分享該 assignment；以及
   - 擁有該 assignment category 的有效功能權限。
3. 分享被撤銷、未分享或失去 category 權限時不可 release。
4. 無權限 request 回覆 `403 Forbidden`。

`can_release_scores` 同時供 detail response 使用，確保 UI capability 與 endpoint authorization 採用同一個 model method。

## 8. Idempotency 與 concurrency

`EssayAssignment#release_scores!` 使用 `with_lock`：

```ruby
with_lock do
  return self if scores_released?
  # atomic update
end
```

效果：

- 同一 request 重試不會更新原本 release timestamp。
- 使用者連續點擊不會重複改寫操作者。
- 兩個老師同時 release 時，第一個成功操作保留首次時間及操作者；後續 request 仍返回成功狀態。
- Essay 的 visibility 與 metadata 在同一次 update 寫入。
- Comprehension 的 `answer_visible` 與 metadata 在同一次 update 寫入。

## 9. 學生端相容性

本功能刻意重用現有學生端 visibility 欄位：

- Essay result 已依 `meta.score_visible` 控制 score tab、overall score 及 criteria。
- Comprehension result 已依 `answer_visible` 控制 score 及 correct answers。

因此 release endpoint 不需要逐筆修改 submissions，也不需要改學生 result schema。

部署前仍必須以學生帳戶做 regression test，確認：

1. Hidden assignment 的舊及新 submissions 都看不到分數。
2. Release 後舊及新 submissions 都能看到分數。
3. 不同 assignment 不會互相影響。

## 10. 主要修改檔案

```text
app/controllers/api/v1/essay_assignments_controller.rb
app/controllers/concerns/essay_assignment_access_authorization.rb
app/models/concerns/essay_assignment_access.rb
app/models/essay_assignment.rb
config/routes.rb
test/controllers/api/v1/essay_assignments_controller_test.rb
```

責任：

- `essay_assignments_controller.rb`：show response、release action、response serializer。
- `essay_assignment_access_authorization.rb`：endpoint authorization guard。
- `essay_assignment_access.rb`：owner／shared teacher capability。
- `essay_assignment.rb`：category support、released state、atomic release。
- `routes.rb`：PATCH member route。
- Controller test：建立設定、權限、category、idempotency 及 metadata regression tests。

注意：assignment academic-year 基線修正與 Release Score 後續修改已一同納入 Bobby branch。
完整整合狀態見：

```text
docs/2026-08-27-bobby-codex-backend-integration-status-zh.md
```

## 11. Regression tests

新增／涵蓋案例：

- 建立 Essay 並選擇 hidden，保存 `meta.score_visible = false`。
- 建立 Essay 並選擇 immediate，保存 `meta.score_visible = true`。
- Comprehension release 更新 `answer_visible`。
- Essay release 更新 `meta.score_visible` 且保留其他 metadata。
- Detail response 回傳 release state 及 capability。
- Owner 可以 release。
- Active shared teacher 可以 release，並記錄 shared teacher ID。
- Shared teacher 失去 category 權限後不可 release。
- 未分享老師不可 release。
- 不支援 category 回覆 422。
- 重複 release 不改寫首次 timestamp。

目標測試：

```bash
bundle exec rails test \
  test/controllers/api/v1/essay_assignments_controller_test.rb
```

Lint：

```bash
bundle exec rubocop --only Lint \
  app/controllers/api/v1/essay_assignments_controller.rb \
  app/controllers/concerns/essay_assignment_access_authorization.rb \
  app/models/concerns/essay_assignment_access.rb \
  app/models/essay_assignment.rb \
  config/routes.rb \
  test/controllers/api/v1/essay_assignments_controller_test.rb
```

基本檢查：

```bash
ruby -c app/models/essay_assignment.rb
ruby -c app/controllers/api/v1/essay_assignments_controller.rb
git diff --check
```

## 12. 手動 API 驗證

### Hidden detail

以有權限 teacher token 讀取 assignment detail，確認：

```text
score_release.supported = true
score_release.released = false
can_release_scores = true
```

### Release

```bash
curl -X PATCH \
  -H "Authorization: Bearer <token>" \
  -H "Accept: application/json" \
  https://<api-host>/api/v1/essay_assignments/<id>/release_scores.json
```

確認 HTTP 200，再重新讀取 detail。

### Route deployment probe

沒有 token 時：

- `401` 通常代表路由已存在，但 authentication 阻止操作。
- Rails routing `404 No route matches` 代表部署版本尚未包含新 route。

此 probe 只能確認 route 是否存在，不能代替已登入的完整 release 測試。

## 13. 部署前檢查

Backend 工作分支目前與 `origin/development`、`origin/production` 是同一個 HEAD，沒有分叉。
部署前仍必須：

1. 再次 fetch 最新 `production`／`development`，避免部署前遠端再次前進。
2. 確認 target branch 仍以 `5f27c6a` 或其後代為基線。
3. Review Release Score 整合 diff，不能把本地環境值或測試資料帶入部署設定。
4. 若遠端再次前進，重新執行 merge／rebase conflict audit。
5. 執行完整目標 tests 及 lint。
6. 確認沒有意外包含本地測試環境設定、測試帳戶或 secret。
7. 由 reviewer 核對 shared teacher release 是否符合產品決定。

不要把本地 `.env`、JWT key、測試 database URL 或測試帳戶資料提交到 repository。

## 14. 部署順序與 smoke test

部署順序：

1. Backend。
2. 確認 route 不再 404。
3. 以 owner token 測試 hidden detail 及 release。
4. 以 shared teacher token 測試 capability 及 release。
5. 以無權限 teacher token 確認 403。
6. 以 student 帳戶確認 visibility。
7. Frontend。
8. 再做一次 end-to-end smoke test。

推薦觀察：

- `release_scores` request 數量、HTTP status 及 latency。
- 403 是否異常增加。
- 422 unsupported category 是否出現。
- Frontend error toast 是否對應 backend response。

## 15. 回退策略

Backend code 可以移除新 route、controller action 及 capability response，但資料回退需另外判斷：

- 已發布 Essay 已寫入 `meta.score_visible = true`。
- 已發布 Comprehension 已寫入 `answer_visible = true`。
- 單純回退 code 不會自動重新隱藏已發布分數。

不要用批量 SQL 自動把所有 visibility 改回 false，因為其中可能包含原本就設定立即顯示的 assignment。若需要資料回退，必須使用 `score_released_at`、assignment 清單及產品確認精確定位。

## 16. 已知限制與後續建議

- 沒有 unrelease。
- 沒有完整 audit history。
- 舊 assignment 若已 visible 但沒有 `score_released_at`，UI 會顯示 released，但沒有時間。
- Release 是 assignment-level，會同時影響目前及未來 submissions。
- 若日後要通知學生，應在 release transaction 成功後交給 background job，並確保通知本身可重試，不要把外部通知放進 database lock 內。
