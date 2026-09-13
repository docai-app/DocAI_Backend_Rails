# Rails 管理 API 與 Sidekiq 存取控制交接

2026-09-13；基準 `94c1210`／交付分支 `bobby-codex-backend`。**用戶已授權推送 GitHub，由工程師 review 及部署；本輪不直接操作 Rails 正式伺服器。請配合總 Admin 版本發布，不要只先部署本 Backend。** 精確交付 SHA 以交付訊息及 Git log 為準。

## 原因

原先部分 `/api/admin/v1` controller 未啟用 `AdminAuthenticator`，未登入也能讀取資料；Sidekiq Web 直接公開掛載。總 Admin 舊 Basic popup 只保護 Admin 網頁，無法代替 Rails 的身份驗證。

## 實作

- `AdminApiController` 共用 `AdminAuthenticator`；其餘以 `ApplicationController` 為基底的 Admin EssayAssignments／LearningPathTemplates／AssignmentPackages 也明確加入。
- 認證 callback 放在其他 before actions 前，沒有有效 token 不查業務資料或執行工作。支援正規 `Authorization: Bearer <token>`；拒絕缺少、空值、Bearer null、錯誤憑證；設定未提供亦拒絕。回傳 401 JSON，不使用瀏覽器 Basic challenge。管理回應 `Cache-Control: no-store`。
- 採既有 Rails `ADMIN_TOKEN`，但正式必須輪換曾經放入 `NEXT_PUBLIC_BEARER_TOKEN` 的公開值。新值只放 Rails 與 Admin server (`ADMIN_RAILS_TOKEN`)；不能相容接受 null 或把教師／學生 JWT 當全局管理員。
- `lib/admin_sidekiq_authentication.rb` 與 `config/routes.rb` 保護 Sidekiq Web（含狀態及操作入口），使用 `SIDEKIQ_ADMIN_USER`／`SIDEKIQ_ADMIN_PASSWORD` 獨立 HTTP Basic；缺少設定拒絕。不改 worker、queue、Redis 或 Sidekiq 原有 CSRF middleware。
- 認證保護涵蓋目前全部 14 個 routed Admin controller；測試檢查所有 controller 的第一個 before action，避免漏保護另一個 ApplicationController 子類。公共 `/api/v1`、`/api/school*` 與 OAuth 登入流程未改。
- 更新原有 admin rerun／OAuth 管理測試以附合法管理 token，沒有關掉認證或把所有請求視為已登入。

Sidekiq 的 Basic middleware 方式參照[官方 Monitoring 文件](https://github.com/sidekiq/sidekiq/wiki/Monitoring#rails-http-basic-auth-from-routes)。還需要工程師部署網路限制及登入速率限制；本次不是 MFA／逐個管理員授權系統。

## 部署必讀

1. **先取得配套總 Admin 的 GitHub 交付版本並安排部署。** 總 Admin repo `qq505810824/AIEnglish_Admin_Dashboard_Frontend`、分支 `main`、基準 `30d7ca79ef4262221e77cbc0dff4cbeaf0e55e83`。用戶現已授權 push 及可能觸發 Vercel；該 repo 連接總 Admin、school-admin、dev 三個 project，工程師須核對各自環境設定。完整範圍與變數在該 repo 同名交接文件。
2. 新 Admin 透過 HttpOnly session → server-only `/api/admin/v1/*` proxy 注入 token。不部署這個配套，舊瀏覽器發送的 Bearer null 會被新 Rails 拒絕。
3. 核准後先把最終兩邊程式與非敏感配置提交到對應 GitHub，保存精確 SHA；部署 server 應 checkout 相同 SHA。正式 secret 不提交。不要 `git add .` 把其他 Listening 或本地 output 一起帶上。
4. 協調同一窗口輪換 Rails `ADMIN_TOKEN` 及 Admin `ADMIN_RAILS_TOKEN`（至少 32 隨機字元），並設定 Sidekiq 獨立帳密。盤點其他合法使用 ADMIN_TOKEN 的系統；不能假設只有這個 Admin 使用。舊 token 不可永久保留作相容通道。
5. 部署配套 Admin 後再收緊 Rails。兩端憑證更新期間可能有短暫 502；必要時先限制管理入口並顯示維護，不能承諾零停機。安全 drain 主 worker；不 kill 正在呼叫 Dify 的工作。
6. **這次沒有新增 migration 或 worker 設定。** 前一輪已完成的四個 migration 不需重跑。報告與失聯恢復 worker 仍是另一份操作清單，本次不啟用它們，也不寄正式郵件。
7. 未登入讀管理 API 必須 401；Sidekiq 未提供有效帳密不能進入。正常 Admin 讀取／合法修改及一般教師／學生操作需驗收。不要使用正式刪除或 Stop All 作測試。
8. 如果要回退，先維持管理入口的網路限制，協調前後端版本／token；不能把公開且無認證的舊接口當作安全回退終態。資料表、學生資料、成功批改及佇列都不需要回退或刪除。

## 測試

明確隔離 PostgreSQL test DB（`RAILS_ENV=test LISTENING_RAILS_ISOLATED_TEST=1`，Ruby 3.1），不連 production、不呼叫正式 Dify/SMTP。

- 206 tests／1976 assertions：auth、Sidekiq 拒絕路徑、生成／防重複／恢復／報告、摘要、Supplementary、學生／全局 admin 既有授權、學年、Comprehension；全部通過（seed 91323）。
- OAuth Admin create/enable/list：另 1 test／9 assertions 通過。
- 真正本地 Next production server → TLS bridge → Rails test server：18 個 HTTP 檢查通過，確認不是只 mock header；未登入拒絕、合法 session 注入私有 token 可取得 categories、跨站拒絕、缺少記錄 404 及 Sidekiq 拒絕正常。
- 舊 OAuth disabled-client／missing-PKCE 兩項測試原本預期未登入返回 400，但目前流程先 302 到登入。在乾淨 `94c1210` 快照重現相同失敗；本次沒有修改其公共 OAuth 邏輯，沒有放寬測試。不能宣稱整個 repo 全部測試綠燈。

主要新測試：`test/integration/admin_api_authentication_test.rb`、`test/services/admin_sidekiq_authentication_test.rb`。原 `test/integration/essay_generation_recovery_edges_test.rb` 與 `oauth_phase1_test.rb` 僅補管理請求憑證。

## 尚未完成的事情

工程師仍須 review 最終版本、正式部署、驗收實際管理帳號及檢查網路／速率限制。報告及恢復專用 worker、正式報告收件、歷史 pending、Speaking Essay 非數字分數缺口不會因這次 auth 修改自動完成。

本輪未修改學生／老師 frontend、微信小程序 repo、Listening、郵件／Dify 業務邏輯或 AGENTS.md。
