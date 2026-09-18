# 正式報告／恢復 worker 與 Sidekiq 帳密啟用

本次使用者明確要求繼續完成 9 月 17 日 Backend 切換後的待辦。**9 月 18 日已正式啟用兩個專用 worker 與 Sidekiq 獨立帳密；Admin 密鑰輪換及實際收件仍須配合驗收。** 以下以當次證據區分已完成與未完成，不能把整份文件視為所有功能已驗收。

## 基準与範圍

正式 Backend 基準 `753e4f9f09604f9c1c29264149774d2e1c595e7f`。9 月 18 日只讀核對仍與 GitHub development 一致；沒有待執行 migration，capture 檢查通過。既有 Rails／主 worker／Redis 均正常，報告與恢復角色尚未配置、schedule 與 report delivery 為空。

先提交 `fe31db13786c887d8c1af0d3b7a313b336af3d7e`，新增 `ops/reliability` 運行工具、測試及文件。啟動驗收發現 scheduler 共存問題後，再提交 `8b3f9bd0a198b3bf9e0f2d8f0e7e7adb30f48e56` 修正 scheduler 初始化；兩者均先 push GitHub `development` 再部署。沒有更改評分／生成／郵件業務邏輯，沒有 schema 或 migration 差異。沒有執行原本會 down/up Redis 的 deploy.sh。

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

修正已於 **2026-09-18 11:29:41 +08:00** 完成正式切換：三個 Sidekiq 均 quiet、確認 busy=0／WorkSet=0 後停止，停止 Rails web，fast-forward 至 GitHub 相同 SHA，再啟動原容器。沒有強殺 Dify 工作、沒有停止 Redis，也沒有操作其他服務。原啟用時間保留，沒有重新建立容器或修改 cutoff。

## 已執行配置與版本

| 項目 | 當次實際值／結果 |
| --- | --- |
| 應用修正版本 | `8b3f9bd0a198b3bf9e0f2d8f0e7e7adb30f48e56`；GitHub `development` |
| 正式 checkout | `/home/akali/aienglish/DocAI_Backend_Rails`，本地分支仍名為 `production`，內容更新至上述 SHA；沒有 push GitHub production 分支 |
| Image | 沿用 `sha256:ae906bce7962b69b5a165bac7ae0c535ed18d6f703d4dbc2051387d7a404dc45`，程式由既有 bind mount 提供 |
| Rails／主 worker／Redis | 保留原容器；主 worker concurrency 6、原 19 queues（含 default）不變；Redis 沒有重啟 |
| 報告容器 | `aienglish-operations-reports`，concurrency 1，只聽 `operations_reports` |
| 恢復容器 | `aienglish-generation-recovery`，concurrency 1，只聽 `generation_recovery` |
| 報告 cutoff | `2026-09-18T11:21:43+08:00` |
| 恢復 cutoff | `2026-09-18T11:21:44+08:00` |
| 收件人 | 兩個專用容器明確配置 `ADMIN_NOTIFICATION_EMAIL=bobby.lian@docai.net` |
| 專用容器限制 | 各 1 CPU／1.5 GiB、無 published ports、restart always、log 上限 10 MiB × 3 |
| Migration／capture | `20260911143000`、`20260912001000`、`20260912030000`、`20260912040000` 已核對，無待執行 migration；capture 檢查通過；沒有執行 migration／修改 trigger |

專用容器建立時 label／manifest 記錄的是 `fe31db1`，之後 source bind mount 升至 `8b3f9bd` 並重啟程序。**建立 label 不是現在載入程式版本的證據**；須同時核對 checkout、差異及程序啟動時間。後續若只有文件更新，不需重啟 workers；應用程式改動仍須依上方 drain 流程。

啟用開關只放專用容器私有 env；沒有把兩個角色的開關混入 shared `.env`。恢復 worker 每五分鐘掃描、只納入 cutoff 後建立且逾兩小時的符合類型任務；今天約 13:21:44 前不會因新 cutoff 而出現兩小時候選。歷史 pending 沒有批量納入／重跑。仍在 queue／worker 中的工作不重跑，未知結果仍須查核，並非兩小時一到便盲目重試。

恢復 scanner 目前明確涵蓋 `essay`、`speaking_essay`、`speaking_conversation`、`sentence_builder`、`talk_lab_speaking` 的 generation slots；不是所有 assignment 類型的通用失聯恢復。Speaking Pronunciation、Comprehension、Sentence Puzzle 及本輪排除的 Listening 不因本次啟用而新增此 scanner 覆蓋。

## 私有資料與交接

本次受保護 runtime 目錄（不在 Git）：

`/home/akali/backups/aienglish-activation-20260918.yTrRPB`

- 目錄 mode 700；role env／manifest、原設定備份及 Sidekiq 帳密檔 mode 600。
- Sidekiq 帳密：`sidekiq-credentials.private.json`。工程師登入主機後透過團隊密碼管理器交付；不要貼到聊天、issue、郵件或 Git。
- 兩個 role env 保留實際啟用時間，不能刪掉重建或倒填時間。
- shared `.env` 已收緊為 mode 600，僅追加獨立 Sidekiq 帳密，沒有輪換 `ADMIN_TOKEN` 或修改 SMTP。
- 原完整 DB 備份位於 `/home/akali/backups/aienglish-predeploy-20260917T095632Z/docai_prod.dump`，11,003,270,905 bytes，9 月 17 日已完成隔離還原驗證。快照為 9 月 17 日 17:56:52 +08:00，**不包含之後的提交**；本次沒有把它當成最新即時備份或回退資料庫。
- 本次來源／runtime／服務資訊及診斷 stderr 留在私有目錄，不能直接整包公開，因其中包含設定備份。

## 正式驗收證據

### 權限與服務

- 外網匿名 `/api/admin/v1/essay_assignments/categories`、`/sidekiq`、`/sidekiq/busy` 均為 401；Sidekiq 錯誤帳密亦 401。
- 使用伺服器內存的獨立 Sidekiq 帳密讀取 `/sidekiq/busy` 為 200，回應確為 Sidekiq。沒有測試停止／刪除管理操作。
- 正式 Admin 舊瀏覽器 session 刷新後過期，跳至正常登入頁；已請使用者重新登入。這不是已完成的「登入後列表驗收」。Backend token 沒有輪換。
- 直接以伺服器內存的既有 Admin token 查詢 categories API 為 200；普通老師 JWT 查詢同一管理 API 為 401。沒有輸出／複製 token 到瀏覽器或文檔。
- 三個程序已確認分別監聽各自預定 queues。檢查時 Rails 約 656 MiB、主 worker 約 287 MiB、報告約 219 MiB、恢復約 224 MiB；是當刻快照，不是長期容量保證。

### 真正排程

- 修正後兩個 schedule 名稱同時存在：`ai_english_operations_report`、`ai_english_generation_recovery`。
- 正式日誌可見兩個角色的 startup tick，及 **11:30、11:35、11:40** 的定時入隊／執行／完成，均使用澳門時間。
- 恢復 heartbeat 為 `completed`，checked_count=0、error_count=0；cutoff 後尚沒有超過兩小時的候選，所以**這不等於已在正式環境驗證一筆真正失聯恢復**。
- 排程每五分鐘核對報告邊界；信件仍僅對應 12:00／18:00／00:00 的固定時段，不是每五分鐘寄信。新啟用後第一個應寄時段為今天 00:00–12:00，不補寄 cutoff 前的歷史時段。

### 一筆合成新提交

使用既有測試帳戶 `teacher@docai.net`，只在其本人擁有的 Essay assignment 新增一筆帶 `OPS ACCEPTANCE 2026-09-18 reliability activation` 標記的合成作文。沒有派發給學生、修改原答案、冒用學生身分或強制 rerun。

- Assignment：`435183ce-65ef-4ae8-a3fb-8fdf92c96d8c`。
- 新 submission：`9da87f7c-5da7-4ca9-93b5-61af56ecbfbe`，11:35:58 建立。
- 真正 HTTP create API 返回 201／pending；之後正式 worker 處理成 graded。
- 主批改 ready，attempts=1，grading／general_context／revised_essay checkpoint 齊備，recovery_version=1。
- 詳情 HTTP API 返回 200，score=91、full_score=100、suggestions=4；與共用 metrics 一致。
- 補充練習 ready，attempts=1，15 題通過正式 `SupplementPracticeValidator`，包括全答對／全空答案的計分契約。
- 紀錄保留供追查，會納入當期報告的提交統計；未刪除。這是 Backend／Dify 真實新提交驗收，**不是學生瀏覽器全流程、所有 rubric 或所有 assignment 類型的完整驗收**。
- 這筆正常完成後 provider_context 會清除，不能把正常完成宣稱成已驗證原 Dify GET 取回失聯結果；沒有為製造失聯而中斷正式任務。

### Sentence Builder 與原 Dify 查詢

再以同一測試帳戶，對其既有 `invention` 測試作業 `a90d229e-61f9-4f90-9397-a584063a7308` 提交一條合成句子；沒有新增／派發 assignment，也未改學生資料。

- 新 submission：`3b9b8897-7867-4885-8f75-18731944adec`，HTTP create 201。
- 實際 worker 完成後 graded，run ready／attempts=1，score=1、full_score=1、suggestions=0。
- 在原任務 context 尚在時取得 workflow ID，透過正式 `DifyWorkflowRecovery.lookup` **只做 GET** 查回原結果，status=succeeded、outputs 已解碼為物件，沒有發第二次生成 POST。這證明正式 provider 原結果查詢可用，但仍不是一次真正故障後的自動恢復全流程。
- 對這筆合成紀錄透過正常 PATCH 嘗試 status=draft，返回 **409**；前後整筆 attributes 摘要一致，保持 graded。沒有對學生真實紀錄做此負向寫入測試。
- 兩筆合成驗收紀錄均保留，所以當期提交統計包含它們。

### 正式網頁小範圍驗收

使用內置瀏覽器中既有 `teacher@docai.net` 正式登入 session，而非本地 fixture：Essay 頁實際顯示 91／100、4 個 Grammar 高亮及各結果頁籤；Sentence Builder 實際顯示 1／1、合成句子及參考答案；Supplementary Exercise 正常載入 5 個 sections／15 題。僅在上述合成練習第一題輸入 `check`、按 Save as Draft，成功返回 dashboard 後重新打開同一練習，答案 `check` 仍在、進度為 1／15（7%）。保留此測試草稿，不提交全部答案、不點重新生成，不更動任何學生原有練習。這項不代表小程序、手機或所有老師／學生角色均已驗收。

### 本輪重跑測試

- 運維 Python unit tests：9 項通過。
- 真實 Sidekiq／scheduler gem＋独立 localhost Redis：4 tests／21 assertions 通過。
- Rails 明確隔離 localhost PostgreSQL：109 tests／1,071 assertions，0 failures／errors。涵蓋報告、恢復、競爭、Admin/API/Sidekiq 權限、生成驗證及 Comprehension 計分；SMTP／Dify 使用隔離 stub，不碰正式學生資料。
- 另補跑列表／詳情摘要及 AI JSON parser：45 tests／363 assertions 通過。兩組 Rails 合計 154 tests／1,434 assertions；不是完整全產品測試套件。
- 本地首次測試因缺假 Azure／JWT 設定及 sandbox localhost 權限未就緒而未通過；補齊隔離假設定／本地連線權限後完整重跑通過，沒有改正式 secret 或關閉測試校驗。

## 仍待完成

1. **Admin 密鑰／登入凭證輪換**：需要正確 Vercel project 存取或工程師同步配合兩端設定及其他合法消費者。Sidekiq 獨立帳密已完成不代表此項完成。
2. **Admin 重新登入後的管理 API UI 驗收**：舊 session 已失效，等待使用者登入。
3. **收件匣確認**：第一封 12:00 排程報告已傳送成功（下節）；已詢問收件人，尚未取得實際收到／內容可讀的確認。不能將 SMTP 接受等同收件匣已收到。
4. **正式真正失聯恢復個案**：scanner 已啟用並有 heartbeat，但沒有為驗收而製造真實故障；查回 provider 原結果／不中斷活躍任務仍有隔離回歸，正式案例需另觀察。
5. 18:00／00:00 實際邊界、長期 resource 使用、off-host 持續備份、入口網路／速率限制尚未作本輪實際驗收。

郵件預覽已在正式 report worker 以真實資料產生，但沒有送信：截至 11:45 的 00:00–11:45 時段，14 個新作業、160 筆提交（當刻全部 graded），388 項跨時段異常、warnings=0，HTML／完整 MIME 成功 render，約 21.8 秒。此時尚未包含後續的 Sentence Builder 合成提交；**388 項不是本次啟用造成的新失敗**。郵件最多列前 100 項並標示截斷，仍需透過 Admin 查完整歷史問題。12:00 正式信件應以該時刻生成的數字為準，不能直接引用這份預覽數字。

## 首封正式排程郵件結果（12:01:46 核對）

不是手動寄信、沒有改時間、沒有重設 delivery claim：

1. 12:00:00 cron 自動將 `OperationsReportTickJob` 入隊。
2. 12:00:01.857 tick 完成、`OperationsReportJob` 開始。
3. 12:00:24 HTML 與純文字版本完成 render。
4. 12:00:25.088 claim；**12:00:31.167 記錄 sent**；job 12:00:32.352 完成。

澳門時間。Delivery ID：`082f0892-3f3a-4c19-8d31-127bfd7b4a1a`；時段 **2026-09-18 00:00–12:00**；state=sent、failure_class=nil、同一 period_end 只有 **1** 筆、report queue=0。SMTP 接受由既有 Mailer／傳送流程記錄，沒有另建郵件系統，也沒有人工重寄。

收件人 `bobby.lian@docai.net`。主旨含「需人工處理 388 項／請查看警告」與「09/18 12:00 澳門時間」。正式 summary：14 個新作業、6 位老師、161 筆提交（產生時全為 graded，含本次兩筆合成驗收）、388 項跨時段待核查，warnings 為空。大量歷史異常只是提醒，未被批量 rerun。

同時恢復 heartbeat 於 12:00:01 完成，checked_count=0、error_count=0，兩個 schedules 仍同時存在。下一個正常報告邊界是今天 18:00，之後明日 00:00；該兩個真實時點仍待觀察，不冒充已驗收。實際收件／是否落到垃圾郵件仍等待收件人確認。

## 停用／回退原則

先停止相關專用 worker 領取工作，等 busy=0，再停止並設 `restart=no`；保留 env cutoff、queue、delivery／學生資料。若只需停報告或恢復，另一角色與主批改可獨立保留。不要直接 rollback 至缺少管理 API 安全修正的舊版，也不要為回退應用碼還原整個 DB。不能直接啟動 scheduler 修正前的三個程序而宣稱仍有可靠共存排程。
