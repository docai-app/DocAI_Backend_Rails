# AI English 定時運行報告

## 交付狀態與範圍

本報告功能在 backend 實作；總 Admin、小程序及未完成 Listening 程式未修改。整體發布另含前端的批改狀態提示，交付狀態及最終測試見[工程師交接](2026-09-12-reliability-release-handoff-zh.md)。未部署、執行 production migration 或寄送正式郵件；不得將本地測試當成正式排程已啟用。

沿用 `AdminNotificationMailer`、`ADMIN_NOTIFICATION_EMAIL`（未設定時沿用現有預設收件人）、`MAILER_FROM` 及 SMTP 環境設定。不新增另一套郵件供應商，也不建立 Codex 桌面排程。報告須在伺服器運行，不依賴使用者電腦開機。

## 時段與排程

固定 `Asia/Macau`，起點包含、終點不包含：

| 報告截止時間 | 統計範圍 |
|---|---|
| 12:00 | 當日 00:00–12:00 |
| 18:00 | 當日 12:00–18:00 |
| 00:00 | 前日 18:00–24:00 |

`OperationsReportTickJob` 每五分鐘核對已到期時段，並在報告 worker 啟動時核對一次。截止時間會落在排程分鐘上；實際寄達仍受統計時間、報告 queue、SMTP 延遲影響，不能保證精確到秒。

每份 job 帶固定 period_end，重試／延遲執行不會變成另一個時段。啟用時間之前的截止點不自動補寄；啟用之後中斷，最多補最近七天，超過七天會在報告標示需核對缺失時段。週末／沒有提交的時段也會寄送。

使用獨立 `operations_reports` queue，獨立 concurrency 1 的 Sidekiq process；不要讓它監聽 grading queues，也不要把它加入主批改 worker。如此批改 worker 全部卡住時，報告仍有自己的執行位置。整台伺服器、資料庫、Redis 或 SMTP 全部失效仍需要外部監控，不能依靠同一系統保證告警送達。

## 報告內容與介入提示

- 主旨以 `【需人工處理 …】` 開頭；HTML 和純文字版第一區塊皆列出異常／資料不完整。
- 跨時段未解決的 stopped、pending 超過兩小時、generation unknown、supplement failed 都列入；主批改 graded 但練習仍卡住也列入。已追蹤任務以目前 queued/started/next_retry 時間計算，不把剛重排的舊作業誤報成卡住。
- 顯示學校、作業名稱、紀錄 ID、狀態、執行次數和保留下來的失敗階段；連到 Admin 作業提交清單和原有 grading 詳情。沒有一鍵自動變更狀態的郵件連結。
- Pending 超時是疑似異常，不是已證實工作消失；報告不會自行 rerun、停止 worker、取消 Dify 或刪答案。
- 顯示每校、每類型的新作業／提交／graded／pending／stopped／曾失敗／恢復數，平均、中位數、P95 及可信時間樣本數。
- 整體錯誤事件包含本時段發生在舊提交上的錯誤；分組的失敗／恢復數則基於本時段提交群體。補充練習失敗不被當成主批改已恢復。
- 列出老師建立的作業、所屬學年、建立時間及連結。不包含學生作文全文、錄音、API token 或完整原始錯誤訊息。
- 學校歸屬：建立作業使用作業的學年所屬學校；提交使用 submission_school / submission_academic_year。缺失列為學校未確認，不能用老師目前的學校猜測。
- 詳細計算最多讀取每組 5,000 筆；超限在最上方警告，不能將截斷後的分組數據當成完整。全局提交／狀態計數仍使用 SQL count。郵件最多列出 100 個异常項目；長期大量异常需要 Admin 核對。

## 時間／歷史的可信度

新增 `essay_operation_events` 觀察 public schema 的狀態轉換，記錄首次正式提交、graded、stopped、錯誤階段及 generation 狀態／嘗試次數。事件與原寫入同交易，rollback 不留下假事件；grading 刪除時相關事件由 FK cascade 移除。

使用 PostgreSQL trigger 覆蓋 `update_columns`／`update_all` 等不經 Rails callbacks 的路徑。不改寫原狀態、不觸發新工作、不保存原始錯誤內容。這是新增少量同步 DB 寫入，不應宣稱對 DB 完全零成本。

事件使用 `timestamptz` 和 `clock_timestamp()`，保存實際事件時刻而非 transaction 開始時間。Rails 事件欄位及原生 SQL 時段條件使用帶 offset 的值，避免 Rails local 與 DB UTC 造成八小時偏差。不更改既有業務時間欄位。若曾安裝早期草稿 migration 且有無時區事件，hardening migration 會停止要求工程師先核實原時區，不猜測、不刪除歷史。

重跑清除 meta 不再抹去這些新事件。已經被舊版清掉的錯誤不會復原，也不回填假的完成时间。

首次正式提交至首次 graded 的耗時包含等待／重試。後續編輯不改耗時，後續主動重跑不是新的學生提交。舊紀錄没有提交事件只能依 created_at 統計，會明確列出這部分數量；沒有可信完成事件不計入平均，不用 updated_at 替代。

統計狀態是報告產生時的快照；補寄報告可能反映截止點後的恢復，不能當成歷史時點還原。

## 郵件防重及失敗處理

`operations_report_deliveries.period_end` 唯一索引＋row lock：同一時段只有一個工作能 claim 發送。報表查詢／渲染失敗可安全重試，不會寄出假的全零報告。寄送前記為 delivering，SMTP 回應成功後記為 sent（代表傳輸接受，不保證使用者收件匣收到）。

SMTP 中斷記為 unknown，不自動重寄；程序在 claim 後崩潰則保持 delivering。後續報告將 unknown、build_failed、超過十五分鐘的 delivering 置頂提醒工程師核對。這採避免重複寄送策略，不能聲稱 exactly-once 收件；發信系統本身全掛時仍需外部監察。

現有停止／人工確認郵件也有獨立 `essay_generation_notifications` 寄送紀錄。其 build_failed、unknown、長時間 preparing/delivering、及沒有送出通知的終止任務會進入報告。這不是另一套郵件供應商，仍沿用原 mailer/SMTP/收件人。

## 部署步驟（工程師執行，尚未在 production 執行）

1. 備份 DB，核對正式 web／worker 版本，排除未完成 Listening 修改。先完成前置 generation migration `20260911143000`。
2. 在核准維護時段執行報告 migration `20260912001000`、恢復 migration `20260912030000` 及寄送 hardening `20260912040000`。核對 DB／Rails 時區及實際事件時間；不要改歷史成績。完整版本不能只裝其中一個 migration。
3. 若新資料庫是用 `db:schema:load` 建立，Ruby schema **不包含 trigger**。必須執行 `bundle exec rake operations_reports:install_triggers`。它只安裝這兩個 trigger，不回填、不寄信。報告程式會驗證 trigger 存在且啟用，缺失時拒絕生成正常報告。
4. 配置現有 SMTP／收件人，及報告 worker 環境：
   - `AI_ENGLISH_REPORTS_ENABLED=true`
   - `AI_ENGLISH_REPORT_WORKER=true`（僅 dedicated report worker 設定，主 worker 不設定）
   - `AI_ENGLISH_REPORTS_ENABLED_AT`＝實際核准啟用時間，ISO 8601 並包含時區，例如用實際日期加 `+08:00`，不要照抄測試的未來時間。
5. 執行唯讀 `bundle exec rake operations_reports:check`。這只核對表／trigger／開關／時間及收件人是否有設定，不驗證 SMTP 密碼或收件匣。
6. 以現有部署系統新增單一報告 worker：`bundle exec sidekiq -e production -C config/sidekiq_operations_reports.yml`，共用同一正式 DB／Redis／SMTP 設定。不要執行主 worker 的 quiet/stop 來啟動報告功能。
7. 確認 log 出現 `Scheduling ai_english_operations_report`（只有 `Schedules Loaded` 或啟動 tick 不足以證明已註冊週期任務）；確認只監聽 operations_reports、concurrency 1。
8. 用核准測試時段驗收一封實際郵件、收件人、紅色置頂區塊、連結及 sent 紀錄；核對下一次 00/12/18 時段。未取得實際收件確認前，不標示啟用驗收完成。

停用：報告 worker 設 `AI_ENGLISH_REPORTS_ENABLED=false` 後重啟，或只停止獨立報告 worker。排隊中的報告 job 也會檢查開關。保留資料表／事件供核對，不為停用而刪除學生資料或重跑批改。

## 本地驗證

- 報告專項 21 tests / 81 assertions 通過。
- 合併既有批改、重試、併發、JSON、分數及權限回歸：122 tests / 952 assertions 通過。
- 複製 Ruby schema 的平行測試 DB 必須補裝 trigger，測試已加入相同的安裝步驟；沒有關閉事件檢查。
- migration 只在已配置的 loopback 隔離測試 DB 執行。曾遇該 DB 既有 Listening migration 登記不一致，沒有修改 Listening；改用本次 migration 的 targeted up 完成驗證。
- SMTP 使用 test transport／受控失敗，不曾寄正式信；Dify 沒有被呼叫。
- 使用專用 loopback Redis 和隔離測試 DB 啟動實際 concurrency 1 報告 worker。確認排程註冊，並於 2026-09-11 澳門時間 23:55 自動觸發 tick；不是只手動呼叫方法。
- 額外實際入隊一份固定時段報告，完成查詢、兩種郵件渲染及 test transport 傳送，DB 紀錄為 sent。這只是本地傳輸驗證，並未連正式 SMTP。測試 worker／Redis 隨後停止。
- 啟動實測曾發現僅 `set_schedule` 並不足以載入記憶體排程；已補 `Sidekiq.reload_schedule!` 再重載 scheduler，保留其他排程且 dedicated worker 只排其監聽 queue。
