# 正式報告／恢復 worker 與 Sidekiq 帳密啟用

本次使用者明確要求繼續完成 9 月 17 日 Backend 切換後的待辦。此初始提交為操作工具與方案，**不是已啟用或已完成收件驗收的聲明**；實際時間與結果須在執行後補充。

## 基準与範圍

正式 Backend 基準 `753e4f9f09604f9c1c29264149774d2e1c595e7f`。9 月 18 日只讀核對仍與 GitHub development 一致；沒有待執行 migration，capture 檢查通過。既有 Rails／主 worker／Redis 均正常，報告與恢復角色尚未配置、schedule 與 report delivery 為空。

新提交只新增 `ops/reliability` 運行工具、測試及文件，不更改評分／生成／郵件業務邏輯，不新增 schema 或 migration。需要先將工具提交 GitHub development，再在指定正式 checkout 使用精確 SHA；不得執行原本會 down/up Redis 的 deploy.sh。

## 預定操作

1. 保留正式 runtime 設定及容器資訊；使用前一日已完成並實際隔離還原通過的完整 DB 備份，說明該快照不含後续新增資料。本次不寫入結構、不重跑 migration。
2. 以 `sidekiq_credentials.py` 建立獨立隨機 Sidekiq 帳密，保存於伺服器受保護目錄，追加到 `.env`；保留所有既有值，尤其 ADMIN_TOKEN。只重啟 Rails web 讀入設定，不需重啟主 worker 或 Redis。
3. 以 `worker_runtime.py` 各啟動一個 reports／recovery 專用容器。沿用既有 immutable image、正式 DB／Redis／SMTP 和 source mount；concurrency 1、各自原 queue、restart always、限制 log／CPU／memory，沒有 published ports。
4. 每個角色使用當次真實澳門時間；不倒填，歷史 pending 不自動納入。明確收件人為使用者已核准的 `bobby.lian@docai.net`。
5. 驗收 Sidekiq 匿名／錯誤憑證 401、有效憑證 200，既有 Admin read 正常；核對兩個 startup tick 和至少兩次 cron tick、queues、concurrency、健康狀態、SMTP 及實際收件。
6. 以專用測試資料驗收新提交／provider 結果，不修改真實學生作業，不強制停止正式 provider 工作製造失聯。正式恢復成功與 scanner 空掃描須分開說明。

## 未能單方面完成的事項

目前 Vercel 帳號仍查不到總 Admin 專案。Rails ADMIN_TOKEN／Admin ADMIN_RAILS_TOKEN 及曾公開的登入憑證輪換仍需工程師提供專案權限或同步配合。本次 Sidekiq 新帳密不是 Admin token 輪換；不能把這項標成已完成。也不新增 WAF／網路允許清單。

## 操作及停用

詳見 `ops/reliability/README.md`。兩個 worker 可獨立 quiet、等待 busy=0、停止並關閉 restart policy；保留 runtime env 的原 cutoff、queue 及所有資料。以後更新 source bind mount 要把它們一起納入 drain 流程，避免旧程序混讀新程式。

## 本地驗證

新增工具 9 項 Python unit tests 通過，涵蓋錯誤容器／mount／network／環境 fail closed、角色分離、Macau cutoff、重複 runtime 不覆蓋、secret 檔權限、dry run 不寫入及 Sidekiq 設定保留既有值。這些測試不連 Docker／正式 DB／SMTP。既有候選 Rails 175 tests／1,689 assertions 為前輪證據，不能冒充本輪重跑。

## 實際啟動發現的排程共存缺口

兩個 worker 初次於 11:21:43／11:21:44 澳門時間啟動，各自 startup tick 完成，但後啟動程序的 scheduler 預設空 YAML 覆蓋共享 Redis schedule。已有記憶體 timer 不代表共享登記正常。已用安裝版本 sidekiq-scheduler 5.0.6 的 Manager／Schedule 實作定位，並加入本機獨立 Redis 的真實 gem 回歸。

修正：三個 Sidekiq YAML 都先停用 gem 預設的整體 schedule 指派；只有該角色 initializer 用 set_schedule 寫入自己的名稱後，明確啟用本程序 scheduler。主 worker 沒有 active recurring definitions，保持 scheduler-disabled，但 queue／concurrency 不變。兩個專用角色仍只排自己監聽的 queue，停用角色只刪自己的登記。沒有改其他服務 Redis、gem 檔案或使用全域 monkey-patch。

此段是修正說明，不代表已部署修正；須在 push 後安全重啟相關 Sidekiq，再確認兩個登記及各兩次五分鐘 tick。原啟用時間必須保留，不重新建立容器或修改 cutoff。
