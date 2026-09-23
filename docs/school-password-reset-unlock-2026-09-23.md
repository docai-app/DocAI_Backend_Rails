# 學校後台：重設學生密碼並解鎖

## 行為與範圍

學校主管理員及獲授權老師使用既有 `POST /api/school_admin/v1/students/:id/reset_password`（以及 `/api/school/v1` 別名）時，重設為既有預設密碼，並清除 `locked_at`、`failed_attempts`、`unlock_token`。未鎖定帳號的失敗次數也清零。帳號的其他角色、功能、學籍、後台授權及停用條件不變。

先沿用當下 actor row lock、授權與學生 scope 檢查，再取得學生 row lock，將密碼與 Devise 解鎖欄位一次驗證儲存。沒有先呼叫會略過驗證的 `unlock_access!`。驗證失敗返回原有 422；密碼和鎖定欄位均不更新。Audit 仍在同一 transaction，沿用 `student_password_reset`，新增布林 `account_unlocked` 表示操作前是否有 locked_at；不保存密碼或 token。

前端現有 API、payload、成功回應格式及操作方式相容，不需要改前端；本次沒有新增按鈕或改文案。無 migration、schema、依賴或設定變更。只影響學校學生重設接口，不改通用忘記密碼或總 Admin 接口。

## 驗證

本機既有隔離 PostgreSQL：127.0.0.1:55439 / listening_rails_isolated_test，RAILS_ENV=test、LISTENING_RAILS_ISOLATED_TEST=1，清除 DATABASE_URL / VECTOR_DATABASE_URL；不執行 migration 或 schema load，不操作真實學校資料。

修正前的行為測試確認：鎖定欄位未清除、未鎖定帳號的登入失敗次數仍保留。新增測試涵蓋：

- 主管理員及獨立受限帳號，兩個 API 別名，重設後鎖定欄位清除，舊密碼失效，新密碼實際登入成功。
- 既有教學老師經真實後台 session 登入後可重設並解鎖授權班級，其他班級完整保留原密碼和鎖定狀態，老師原角色及密碼不變。
- 未鎖定帳號亦清除失敗次數及舊 unlock token；audit 對應 true/false，不含密碼。
- 密碼儲存驗證失敗，原密碼、鎖定狀態、失敗次數及 unlock token 均保持，沒有成功 audit。
- 不同班級、學年、學校均返回 404，原狀態與 audit 數量不变。

複查後執行 `school_password_reset_transaction_test.rb`、`school_password_delegation_test.rb`、`admin_api_authentication_test.rb`、`school_portal_read_performance_test.rb`：**43 tests / 757 assertions，0 failures / errors / skips**。保留既有 wkhtmltopdf 路徑、Rswag 棄用及 HABTM 常數警告。無 UI 改動，未重跑瀏覽器視覺測試；HTTP 登入與權限行為由真實 Rails integration test 驗證。

## 第二輪複查

未發現本次重設及解鎖實作需要再修正的產品問題。新增真實 transaction 測試（不使用 fixture 外層 transaction）：

- 密碼已 save 後強制 audit 驗證失敗，HTTP 422；原密碼、鎖定時間、失敗次數、unlock token 完整回滾，無成功 audit。
- 兩名不同受限老師同時重設同一鎖定學生，以 PostgreSQL `pg_blocking_pids` 證實第二個請求等待學生 row lock。兩請求均成功；第一筆 audit 為解鎖 true，第二筆為 false，最終密碼及解鎖狀態正確。

測試初版的鎖等待查詢受到 query cache 影響而超時，已改為 uncached；合成資料 teardown 受到既有學年刪除保護及 isolated DB 的 Ahoy 關聯欄位限制，已改用精確 fixture IDs 清理。這些是測試工具問題，沒有為了通過測試修改產品的刪除保護或 DB schema。初版留下的四組合成學校資料已在確認隔離 DB 及測試 Email 標記後清理；最終回歸含 teardown 全部成功。

## 交付狀態

2026-09-23 使用者明確要求同步 GitHub、確保沒有分叉並部署 production server。本次以此新授權發布，不改後端日常預設 development 約定。基於 origin/development `1165e51a88ef97f4e4ac3f61f0078e94d9c61aba`，隔離工作分支 `codex/school-reset-unlock`。

發布前重新 fetch，GitHub development / production 與正式 repo 均為上述同一 baseline。以同一後續提交 fast-forward 更新兩個遠端分支，使用 atomic push，不 rebase 遠端、不 force push。正式 repo tracked files clean；保留兩個既有未追蹤字型檔。只讀檢查 pending_migrations=false。本次改動無 schema、migration、依賴或環境設定，前端沒有修改。

目標仍為使用者指定的 akali@43.228.217.157，repo `/home/akali/aienglish/DocAI_Backend_Rails`。四個既有 Rails/Sidekiq 容器共同掛載該 repo；沿用 [已核實的部署順序](school-portal-release-2026-09-21.md#deployment-procedure-and-rollback)：

1. 先 push 並核對 GitHub 精確 SHA，伺服器 fetch 後檢查 baseline、完整 diff 及無待遷移；記錄容器 ID/image/environment SHA256、Redis ID/start time，不記秘密。
2. 對主 worker、operations-reports、generation-recovery 發送 TSTP，確認全部 quiet=true、busy=0 後才停止；保留排隊工作。
3. 只停止 `docai_backend_rails-docai-rails-1`、`docai_backend_rails-sidekiq-1`、`aienglish-operations-reports`、`aienglish-generation-recovery`。`git merge --ff-only <verified SHA>`，再啟動同一四個容器。Redis、QG、其他服務不重啟，不執行舊 deploy.sh、migration、compose down、prune 或 image build。
4. 核對 GitHub/正式 HEAD、容器狀態及環境摘要、載入的 reset 原始碼、HTTP 唯讀接口、worker registry 與排程健康。正式資料不作測試重設；功能以 43 項隔離測試驗證。

回退 baseline 為 `1165e51a88ef97f4e4ac3f61f0078e94d9c61aba`。需要回退時先按相同 quiet/drain 順序停止四個服務，保留 Redis/runtime/排隊工作，將應用回到 baseline（GitHub 記錄對應 revert），再啟動及驗證。只回退程式，不回寫已重設的密碼或重新鎖定帳號。實際發布結果在完成後補記，以上流程不代表已部署。
