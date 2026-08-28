# 學生 Assignment Read 403 修復

日期：2026-08-28

## 狀態與範圍

- 基線：`5786b0f`，保留遠端新增的登入白名單修復。
- 此 hotfix 與文件一併提交到 `bobby-codex-backend`；本次不修改 production 分支或執行部署。
- 只修改 Backend authorization，不修改 Frontend／微信小程序 request contract。
- 不需要 database migration，不修改 assignment、distribution、submission 的學年資料。

## 原因

`9c2d0f2` 重新啟用 assignment 權限時，把 `read` 與 `update` 同時套用
`authorize_essay_assignment_manage!`。這個 guard 只接受 owner 或有 category 權限的 shared teacher。

網頁學生查看批改及繼續草稿的實際流程為：

1. `GET /api/v1/essay_gradings/:grading_id.json` 讀取本人的 submission。
2. `GET /api/v1/essay_assignments/:assignment_id/read.json` 讀取題目與設定。

第二個 request 因學生不是 owner/shared teacher 而回覆 `403 {"success":false,"error":"Forbidden"}`。
這是權限 regression，不是學年 filter、登入 token 或前端 cache 問題。

此前 regression 有測試 pending list 與 assignment code 的 `show_only`，但漏了 UUID `/read`。
新測試先在未修復程式重現 9 個 403 failures，再驗證修復後的完整雙 request 流程。

## 修正

- `read` 改用獨立 `authorize_essay_assignment_read!`。
- Owner／有 category 權限的 shared teacher 保留原有讀取權限。
- 學生只有在以下任一條件成立時可以讀取：
  - assignment 已明確派發給本人；或
  - assignment 已有本人的 grading／submission／draft。
- 不要求 current year 或現有 category feature，以兼容歷史批改與 code-joined drafts。
- 不因其他學生有 submission、相同 feature 或相同學校就授予讀取權限。
- 不擴大共用 `accessible_by?`，避免學生因此取得老師管理能力。

## 保留的安全邊界

| Endpoint | 學生權限 |
| --- | --- |
| `/read` | 本人派發／submission／draft 可讀，只回 assignment，不回全班 grading list |
| assignment `show` | 仍拒絕，這是包含全班 submissions 的老師介面 |
| assignment `update`／`destroy` | 仍拒絕 |
| `/release_scores` | 仍拒絕 |
| 未登入 `/read` | 401 |
| 無關 assignment `/read` | 403 |

## 驗證

- 隔離 PostgreSQL database 從空 DB 執行全部 migrations，沒有連接 production/development DB。
- 修復前重現：`19 runs, 73 assertions, 9 failures, 0 errors`。
- 第一輪修復後完整學年／共享／Release Score／學生讀取 suite：
  `72 runs, 391 assertions, 0 failures, 0 errors, 0 skips`。
- 再次擴充測試後，以 seed `48281` 及 `91403` 分別跑完整 suite，兩輪均為：
  `88 runs, 571 assertions, 0 failures, 0 errors, 0 skips`。
- Push 前再次 `fetch`／`pull --ff-only`，確認遠端仍為基線 `5786b0f`；第三輪 seed
  `280826` 同樣為 `88 runs, 571 assertions, 0 failures, 0 errors, 0 skips`。
- 覆蓋 Essay、Comprehension、Speaking Essay、Speaking Conversation、Speaking Pronunciation、
  Sentence Builder、Sentence Puzzle、Listening 的 draft／pending／stopped／graded 雙 request 流程。
- 每種類型也測試 pending list → code `show_only` → UUID `read`，即使 category feature 已移除且無 submission。
- 覆蓋 code-joined work 無 distribution、舊學年且無目前 enrollment／feature、其他學生 submission、
  本人另一個 assignment 的 submission、移除派發、未知 assignment ID、未登入及未分享老師。
- Owner／shared teacher 可讀；share revoked 或 category permission 被移除後仍不可借用學生例外。
- 學生不可讀老師全班 grading list、statistics、distributions，不可修改／刪除 assignment；
  Essay／Comprehension 真正可 release 的類型亦明確測試學生無法發布分數。

### 客戶端呼叫點查核

- Web 共用 grading detail，以及 Essay、Comprehension、Speaking Essay、Speaking Conversation、
  Speaking Pronunciation、Sentence Builder、Listening 的 draft editor 均使用 UUID `/read.json`。
- Web pending／join／各類 upload 入口使用 code `/show_only.json`。
- 微信 `api/aienglish.js#getAssignmentDetail` 同樣使用 UUID `/read.json`，呼叫點包括
  `dashboardgrading.vue` 及 `join.vue`；本次沒有修改小程序檔案。

### 驗證範圍與限制

上述為本地隔離 database 的 authenticated API integration tests 及 client 呼叫點審查。
Category fixtures 刻意避免執行真實 AI workflow／音頻／評分 jobs，因此不是所有作業業務的全功能 E2E。
尚未完成 production 部署後的學生登入及真機／browser 畫面驗收，不能宣稱線上已恢復。

## 部署與驗收

此修復需由部署流程部署 Backend；GitHub branch 已更新不代表 production 已部署，僅刷新 frontend 不會修復線上 403。
部署後使用學生帳戶逐一驗證：

1. 打開本人已批改作業：grading API 與 assignment `/read` 均為 200。
2. 繼續本人草稿：同樣兩個 API 均為 200。
3. 本人已派發作業可讀；其他學生／無關 assignment 不可讀。
4. Owner／shared teacher 原有功能不受影響。

不得為了消除 403 而移除全部 authorization，或放開 assignment `show` 的全班成績。
