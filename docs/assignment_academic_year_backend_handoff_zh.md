# Assignment 學年關聯與列表篩選 Backend 實作文件

## 1. 目的與最終行為

本功能解決 Assignment Dashboard 出現以下錯誤的根本原因：

- `All School Years` 可以看到 assignment，但 `Current` 看不到。
- Assignment 建立日期落在另一個學年日期範圍時，被錯誤歸類。
- Dashboard 為了前端過濾而一次載入全部歷史資料，影響載入速度。

最終設計不再以 `essay_assignments.created_at` 決定新 assignment 的學年。每個新 assignment 建立時必須保存明確的：

```text
essay_assignments.school_academic_year_id
    -> school_academic_years.id
```

列表預設只查詢目前 active 學年；只有使用者選擇其他學年或 `All School Years` 時，才查詢相應資料。

## 2. 修改範圍

主要 Backend 檔案：

```text
app/controllers/api/v1/essay_assignments_controller.rb
app/models/essay_assignment.rb
app/models/school_academic_year.rb
app/queries/essay_assignment_index_query.rb
app/services/essay_assignment_academic_year_filter.rb
app/services/student_academic_year_filter.rb
db/migrate/20260827150000_add_school_academic_year_to_essay_assignments.rb
test/controllers/api/v1/essay_assignments_controller_test.rb
test/queries/essay_assignment_index_query_test.rb
test/services/essay_assignment_academic_year_filter_test.rb
test/services/student_academic_year_filter_test.rb
test/services/student_academic_year_filter_integration_test.rb
```

Frontend 配合傳入學年 ID，但資料權限、預設學年及最終查詢條件全部由 Backend 決定，不能信任前端自行過濾。

## 3. Database Schema

Migration 新增 nullable UUID 欄位：

```ruby
add_column :essay_assignments, :school_academic_year_id, :uuid
```

並加入：

- `index_essay_assignments_on_school_academic_year_id`
- `essay_assignments.school_academic_year_id -> school_academic_years.id` foreign key

索引使用 PostgreSQL concurrent index；migration 使用：

```ruby
disable_ddl_transaction!
```

欄位暫時允許 null 是為了兼容無法唯一判斷學年的歷史資料。所有經正式 create endpoint 建立的新 assignment 都會寫入學年 ID。

Model 關聯：

```ruby
class EssayAssignment < ApplicationRecord
  belongs_to :school_academic_year, optional: true
end

class SchoolAcademicYear < ApplicationRecord
  has_many :essay_assignments, dependent: :restrict_with_error
end
```

`optional: true` 只為兼容 legacy null rows，不代表新 assignment 可以沒有學年。

## 4. Legacy Data Backfill

Migration 加欄位及 foreign key 後會執行舊資料回填。

### 4.1 回填資料來源

每筆舊 assignment 使用以下資料判斷：

- `essay_assignments.general_user_id`
- 該老師的 `teacher_assignments`
- `school_academic_years.start_date`
- `school_academic_years.end_date`
- `school_academic_years.status`
- `schools.timezone`
- `essay_assignments.created_at`

### 4.2 判定步驟

1. 取得 assignment owner 可使用的 academic years。
2. 把 assignment 的 `created_at` 轉換到每個 academic year 所屬學校時區。
3. 比較轉換後的本地日期是否落在 `start_date..end_date`。
4. 只有一個符合結果時直接回填。
5. 多個符合結果但只有一個為 active 時，使用該 active year。
6. 仍然無法唯一判斷時保持 null，不任意塞入目前學年。

Migration 完成時會輸出：

```text
Backfilled X essay assignments; Y require legacy date fallback
```

### 4.3 為何仍保留 legacy fallback

歷史老師可能同時屬於多間學校，或舊資料不足以唯一判斷。強行填入錯誤學年會造成不可見或權限錯誤，因此 unresolved rows 保持 null。

列表只對 `school_academic_year_id IS NULL` 的舊資料使用日期 fallback；已填入 ID 的資料永遠以 ID 為準，不會被 `created_at` 覆蓋。

## 5. 建立 Assignment API

Endpoint：

```http
POST /api/v1/essay_assignments.json
```

Frontend payload：

```text
essay_assignment[school_academic_year_id]=ACADEMIC_YEAR_UUID
```

### 5.1 指定學年

Backend 使用 `EssayAssignmentAcademicYearFilter` 從目前老師的 `teacher_assignments` 中查找指定學年。只有老師可使用的 academic year 才能保存。

成功建立後：

```ruby
essay_assignment.school_academic_year_id == requested_academic_year_id
```

Backend 不使用 client 提供的 `created_at`，也不以伺服器時間推算新 assignment 所屬學年。

### 5.2 舊 client 沒有傳入學年

為兼容尚未更新的 client，Backend 會使用老師的 active academic year。若有多個 active years，使用 `start_date` 最新的一個。

### 5.3 錯誤回應

指定老師無權使用的 academic year：

```http
403 Forbidden
```

```json
{
  "success": false,
  "error": "The selected academic year is not available for this account."
}
```

沒有傳入學年且老師沒有 active academic year：

```http
422 Unprocessable Entity
```

建立時傳入保留值 `all`：

```http
403 Forbidden
```

`all` 只適用於列表，不是可保存的 academic year ID。

### 5.4 Archived year 的目前政策

正常 Frontend 只允許在 active year 顯示 Create New，手動進入 archived year 的 create route 亦會返回 Dashboard。

Backend 目前允許老師透過 API 指定其有權使用的 archived year。這是既有授權策略，亦方便資料修復及 regression test。若產品政策要求 API 層完全禁止在 archived year 建立，需要另外增加 `academic_year.active?` 驗證；不能只依賴 Frontend。

## 6. Assignment 列表 API

Endpoint：

```http
GET /api/v1/essay_assignments.json
```

### 6.1 查詢指定學年

```http
GET /api/v1/essay_assignments.json?school_academic_year_id=ACADEMIC_YEAR_UUID
```

主要 SQL 邏輯：

```text
school_academic_year_id = selected_year_id
OR (
  school_academic_year_id IS NULL
  AND created_at BETWEEN selected_year_start AND selected_year_end
)
```

第一段是正常路徑，使用已建立的 academic year index。第二段只兼容 migration 無法唯一回填的舊資料。

### 6.2 預設目前學年

沒有傳 `school_academic_year_id` 時，Backend 解析老師的 active academic year，並套用與指定 UUID 相同的 database filter。它不會預設載入所有年份。

### 6.3 查看全部學年

```http
GET /api/v1/essay_assignments.json?school_academic_year_id=all
```

`all` 會取消學年條件，但仍保留：

- owner/shared access control
- category filter
- search
- sorting
- pagination

### 6.4 查詢順序

正確順序如下：

1. 建立 owned 及 shared scopes。
2. 套用 academic year database filter。
3. 套用 shared assignment category permission。
4. 套用 category 及 search。
5. 合併 owned/shared scopes。
6. 排序。
7. pagination。

`meta.total_count`、`total_pages` 及實際資料使用相同學年條件，避免數量與列表不一致。

## 7. Shared Assignments

Shared assignment 使用 assignment 本身保存的 `school_academic_year_id`，不是分享日期，也不是接收老師目前所在學年。

例如 assignment 保存為 `2025-2026`，即使在 `2026-2027` 才分享給另一位老師，它仍只會出現在 `2025-2026` 或 `All School Years`。

Owner 及 shared scopes 都在 union/pagination 前完成學年篩選。

## 8. 學生端待完成作業

Endpoint：

```http
GET /api/v1/essay_assignments/my_assignments
```

網頁版與微信小程序共用此 endpoint。兩邊沒有主動選擇學年時，Backend 使用學生 enrollment 的 active academic year。

### 8.1 尚未提交

尚未提交的 assignment 使用 distribution 的明確學年：

```text
assignment_student_assignments.assignment_distribution_id
    -> assignment_distributions.school_academic_year_id
```

不再使用 `assignment_student_assignments.created_at` 判斷，所以即使派發記錄建立日期與學年日期不一致，仍會出現在正確學年。

### 8.2 已提交

已提交資料使用：

```text
essay_gradings.submission_academic_year_id
```

legacy grading 沒有 submission snapshot 時，才使用 grading `created_at` 日期 fallback。

因此學生 assignment 的分類規則為：

- Pending／Overdue：distribution academic year。
- Submitted／Completed：submission academic year snapshot。
- Legacy submitted row：submission time fallback。

## 9. Frontend 對接

Dashboard URL 使用：

```text
academic_year=UUID
```

呼叫 Backend 時轉為：

```text
school_academic_year_id=UUID
```

Frontend 已遵守以下效能規則：

- Profile 及 academic years 尚未準備完成時不發 assignment request。
- 預設只請求 active year。
- 切換學年才請求另一個 year。
- `All School Years` 才傳 `all`。
- 切換 category、year 或 search 時重置 pagination。
- 不在 focus/reconnect 時無條件重取全部列表。

建立頁會把選定 active year 的 UUID 放入 create payload。從 `All School Years` 建立時使用 active year，不會傳 `all`。

Duplicate assignment 不複製舊 assignment 的 `school_academic_year_id`，讓 Backend 將副本保存至目前 active year。

## 10. 權限與安全

- Academic year UUID 必須來自目前老師的 `teacher_assignments`。
- Student academic year 必須來自目前學生的 `student_enrollments`。
- `all` 不會繞過 owned/shared 或 student scope。
- Frontend 顯示或隱藏按鈕不是安全邊界，Backend 仍會驗證 ID。
- Foreign key 防止保存不存在的 academic year。

## 11. 效能

新增索引：

```text
index_essay_assignments_on_school_academic_year_id
```

Assignment 列表在 SQL 層完成學年、category、search 及 pagination，不會載入全部年份後由 Ruby 或 Frontend 過濾。

Legacy fallback 僅作用於 `school_academic_year_id IS NULL` rows。部署後新資料都有明確 ID，fallback 掃描範圍不會隨新 assignment 增長。

學生 Pending Assignment 使用已存在的：

```text
assignment_distributions.school_academic_year_id
assignment_student_assignments.assignment_distribution_id
```

## 12. 測試覆蓋

Backend automated tests 覆蓋：

- 指定 academic year 建立並保存 UUID。
- 舊 client 沒有傳 UUID 時使用 active year。
- 拒絕未授權 academic year。
- 拒絕把 `all` 當作建立目標。
- 即使 assignment 今天建立但指定為舊學年，Current 不顯示、舊學年顯示、All 顯示。
- Owned 及 shared assignments 都按明確 ID 篩選。
- Explicit ID 不會被 `created_at` 覆蓋。
- Legacy null assignment 使用日期 fallback。
- Category、search、count 及 pagination 在學年篩選後運作。
- 學生 Pending Assignment 按 distribution year，而不是派發記錄建立時間。
- 學生 submitted grading 按 submission snapshot。
- School timezone 邊界及無 timezone fallback。

建議驗證命令：

```bash
bundle exec rails test \
  test/services/essay_assignment_academic_year_filter_test.rb \
  test/services/student_academic_year_filter_test.rb \
  test/services/student_academic_year_filter_integration_test.rb \
  test/queries/essay_assignment_index_query_test.rb \
  test/controllers/api/v1/essay_assignments_controller_test.rb

bundle exec rubocop --only Lint \
  app/controllers/api/v1/essay_assignments_controller.rb \
  app/models/essay_assignment.rb \
  app/models/school_academic_year.rb \
  app/queries/essay_assignment_index_query.rb \
  app/services/student_academic_year_filter.rb \
  db/migrate/20260827150000_add_school_academic_year_to_essay_assignments.rb
```

## 13. 部署順序

建議順序：

1. 備份 production database。
2. 部署 Backend code。
3. 執行 migration：

   ```bash
   bundle exec rails db:migrate
   ```

4. 記錄 migration 輸出的 backfilled/unresolved 數量。
5. 部署 Frontend code。
6. 清除或更新應用程式 cache。
7. 執行下方 smoke tests。

Migration 必須先於新版 Frontend 完成。Backend 已兼容沒有傳學年 ID 的舊 Frontend，因此可以先部署 Backend。

## 14. 部署後資料檢查

統計已回填及 unresolved rows：

```sql
SELECT
  COUNT(*) FILTER (WHERE school_academic_year_id IS NOT NULL) AS assigned_year,
  COUNT(*) FILTER (WHERE school_academic_year_id IS NULL) AS unresolved_legacy
FROM essay_assignments;
```

按學年統計：

```sql
SELECT school_academic_year_id, COUNT(*)
FROM essay_assignments
GROUP BY school_academic_year_id
ORDER BY COUNT(*) DESC;
```

檢查 dangling reference 理論上應為 0，foreign key 亦會阻止新資料產生：

```sql
SELECT COUNT(*)
FROM essay_assignments ea
LEFT JOIN school_academic_years say ON say.id = ea.school_academic_year_id
WHERE ea.school_academic_year_id IS NOT NULL
  AND say.id IS NULL;
```

## 15. Smoke Test Checklist

- [ ] 老師登入後預設選中 active school year。
- [ ] Current 只請求一個 school academic year ID。
- [ ] Current 顯示剛建立的 assignment。
- [ ] 舊學年只在選擇後載入。
- [ ] `All School Years` 顯示所有可存取資料。
- [ ] 同一 assignment 不會同時錯誤出現在兩個學年。
- [ ] Shared assignment 顯示於 assignment 原本學年。
- [ ] Category、search、list/cards 及 pagination 正常。
- [ ] 無權限 academic year UUID 返回 403。
- [ ] 老師沒有 active year 且 request 無 UUID 時返回 422。
- [ ] 學生網頁 Pending Assignment 只顯示 active enrollment year。
- [ ] 微信小程序 Pending Assignment 與網頁結果一致。
- [ ] 學生歷史 grading 切換學年結果正確。

## 16. Rollback

若只需回退 application code，可先回退 Frontend，再回退 Backend。新增欄位仍可保留，不影響舊版程式。

若必須回退 migration：

```bash
bundle exec rails db:rollback STEP=1
```

Migration down 會移除 foreign key、index 及 `school_academic_year_id` 欄位。這會永久刪除已保存的 assignment 學年關聯，因此 production 執行前必須備份，通常不建議在資料已開始寫入後回退 schema。

## 17. GitHub

Repository：

```text
docai-app/DocAI_Backend_Rails
```

Branch：

```text
bobby-codex-backend
```
