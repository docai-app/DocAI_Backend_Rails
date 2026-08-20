# Assignment 學年篩選 Backend 交接文件

## 1. 功能目的

老師的 Assignment Dashboard 現在可以切換不同學年，例如：

- `2025-2026`
- `2026-2027（Current）`
- `All years`

切換學年後，系統只載入該學年建立的 assignments，不再一次載入所有歷史資料。這樣可以減少舊資料對列表速度的影響，也讓老師更容易管理每個學年的作業。

## 2. 本次 Backend 修改範圍

Assignment 列表 API 現在支援以下 query parameter：

```http
GET /api/v1/essay_assignments?school_academic_year_id=ACADEMIC_YEAR_UUID
```

Backend 收到 `school_academic_year_id` 後會：

1. 確認該學年屬於目前老師可使用的學年。
2. 讀取學年的 `start_date` 和 `end_date`。
3. 使用 assignment 的 `created_at` 判斷所屬學年。
4. 在 pagination 前完成日期篩選。
5. 同時篩選老師自己建立及其他老師分享的 assignments。
6. 讓列表資料和 `meta.total_count` 使用相同的篩選條件。

本次沒有在 `essay_assignments` table 新增 `academic_year_id`，因此不需要 database migration。

查看全部學年時使用明確保留值：

```http
GET /api/v1/essay_assignments?school_academic_year_id=all
```

Backend 收到 `all` 後不套用日期範圍，但 owned/shared 權限、搜尋、category 及 pagination 全部維持不變。

## 3. 預設行為

如果前端沒有傳入 `school_academic_year_id`：

```http
GET /api/v1/essay_assignments
```

Backend 會從老師的 `teacher_assignments` 中找出 status 為 `active` 的 academic year，並自動使用該學年的日期範圍。

如果老師被分配到多個 active academic years，系統會選擇 `start_date` 最新的一個。

## 4. Assignment 所屬學年的判定規則

Assignment 按照 `created_at` 判斷所屬學年：

```text
academic_year.start_date <= assignment.created_at <= academic_year.end_date
```

例如：

```text
學年：2025-2026
開始日期：2025-08-01
結束日期：2026-07-31
```

在以上日期範圍內建立的 assignment 都會顯示在 `2025-2026`。

注意事項：

- 修改 assignment 不會改變它所屬的學年，因為使用的是 `created_at`，不是 `updated_at`。
- Shared assignment 按照 assignment 原本的建立日期分類，不是按照分享日期分類。
- 學年日期包含開始日及結束日的完整一天。

## 5. Timezone 處理

日期邊界會優先使用學校的 `timezone`。

例如學校 timezone 是：

```text
Asia/Hong_Kong
```

則日期範圍會按照香港時間計算：

```text
start_date 00:00:00 至 end_date 23:59:59.999999
```

如果舊學校資料沒有設定 timezone，系統會安全 fallback 到 Rails application timezone；如果 application timezone 也不可用，則使用 UTC。

## 6. Owned 和 Shared Assignment

以下兩種 assignment 都會套用相同的學年篩選：

- 老師自己建立的 assignment
- 其他老師分享給目前老師的 assignment

篩選會在 pagination 前執行，因此：

- `essay_assignments` 只包含所選學年的資料。
- `meta.total_count` 只計算所選學年的資料。
- `meta.total_pages` 只按照所選學年的資料計算。
- 搜尋及 assignment category 篩選仍然可以正常配合使用。

## 7. 權限及錯誤回應

### 7.1 選擇未獲分配的學年

老師只能選擇自己在 `teacher_assignments` 中獲分配的 academic year。

如果傳入其他學校或未獲分配的 academic year ID，Backend 回傳：

```http
HTTP/1.1 403 Forbidden
```

```json
{
  "success": false,
  "error": "The selected academic year is not available for this account."
}
```

### 7.2 沒有 active academic year

如果 request 沒有提供 `school_academic_year_id`，而老師沒有任何 active academic year，Backend 回傳：

```http
HTTP/1.1 422 Unprocessable Entity
```

```json
{
  "success": false,
  "error": "No current academic year is available for this account."
}
```

## 8. 前端對接方式

前端切換學年時，需要重新請求 Assignment 列表：

```http
GET /api/v1/essay_assignments?school_academic_year_id=58207d18-1632-41d8-b523-d3a673cb4b04
```

以下現有參數仍可同時使用：

```http
GET /api/v1/essay_assignments?school_academic_year_id=ACADEMIC_YEAR_UUID&category=essay&page=1&count=10&search=keyword
```

前端送給 Backend 的參數名稱必須是：

```text
school_academic_year_id
```

前端頁面 URL 中使用的 `academic_year` 只是前端路由狀態，不是 Backend API parameter。

## 9. 舊學年建立 Assignment 的限制

目前「只有 current academic year 可以建立新 assignment」主要由前端控制：

- Current academic year 顯示 Create New Assignment。
- Archived 或 upcoming academic year 不顯示建立入口。

本次 Backend 修改只負責 Assignment 列表的學年篩選，沒有新增 `academic_year_id` 到 assignment create payload，也沒有在 create endpoint 驗證前端當時選擇的學年。

如果未來需要 Backend 強制禁止在舊學年建立 assignment，建議另外設計 create API 規則，不能只依靠本次的 `created_at` 篩選。

## 10. 主要程式檔案

### Controller

```text
app/controllers/api/v1/essay_assignments_controller.rb
```

負責：

- 接收 `school_academic_year_id`
- 建立學年篩選條件
- 將日期範圍傳入 Assignment query
- 處理未授權學年及沒有 active 學年的錯誤

### Academic Year Filter Service

```text
app/services/essay_assignment_academic_year_filter.rb
```

負責：

- 找出老師可使用的 academic years
- 選擇指定學年或預設 active 學年
- 驗證老師的學年存取權限
- 按學校 timezone 建立 `created_at` 日期範圍

### Student Academic Year Filter Service

```text
app/services/student_academic_year_filter.rb
```

負責：

- 從學生歷年 enrollment 驗證可查看學年
- 已提交 grading 優先使用 `submission_academic_year_id`
- 舊 grading 沒有 snapshot 時按 `created_at` fallback
- 未提交 assignment 按分配時間分類
- 支援 Grading 的 `all` 保留值

### 學生與老師 Grading

```http
GET /api/v1/essay_gradings.json?school_academic_year_id=ACADEMIC_YEAR_UUID
GET /api/v1/essay_gradings.json?school_academic_year_id=all
```

- 學生按 enrollment 驗證學年。
- 老師按 teaching assignment 驗證學年。
- 學生 Grading 單一學年使用 submission snapshot／日期 fallback。
- 老師 Grading 單一學年使用 grading `created_at`。
- `all` 只取消日期條件，不會繞過目前登入帳號的 grading scope。
- Join 頁面的 My Assignments 不提供切換，只請求學生 active 學年的待完成作業。

### Assignment Index Query

```text
app/queries/essay_assignment_index_query.rb
```

負責：

- Owned assignment 日期篩選
- Shared assignment 日期篩選
- Owned 和 shared count 日期篩選
- 在 pagination 前套用篩選

## 11. 測試範圍

已驗證以下情境：

- 沒有傳學年時，預設使用 active academic year。
- 可以讀取老師獲分配的 archived academic year。
- 拒絕老師未獲分配的 academic year。
- 沒有 active academic year 時返回明確錯誤。
- 使用學校 timezone 計算開始日及結束日。
- 學校 timezone 空白時正常 fallback。
- Owned assignments 正確按學年篩選。
- Shared assignments 正確按學年篩選。
- 在 pagination 前完成篩選。
- `total_count` 和 `total_pages` 正確。
- 指定 `general_user_id` 的列表路徑同樣套用學年篩選。

新增的 service tests 已涵蓋老師及學生 `all` 行為。完整 Rails test 在本機因缺少 `DEV_DB_HOST` 無法連接測試資料庫；部署前需由工程師在具備測試資料庫設定的環境補跑。

## 12. 部署前檢查

請 Backend 工程師確認：

- [ ] 每所學校的 academic year `start_date` 正確。
- [ ] 每所學校的 academic year `end_date` 正確。
- [ ] 當前學年的 status 是 `active`。
- [ ] 舊學年的 status 是 `archived`。
- [ ] 老師有正確的 `teacher_assignments` 記錄。
- [ ] 學校 timezone 已正確設定；未設定也應確認 fallback 符合預期。
- [ ] 前端 request 傳入 `school_academic_year_id`。
- [ ] 切換不同學年後，API 回傳的 assignment IDs 不相同。
- [ ] Owned 和 shared assignments 都能在正確學年顯示。
- [ ] `meta.total_count` 與畫面實際資料數量一致。
- [ ] Assignment、學生 Grading、老師 Grading 的 `school_academic_year_id=all` 均正常。
- [ ] Join 頁只載入 active 學年待完成作業。

## 13. 建議驗收步驟

1. 在 School Management 建立兩個不重疊的 academic years。
2. 將目前學年設為 `active`，舊學年設為 `archived`。
3. 確認測試老師在兩個學年都有 `teacher_assignments`。
4. 準備分別建立於兩個日期範圍內的 assignments。
5. 請求當前學年的 Assignment API，確認只回傳當前學年資料。
6. 傳入舊學年的 `school_academic_year_id`，確認只回傳舊學年資料。
7. 確認 shared assignments 也按照建立日期出現在正確學年。
8. 使用不屬於該老師的 academic year ID，確認返回 `403`。
9. 檢查 pagination、搜尋及 category filter。

## 14. GitHub 資訊

Repository：

```text
docai-app/DocAI_Backend_Rails
```

Branch：

```text
bobby-codex-backend
```

Commit 以 `bobby-codex-backend` 本次學年功能 push 的最新 commit 為準。
