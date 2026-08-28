# Assignment 學年規則：Production Readiness Audit

更新日期：2026-08-27

2026-08-28 補充：學生 UUID `/read` 路由曾被 teacher management guard 誤擋，
此前測試未覆蓋此路由。原因、修復及新增的雙 request regression 見
[學生 Assignment Read 403 修復](2026-08-28-student-assignment-read-forbidden-fix-zh.md)。

## 1. 結論

本地 backend、web frontend 及微信小程序的學年規則已完成完整 regression audit。

本地確認結果：

- 空 PostgreSQL database 可從第一個 migration 跑至最新版本。
- 學年 migration、舊資料回填、老師列表、學生待辦、學生批改紀錄、派發、共享權限及分頁測試：
  `58 runs, 265 assertions, 0 failures, 0 errors`。
- Web frontend：TypeScript、targeted ESLint、production build 通過。
- 微信小程序：utility tests、release gates、production build 通過。
- 三個 repository 的目前 branch 均與自己的 upstream 為 `0 ahead / 0 behind`。
- 本次修正與文件已納入 `bobby-codex-backend` 整合提交並推送至 GitHub；尚未 deploy，也沒有寫入 production 資料。

不能只憑上述結果宣稱 production database 已完成 migration／回填。Production API 未登入可正常回覆
`401`，但 production DB schema、NULL 數量及實際帳戶 E2E 仍需使用 production DB read-only 權限
或已登入老師／學生帳戶驗證。

## 2. Source of truth

### 老師建立及查看 Assignment

- 新 assignment 保存明確的 `essay_assignments.school_academic_year_id`。
- 建立 request 沒有傳學年時，backend 使用老師可用的 active school year。
- 建立 request 傳指定學年時，backend 驗證該學年屬於老師帳戶。
- 建立 request 不可使用 `all` 作為 assignment 所屬學年。
- 列表直接按 `school_academic_year_id` 查詢。
- 只有 migration 無法唯一回填的舊 assignment 才使用 `created_at` date range fallback。

### 學生待完成 Assignment

- 未提交作業按 `assignment_distributions.school_academic_year_id` 分類。
- 建立 distribution 時繼承 assignment 已保存的學年；只有 legacy NULL assignment 才 fallback active year。
- 不再按 `assignment_student_assignments.created_at` 分類。
- 沒有傳學年 ID 時，backend 使用學生 enrollment 中的 active school year。

### 學生已提交／批改紀錄

- 優先按 `essay_gradings.submission_academic_year_id` 分類。
- 只有舊 grading 的 snapshot 為 NULL 時才使用 `created_at` fallback。

## 3. Database 與 migration 驗證

Migration：

```text
db/migrate/20260827150000_add_school_academic_year_to_essay_assignments.rb
```

在一次性空 database 執行所有 migrations：成功。

本地最新 schema 實際檢查：

| Table | Column | Nullable | Index | Foreign key |
| --- | --- | --- | --- | --- |
| `essay_assignments` | `school_academic_year_id` | YES | YES | YES |
| `assignment_distributions` | `school_academic_year_id` | NO | YES | YES |

`essay_assignments.school_academic_year_id` 暫時保留 nullable 是刻意設計：migration 對不能唯一判定的
legacy rows 不會猜測學年，而是保留 NULL 讓列表使用受控 fallback。新 assignment 經 create controller
必須寫入一個明確學年，已有 regression test 防止新資料變成 NULL。

回填測試覆蓋：

- 學年不是 9 月 1 日開始。
- 學年開始前一天／上一學年結束日。
- 學年開始當天。
- 學年結束當天。
- 學年結束後一天。
- `Asia/Macau` local date，不會因 UTC 儲存差一天。
- 歷史重疊 date ranges 中只有一個 active year 時，選擇 active year。
- 無法唯一判定時保留 NULL，不做危險猜測。

## 4. 老師端 regression

已自動驗證：

1. 建立 Current School Year assignment：Current 及 All 看得到，舊學年看不到。
2. 今天建立但明確指定舊學年：Current 看不到；指定舊學年及 All 看得到。
3. 建立時不傳學年：舊 client 會保存 active year。
4. 指定不屬於老師帳戶的學年：403。
5. 建立時指定 `all`：拒絕。
6. Category、search、academic year 在 SQL query 中先套用，再 pagination。
7. Owned 與 shared assignment 合併後不重複，total count／total pages 正確。

目前 web UI 只允許在 active year 建立 assignment；backend API 已支援明確指定老師可用的 archived year。
因此「今天建立並指定舊學年」目前是 backend regression 能力，不代表老師 UI 已提供 archived-year create 操作。

## 5. 學生端 regression

已自動驗證：

- Current／Past／All grading records 使用 `submission_academic_year_id`。
- legacy grading snapshot 為 NULL 時才使用日期 fallback。
- Current／Past／All pending assignments 使用 distribution year。
- 即使 `assignment_student_assignments.created_at` 是另一學年，仍以 distribution year 為準。
- 已提交 assignment 改按 submission snapshot 顯示。
- assignment code／feature 權限改變後，已明確派發的 assignment 仍可打開。
- 今天建立並指定舊學年的 assignment 經真實 distribution endpoint 派發後：Past／All 看得到，
  Current 看不到。
- Distribution options 只可讀取老師所屬學校的學年，其他學校的 year ID 回覆 not found。
- 學生待辦 pagination 在 database 執行，page size、total pages、total count 和回傳列表一致。

## 6. 權限與共享

已驗證：

- Owner 可查看、修改及刪除自己的 assignment。
- Active shared teacher 可查看被分享 assignment。
- Shared teacher 能否修改、派發或 release score，依 assignment category feature capability 判斷。
- 非 owner 不可刪除 owner assignment。
- 未分享老師不可存取 assignment detail 或 release score。
- 指定不屬於帳戶的 school academic year 會被拒絕。
- All School Years 仍然只合併 owned 及 active shared assignments，不會取消 user／school 限制。

本次 audit 發現 controller 的 owner/access guards 曾被註解，造成 shared teacher 可刪除 owner assignment。
已重新啟用 read／show／update／destroy 的對應 authorization，並由 integration test 驗證 destroy 回覆
`403 Forbidden`。

同時發現 assignment distribution 曾固定使用 `school.current_academic_year`，會令指定舊學年的新 assignment
錯誤出現在學生 Current。現已改為繼承 assignment year，並重新啟用 distribution 的 same-school access guard。

## 7. 效能

已確認：

- Teacher assignment query 直接在 SQL 使用 `school_academic_year_id`，不是載入所有年份再前端過濾。
- Legacy `created_at` 條件只套用 `school_academic_year_id IS NULL` rows。
- Academic year、category、search 會在 pagination 前套用。
- `essay_assignments.school_academic_year_id` 有 btree index。
- `assignment_distributions.school_academic_year_id` 有單欄 index，另有
  `(essay_assignment_id, school_academic_year_id)` composite index。
- Teacher assignment、student pending assignment、grading list 都使用 database pagination。
- Past assignment statistics 使用 assignment year 的 enrollment，並以 database pagination 回傳學生列表。

本次 audit 修正兩個會先 materialize relation 的位置：

```text
MyAssignmentsController: paginate_array(assignments.to_a) -> relation.page.per
EssayGradingsController: paginate_array(relation) -> relation.page.per
AssignmentStatisticsController: paginate_array(students_query.to_a) -> relation.page.per
```

## 8. Web frontend

已確認：

- Teacher assignment request 傳 `school_academic_year_id=<selected id|all>`。
- Student／teacher grading request 傳相同學年參數。
- 切換學年會 reset infinite pagination 至 page 1。
- Search、assignment type 及學年 ID 同時存在於 request key，不會混用舊 cache。
- URL 使用 `academic_year`，type 使用 `type`，切換時採 replace 並保留其他 query params。
- Cards／List 狀態只影響顯示，不改動學年 request。
- 文案統一為 `All school years`。
- Student pending list 不傳學年 ID，backend 因此使用 active school year；沒有前端跨年過濾。

驗證：

```text
npx tsc --noEmit                                        PASS
npx eslint <academic-year related files>                PASS
npm run build                                           PASS
```

Production build 顯示的 Hook warnings 是專案既有 warnings，本次 academic-year files 沒有 targeted ESLint error。

## 9. 微信小程序

已確認：

- Dashboard grading 學年來自 profile enrollment／teaching assignment，不 hard-code 日期。
- 選擇 Current／Past／All 時 request 會傳 `school_academic_year_id`。
- Search、status、pagination 都沿用同一學年 ID。
- 切換學年 reset page 1，並用 request signature 防止舊 request 混入新年份。
- 待完成作業不傳學年 ID，由 backend 預設 active year。
- API 回覆的 `meta.academic_year` 用於顯示實際待辦學年。

驗證：

```text
node scripts/test-assignment-utils.mjs                  PASS
bash scripts/verify-release.sh                          PASS
Mini Program production build                           PASS
```

## 10. Production read-only smoke check

2026-08-27 未登入 request：

| URL | Result |
| --- | --- |
| `https://aienglish.docai.net/login` | HTTP 200 |
| `https://aienglish.docai.net/essay/dashboard` | HTTP 200 HTML |
| production assignment list endpoint | HTTP 401 JSON |
| production student pending endpoint | HTTP 401 JSON |
| production grading list endpoint | HTTP 401 JSON |

上述證明 production frontend 可達、三個 backend route 已存在且 authentication 正常攔截；它不能證明
production database 已執行 migration 或舊資料已正確回填。

## 11. Production DBA 必做 read-only 檢查

部署／migration 操作者應保存以下 query 結果：

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'essay_assignments'
  AND column_name = 'school_academic_year_id';

SELECT COUNT(*) AS unresolved_legacy_assignments
FROM essay_assignments
WHERE school_academic_year_id IS NULL;

SELECT COUNT(*) AS missing_distribution_year
FROM assignment_distributions
WHERE school_academic_year_id IS NULL;

SELECT COUNT(*) AS invalid_assignment_year_reference
FROM essay_assignments ea
LEFT JOIN school_academic_years say
  ON say.id = ea.school_academic_year_id
WHERE ea.school_academic_year_id IS NOT NULL
  AND say.id IS NULL;
```

還要檢查 migration log 的：

```text
Backfilled N essay assignments; M require legacy date fallback
```

如果 `M > 0`，必須匯出該批 assignment ID、owner、created_at、老師所屬學年及學校 timezone，逐筆確認；
不要只按 9 月 1 日或年份名稱批量猜測。

## 12. Production 尚未完成的 E2E

需要已登入測試帳戶或 staging／production read-only DB 權限：

1. 老師 Current／指定舊學年／All School Years 實際列表。
2. 老師 search、type、Cards／List、pagination 切換後 URL 及數量。
3. 學生 Current pending、Past／All grading history。
4. assignment code 加入後的 distribution year。
5. 同時屬於多個學校／學年的學生，不可看到未 enrollment school 的資料。
6. 微信真機的 Current pending 及 grading year switch。
7. Production query plan／slow query log 在實際資料量下的表現。

未完成上述 authenticated checks 前，狀態應寫成「local regression passed；production DB/E2E pending」，
不應寫成「production 已全部確認」。
