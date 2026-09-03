# Bobby Codex Backend 整合與驗證狀態

更新日期：2026-08-27

## 1. 分支與遠端狀態

- Repository：`docai-backend-rails_fresh_2026-04-02`
- 工作分支：`bobby-codex-backend`
- 整合基線：`5f27c6a merge`
- `HEAD == origin/bobby-codex-backend == origin/development == origin/production`。
- 工作分支與 origin 為 `0 ahead / 0 behind`，沒有 commit-level 分叉。
- `origin/main` 為 `dacfe74`；它與自己的 local tracking branch 一致，但沒有包含學年 commits。
- 所有 remote refs 已執行 `git fetch --all --prune --tags`。
- 本地 Release Score 修改在 fast-forward 前使用包含 untracked files 的 stash 保存，更新後成功
  `stash pop`；沒有 conflict，臨時 stash 已自動移除。
- 本文件列出的修改已納入 `bobby-codex-backend` 整合提交並推送至 GitHub；production deploy 不在本次操作範圍。

## 2. 已在 HEAD 的學年功能

目前 HEAD 已包含：

```text
532a378 feat: filter assignments by academic year
6a0e16c feat: support academic year filtering for student records
093954f fix: harden academic year history handling
e979ebc feat: persist assignment academic years
```

核心行為：

- 建立 assignment 時解析並保存明確的 `school_academic_year_id`。
- Teacher assignment list 優先按保存的學年 ID 查詢。
- 歷史舊資料仍提供受控 fallback，不會要求 frontend 載入所有年份再自行過濾。
- Student pending assignments 依 assignment distribution 的學年關係判斷。
- 建立日期不再被當成 assignment 所屬學年的唯一依據。
- 指定舊學年的新 assignment 必須只在舊學年及 All School Years 出現，不會出現在 Current。

最新 `5f27c6a` 同時加入 OAuth partner／assignment webhook 功能。它對
`AssignmentDistribution` 的變更只增加 distribution 建立或 deadline 更新後的 webhook callback，
沒有移除或覆寫學年 association／filter。

## 3. 本次整合的 Release Score 修改

完整規格：`docs/score_release_backend_handoff_zh.md`。

整合檔案：

```text
app/controllers/api/v1/essay_assignments_controller.rb
app/controllers/api/v1/assignment_distributions_controller.rb
app/controllers/api/v1/assignment_statistics_controller.rb
app/controllers/api/v1/essay_gradings_controller.rb
app/controllers/api/v1/my_assignments_controller.rb
app/controllers/concerns/essay_assignment_access_authorization.rb
app/models/concerns/essay_assignment_access.rb
app/models/essay_assignment.rb
app/services/assignment_statistics_service.rb
config/application.rb
config/routes.rb
test/controllers/api/v1/essay_assignments_controller_test.rb
test/integration/assigned_essay_assignment_access_test.rb
test/integration/essay_assignment_shares_api_test.rb
test/migrations/add_school_academic_year_to_essay_assignments_test.rb
test/services/essay_assignment_share_service_test.rb
```

功能摘要：

- 新增 `PATCH /api/v1/essay_assignments/:id/release_scores.json`。
- 支援 Essay 與 Comprehension，不支援其他 category。
- Essay 更新 `meta.score_visible`；Comprehension 更新 `answer_visible`。
- 記錄首次 `score_released_at` 及 `score_released_by_id`。
- `with_lock` 保證 idempotency 及並發一致性。
- Owner 及仍有 category 權限的 active shared teacher 可以 release。
- Detail response 提供 `can_release_scores` 及 `score_release`。
- `config.application` 的 localhost host 規則只供 development／test 本地驗證。

## 4. 合併審計

- Fast-forward：`e979ebc -> 5f27c6a`。
- Stash restore 唯一自動 merge 的共同檔案為 `config/routes.rb`，Git 無 conflict。
- Release route 仍位於 `api/v1/essay_assignments` member routes 內。
- 新 OAuth partner routes 及 Release Score route 同時保留。
- `git diff --name-only --diff-filter=U` 應為空。
- 學年 controller/model 修改與 Release Score 疊加後一同完成 regression；學年基線本身已在整合基線中。

## 5. 驗證記錄

完整學年 production-readiness audit：

```text
docs/2026-08-27-academic-year-production-readiness-audit-zh.md
```

使用專案指定 Ruby `3.1.0`：

- `bundle check`：通過。
- 修改及相關 Ruby 檔案 `ruby -c`：全部 `Syntax OK`。
- 修改及相關檔案的 Ruby syntax：全部 `Syntax OK`。完整 targeted RuboCop 仍會列出專案既有的
  controller complexity／style baseline，因此不把全專案 RuboCop 當作本次 clean gate；功能正確性以
  isolated database regression suite 為主要 gate。
- `git diff --check`：通過。
- Unmerged file check：沒有 conflict marker／unmerged path。
- Branch divergence：工作 HEAD 對 `origin/bobby-codex-backend`、`origin/development`、
  `origin/production` 均為 `0/0`；local `main` 對 `origin/main` 亦為 `0/0`。
- 獨立臨時 PostgreSQL database 已從空 DB 跑完全部 migrations，再執行學年、學生、共享及
  Release Score 相關 tests：

```text
58 runs, 265 assertions, 0 failures, 0 errors, 0 skips
```

測試 database 已刪除，沒有使用 production／development database。

測試同時覆蓋：

- 明確學年保存與 current／past／all list regression。
- Legacy migration backfill、Macau timezone 及非 9 月日期邊界。
- Student pending distribution year 及 grading submission snapshot。
- Distribution endpoint 繼承 assignment year，並拒絕跨學校派發／學年 options。
- SQL pagination、search、category、total count。
- Owned／shared assignment 及跨帳戶學年權限。
- Essay immediate／later score visibility。
- Essay／Comprehension release。
- Owner／shared teacher／無權限 teacher。
- 不支援 category。
- 重複 release 的 idempotency。

本次 audit 額外修正：

- 重新啟用 assignment read／show／update／destroy authorization；shared teacher 不可刪除 owner assignment。
- Student pending assignment 及 grading index 改為 database pagination，不再先 materialize 全部 relation。
- Distribution create／add-students 改為使用 assignment 已保存學年；legacy NULL 才 fallback active year。
- Distribution same-school authorization 重新啟用，不能用其他學校 assignment ID 派發。
- Assignment statistics 依 assignment year 讀取 enrollment，並重新啟用 same-school guard 及 DB pagination。
- 兩個 self-contained share tests 停用全專案 fixtures，避免 stale fixture schema 造成假錯誤。

## 6. 尚未完成的外部狀態

- Release Score endpoint 已推送至 `bobby-codex-backend`，但尚未確認 production 部署。
- `development`／`production` 是否合併這個整合提交，應由後續 PR／部署流程決定，不能因 Bobby branch 已 push 就視為已上線。
- Frontend Release Score 按鈕不可先於 backend endpoint 單獨部署。
- Production deployment 後仍需執行 database migration／release command，因 `5f27c6a` 包含新的
  OAuth partner tables migration；Release Score 本身沒有 migration。

## 7. 建議提交與部署順序

1. 以 `bobby-codex-backend` 建立／更新 PR，確認 target branch 沒有新分叉。
2. 先部署 backend，並執行部署版本需要的 migrations。
3. 驗證 release route、owner／shared permissions、student visibility。
4. 再部署 frontend。

## 8. 不應執行的合併

- 不要把 `origin/main` 強制覆蓋到 `bobby-codex-backend`；目前 main 是較舊且缺少學年功能的歷史。
- 不要為了讓所有 branch hash 相同而 rewrite remote history。
- 不要把 Release Score visibility 與 assignment academic year 再混回使用 `created_at` 的前端過濾。
- 不要在未確認資料範圍前批量修改 `score_visible` 或 `answer_visible`。
