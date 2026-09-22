# 學校子帳號：班級密碼授權（無 migration）

> 2026-09-21 更新：新增入口已改為選擇既有老師、沿用老師帳密，只新增後台權限。下方獨立帳號與固定角色說明適用於舊帳號／相容 API；新流程、撤權保留教學功能與驗證見 [既有老師後台授權](school-teacher-portal-access-2026-09-21.md)。本地實作不等於已上線。

## 狀態與範圍

2026-09-18：使用者要求簡化，改用既有帳號 JSON 欄位；取消原先兩張新表的方案。前後端已在獨立工作區實作。使用者已授權檢查後提交／推送前端 `school` 與後端 `development`，明確禁止部署；沒有操作正式資料。精確 GitHub 狀態以分支 SHA 及交付回覆為準。瀏覽器驗收結果見文末；本文件不能當作線上功能已啟用的證明。

- 前端 repo：`qq505810824/AIEnglish_Admin_Dashboard_Frontend`；基線 `school` 的 `e9e93c1`，依使用者要求，工作及交付分支改為 `school`（保留原 main 工作區）。
- 後端 repo：`docai-app/DocAI_Backend_Rails`；基線 `origin/development` 的 `2398322`，隔離 checkout 的工作分支 `development`。
- 總 Admin 原 main 工作區、OCR checkout、小程序及學生作業前端產品程式未修改。
- 沒有新增表、欄位、索引、migration；沒有改 schema 或 SQL DDL。只使用既有 `general_users` 與 `school_admin_audit_logs`。

## 帳號與授權

學校主管理員保持 `school_admin` 角色，在 `/password-managers` 建立獨立 Email 登入子帳號。角色固定為 `school_password_manager`，不是既有教學老師角色的覆寫；已使用的 Email 不能被接管。主管理員可修改姓名、指定新密碼、啟用／停用及授權班級。停用與修改子帳號密碼會讓舊登入 token 失效；再次啟用亦不恢復舊 token。

子帳號只可查看已授權在讀學生的姓名、登入 Email、班級、學號、學籍狀態和更新時間，以及重置其密碼。現有密碼不會回傳；仍沿用既有預設密碼重置流程，成功提示與操作紀錄不記錄密碼值。

`general_users.school_id` 保存學校歸屬；`meta` 使用以下 server-owned 格式：

```json
{
  "aienglish_role": "school_password_manager",
  "aienglish_features_list": [],
  "school_password_access": {
    "enabled": true,
    "created_by_id": "owner-uuid",
    "revision": "opaque-revision",
    "session_version": "opaque-version",
    "grants": [
      { "school_academic_year_id": "academic-year-uuid", "class_name": "1A" }
    ]
  }
}
```

授權精確比對同一筆 enrollment 的「本校＋學年 ID＋班名」；學年與學籍均須 active。不使用 `banbie`、模糊班名或舊學籍擴大權限。新學年、改班名、轉班、撤權後需重新授權；空或不合法授權預設沒有學生可操作。若現有學籍髒資料仍標示在讀，系統會按保存的學籍判斷；本次不整理正式學籍。

角色、enabled 與授權僅由學校主管理員服務端流程写入，普通個人資料 API 不能更新 meta。受限角色另在共用 ApiController 採明確 allowlist，拒絕其他 portal 功能、通用學生／教師 API 及 Admin API。每次請求使用當下帳號資料，不把授權永久寫死在 token。

## API

兩個既有別名 `/api/school/v1` 與 `/api/school_admin/v1` 具有相同限制。

- `GET password_managers`：主管理員限定，20 筆分頁；輸出 id/email/nickname/enabled/grants/revision。
- `GET password_managers/classes`：主管理員限定，回本校 active 學年及有 active enrollment 的班級。
- `POST password_managers`：email、nickname、password（至少 8 字元）、grants；角色及學校由後端固定。
- `PATCH password_managers/:id`：帶原 revision；可改 nickname/password/enabled/grants。停用採明確 false，不採 toggle。revision 不符回 409，不覆蓋別人的授權修改。
- `session` 與 `me` 加上受限角色支援與 capabilities；受限 `academic_years` 只列獲授權的 active 學年。
- 學生列表、詳情、reset 使用相同授權 scope，前端重置傳目前學年。重置與管理員撤權／停用以帳號 row lock 串行化。

操作沿用 `SchoolAdminAuditLog`，記錄真實 actor_role、目標、授權及 enabled 變更；無密碼。原 reset audit 中的預設密碼標籤已從新寫入移除，既有紀錄 API 回傳也排除該欄位；不改寫歷史資料。

## 介面與失敗恢復

沿用 school 分支 Tremor 樣式、學生表格及重置對話框。受限使用者只顯示學生入口，其他直達頁面顯示沒有權限。授權按學年分組勾選，提交前確認實際清單；未儲存關閉有放棄確認。角色／授權變化及登出會重建 SWR cache，避免上一個帳號資料殘留。

表單有同步提交鎖；網路結果不明不自動重試寫入，先重新載入清單核對。重複 Email 有資料庫原有唯一索引保護；一般的 create 不提供跨裝置 idempotency key。帳號編輯有 revision 衝突檢查。

## 本地驗證入口

後端使用既有 `LISTENING_RAILS_ISOLATED_TEST=1`，只在 `RAILS_ENV=test` 啟用，DB 為 loopback 55439 的 `listening_rails_isolated_test`。Ruby 3.1.0，`BUNDLE_WITHOUT=development RUBYOPT=-rlogger PARALLEL_WORKERS=1`，清除 `DATABASE_URL`／`VECTOR_DATABASE_URL`，只設定測試 JWT／Azure 佔位值。不執行 migration 或 schema load。

```sh
bundle exec rails test test/integration/school_password_delegation_test.rb test/integration/admin_api_authentication_test.rb
```

後端 `test/support/school_password_browser_seed.rb` 只允許上述隔離 DB，建立合成學校、主管理員及 1A／1B／2A 學生。固定 fixture 登入值只用於 loopback 測試，不可在正式環境執行此 seed。

前端 `tests/school-password-delegation.browser.cjs` 連真實本地 Next 與 Rails：預設 3001／4117，拒絕非 127.0.0.1 host。需提供已安裝 Playwright 的 NODE_PATH 或由本機測試 runtime 解析。兩種角色都經實際登入表單登入，資料請求使用真實瀏覽器 CORS；Rails 既有隔離 test 設定允許 3001。只在衝突恢復案例模擬 PATCH 409；沒有變更正式 CORS 設定，不代表部署域名 CORS 已驗收。使用合成資料，不操作真實學生。

## 發布與回退

2026-09-18 使用者已授權本次 GitHub push，並明確要求不要部署。已 fetch 兩個目標分支，基線均沒有新的遠端提交。前端 `school` 最新 commit 的 GitHub checks/status 顯示三個 Vercel 專案仍有整合：`ai-english-schooladmin-dashboard-frontend`、`ai-english-admin-dashboard-frontend`、`dev-ai-english-admin-dashboard-frontend-c98s`。既有部署失敗不代表停用自動部署，故前端提交完成後暫不 push，須先確認不觸發部署的方式；未自行修改 Vercel 設定。後端沒有 GitHub Actions workflow、分支 check/status 或 deployment 紀錄，沿用既有手動伺服器發布流程；本次不執行任何部署命令。優先上後端，再上 school 前端。若目標 DB 缺少既有 school_id 或 audit 表，仍要交工程師處理，不能把本次無 migration 當成任何舊 migration 已完成。

回退：先撤回前端子帳號入口，再回退後端版本；新角色在舊 school portal 會被拒絕，既有主管理員維持原邏輯。保留 metadata 和 audit 記錄，避免失去授權歷史。不回退密碼重置造成的學生密碼變動。

## 驗證結果

- Rails 18 tests / 446 assertions，0 failures、0 errors；包含新授權及既有 Admin API 認證回歸。
- 前端 TypeScript 全量檢查通過。
- 前端 lint 完成，既有 hooks／圖片警告保留，未关闭規則。
- 真實本地 Next + Rails 瀏覽器流程通過：建立帳號、欄位驗證、鍵盤勾選、390px 窄屏、授權班級隔離、學生重置、直接網址拒絕、撤權、空授權、停用登入、身份快取隔離、密碼顯示／隱藏、焦點重驗保留輸入、409 衝突恢復；無 pageerror。測試結果和截圖由 browser 腳本輸出至指定本地目錄。
- DESIGN.md 官方 lint：0 errors / 0 warnings。全 repo Premium 靜態審核仍有 17 項舊頁面問題（7 項 native select ownership、8 項 button 靜態偵測、2 項舊 form noValidate）；新增密碼管理功能未被列出。未為通過審核擴大重構舊頁面，不宣稱全站已通過設計審核。
- Next 正式 build 通過，包含 `/password-managers` 路由；建置仍顯示既有 hooks／圖片警告及 edge runtime 提示，未关闭任何檢查。
- 本地安裝發現原 package-lock 與 package.json 不同步，`npm ci` 未通過；未改鎖檔。以既有 manifest 安裝到獨立工作區，並補回原 lock 已包含的 `@headlessui/tailwindcss@0.2.0` 供驗證，不新增產品依賴。

## 交付前第二輪複查（2026-09-18）

- 再次檢查角色限制、跨校／跨學年／精確班級範圍、舊 token 撤權與停用、revision 衝突及 audit 密碼遮蔽，未發現阻擋本次功能交付的問題。
- Rails 再跑 18 tests / 446 assertions，全部通過；TypeScript 通過，lint 僅保留既有警告。產品程式未在首次 build 通過後改動，沒有無故重建正在供使用者預覽的 production build。
- 將瀏覽器回歸改成實際登入表單及原生本地 CORS，完整流程再次通過。預覽保留在 loopback 3001（Next）／4117（隔離 Rails test）。
- 本次沒有資料庫結構或依賴清單／lockfile 變更。既有 npm ci 鎖檔不一致仍是未解決的環境限制，不能把本地 build 通過當成乾淨 CI 安裝已通過。
