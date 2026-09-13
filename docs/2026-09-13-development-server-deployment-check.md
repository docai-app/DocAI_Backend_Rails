# Development server 部署前核對與交接

日期：2026-09-13。目標：用戶指定的 `103.230.15.190` 測試主機；repo 位於 `/home/akali/aienglish/DocAI_Backend_Rails`。SSH 主機指紋已由用戶確認並固定校驗；密碼未保存至文件或 Git。

## 當前狀態

- GitHub `development` 已包含安全修正 `9f81058bbbcddacccb0054efc90b1e0cdbf881e3`；本地／遠端一致。
- 部署前 dev 實際為 `0948582ca8dfa783f4b842a9537c56094c3cdfc7`，分支 `development`。
- 上一輪只讀核對 prod 為 `94c1210ce67f0470b7bd221d81193ed497c11794`，並非 dev 同版。本次沒有修改 production。
- **用戶已批准安全切換，dev 已於澳門時間 2026-09-13 23:25 切換到 `9f81058`。** 只停止／啟動既有 Rails 和 Sidekiq，Redis 容器 ID 保持不變；未執行 migration、未清理 images、未修改原 deploy.sh。

## 已實際核對

- Dev Rails 使用 `development` 環境及獨立資料庫；查到的資料庫名稱與 prod 不同。沒有複製或修改正式資料。
- 四個 migrations `20260911143000`、`20260912001000`、`20260912030000`、`20260912040000` 均已執行；當前 dev checkout 的 pending migration 清單為空。目標 `9f81058` 相對目前 `0948582` 沒有新增／修改 migration。
- `public.essay_generation_runs`、`public.essay_operation_events`、`public.operations_report_deliveries`、`public.essay_generation_notifications` 存在。
- 兩個事件 trigger 啟用，捕捉函數寫入 `public.essay_operation_events`；資料庫 TimeZone 為 UTC，檢查時 UTC offset 為 0。
- 檢查時 Sidekiq busy=0，queue／retry／scheduled 數量為 0；實際切換前必須重新確認，不能依靠過期快照。
- Rails／Sidekiq 是 source bind mount；目標版本未改 Gemfile、Gemfile.lock 或 Dockerfile，因此本次不需要為程式切換重建整套 image。
- 伺服器有既有字型大小寫變更（大寫檔名刪除、小寫檔名存在），必須保留，不執行 reset --hard、clean 或覆蓋字型。
- Dev 的 `ADMIN_TOKEN` 有設定；Sidekiq 獨立登入帳密尚未設定，部署安全修正後將拒絕 Sidekiq Web，須由工程師補安全設定後才能使用，不能退回公開入口。
- 報告／恢復專用 worker 及開關未啟用；本次程式部署不代表這兩項功能已開啟，也未驗收正式郵件或真實 Dify。

## 原 deploy.sh 為何不原樣執行

原腳本使用 `git pull`、`docker-compose build`、`docker-compose down`／`up -d`，最後全機掃描並強制刪除無標籤 images。它沒有固定目標 SHA／fast-forward 保護，也沒有先 quiet／drain worker。

目前 compose 未配置 Redis 持久化 volume；down／up 會替換 Redis 容器，不能假設 queue、retry、scheduled 和 scheduler 狀態可保留。全機 image 清理不應與本次 scoped 發布綁定。**不要為了部署直接清 queue、刪 Redis 或清理所有 images。**

## 已批准並執行的安全切換

1. 保存原 commit、容器/image ID、工作區狀態及私有設定備份；不把密鑰或資料備份上傳 GitHub。
2. 只 quiet 本次 dev Sidekiq，重新核對 busy=0；等待既有工作結束，不強制終止 Dify。
3. 只停止 dev Rails／Sidekiq；保留 Redis 及其他服務。檢查並 fast-forward 到已核准的精確 `development` SHA，保留字型與本地設定。
4. 啟動原 Rails／Sidekiq，保持原 queue 配置。不執行 migration、不修改 deploy.sh、不 build／刪 image。
5. 驗證容器 SHA、服務穩定、無 pending migration、public table mapping／trigger、worker queue，以及匿名 Admin／Sidekiq 拒絕與合法 Admin 讀取；教師／學生仍走原身份驗證。
6. 回報哪些已驗收、哪些需配置或實際帳號驗收；未完成項不能標成正常。若失敗，停止放行、保留 Redis／資料及回退資訊，由工程師決定修正或安全回退。

## 部署後實際結果

- 停止前兩次核對 worker busy=0、quiet=true；啟動後 quiet=false，保留全部原 queue 配置（包括 default），沒有新增或移除其他業務 queue。
- Rails／Sidekiq 均 running、RestartCount=0，容器 source HEAD 均為 `9f81058`。本交接及 AGENTS 後續文件提交只改 Markdown；同步文件不需重啟服務，功能版本仍為 `9f81058`。
- 實際 HTTP：匿名 Admin categories 401；Bearer null 401；使用伺服器既有合法管理 token 200；匿名 Sidekiq 401；一般 `/api/v1/essay_assignments` 未登入 401，沒有加上全局 Admin token 要求。
- `OperationsStatusReport.verify_capture!` 通過；四個協調／報告 model 都映射至 `public.*`；pending migrations 仍為空。
- 私有回退備份位於 dev 的 `/home/akali/aienglish/pre-security-deploy.Ywk0az`，含原 commit、工作區差異、字型、compose、相關本地設定與 container/image IDs；目錄只供登入使用者讀取，未上傳 GitHub。這是程式／設定備份，**不是完整資料庫備份**。
- 未改正式 server、未進行正式資料寫入、未重跑舊作業，未生成 Dify 或測試寄信。
- **尚未完成**：Sidekiq 合法帳密登入（未配置）、配套 Admin 網頁真實帳號登入及學生／教師完整流程、新生成 Dify 評分、報告／恢復專用 worker 與實際收件。本輪只證明上述部署與介面 smoke checks 通過，不能宣稱所有功能零 bug。

## 工程師後續

- Review Backend `development` 的 `9f81058` 及配套 Admin `main` 的 `622eb09`；不要單獨先收緊 prod Backend 而保留舊 Admin。
- Admin Vercel 的該次發布曾被阻擋，需處理 project 權限及私有登入／proxy 環境變數；目前不能假設它已部署。
- 依 `docs/2026-09-13-admin-api-auth-handoff-zh.md` 協調 token 輪換、Sidekiq 帳密、正式安全切換及验收。
- 報告及失聯恢復 worker 按既有交接文件另行啟用，使用實際啟用時間，不倒填；驗證排程與實際收件。
- Dev 驗收不取代 prod 的備份、migration status、安全切換及真實使用者驗收。涉及 schema／migration 的變更仍只能由工程師先處理。
