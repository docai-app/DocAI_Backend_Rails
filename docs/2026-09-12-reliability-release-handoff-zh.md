# AI English 批改可靠性、失聯任務恢復及運行郵件：工程師交接

日期：2026-09-12。請先 review，再依本文件部署；**本文件不是 production 已驗收的聲明**。

## 1. 交付範圍與版本

- Rails repo：`docai-app/DocAI_Backend_Rails`，目標 `bobby-codex-backend`。包含前一個本地提交 `e83e9b1` 的驗證／重試，以及本文件所在提交的恢復／報告／最後修正。工程師應 checkout 完整分支 commit，不只複製幾個檔案。
- Web repo：`loveson821/essay-checker`，本地 `bobby-codex`，本次 tip `346957b`。包含前一個本地提交 `ba209ed` 的 Supplementary 狀態／Retry，以及新的主批改人工確認提示。
- **使用者已確認：前端只保留本地 commit，不 push。** GitHub 有 Vercel 整合，但無法確定此分支是否自動部署。工程師先確認／安排部署設定，再要求推前端。不要因此自行關閉整個專案整合。
- 本次不部署，不跑正式 migration、不重批改正式紀錄、不改歷史分數、不寄正式電郵。Backend push 不等於 deployment。
- 不新增或修改總 Admin UI、微信小程序、未完成 Listening；保留工作區既有 Listening 變更。分支祖先本來已有 Listening commit，並非本次新加入；工程師仍須 review 完整部署差異，不能將本次排除未提交內容理解為部署版本完全沒有 Listening。

## 2. 為什麼要改

問題分為三種，不能只看 `pending/graded/stopped`：

1. Dify HTTP 成功但內容缺分數、壞題目，原本可能被當成 graded。
2. 過程失敗或 worker 遺失，原本可能沒有有限重試，或一直 pending。
3. 管理員缺少跨學校摘要；錯誤被重跑清除後、通知沒送達時，很難追查。

做法是「內容先驗證 → 有限重試 → 成功階段保存 → 結果不明先確認 → 狀態及郵件保留紀錄」，不是一律超時重跑。

## 3. 功能／程式對照

| 部分 | 主要程式 | 規則 |
|---|---|---|
| Comprehension 滿分 | `ComprehensionScoreCalculator` | 滿分由啟用題目／空格決定；漏答不減少滿分，額外答案不增加滿分。 |
| Essay 內容驗證 | `EssayFeedbackValidator` | 總分／滿分有限且合理、準則分數／解釋、句子／錯誤結構；真正沒有錯誤可通過。兼容外層反引號；拒絕錯誤訊息冒充 feedback。 |
| Supplementary 驗證 | `SupplementPracticeValidator`、parser/scorer | 檢查必要欄位、題型、選項、答案、ID；用實際計分器測試全對與空答案滿分一致。通過才 ready。 |
| 任務與重試 | `EssayGenerationRun`、`EssayGenerationJob`、兩個 grading services | 一個 grading/kind 一個 slot；token 防舊工作覆寫；最多三次；主批改與補充練習獨立。 |
| 失聯恢復 | `EssayGenerationRecoveryState`、`EssayGenerationReconciler`、`EssayGenerationQueueSnapshot`、`EssayGenerationRecoveryJob` | 兩小時後核對 queue/worker/provider，確認可安全恢復才重新入隊。 |
| 報告 | `EssayOperationEvent`、`OperationsStatusReport`、report job/tick/window | 保存事件歷史，按澳門固定時段統計，異常置頂。 |
| 郵件可靠性 | `OperationsReportDelivery`、`EssayGenerationNotification`、現有 mailer | rendering 可重試；SMTP 結果不明不自動重寄，留下需核對紀錄。 |
| Web | `gradingGeneration.ts`、既有 `FeedbackDataNotice`、Supplementary 元件 | 顯示後端狀態；只 GET 輪詢。网络錯誤不表示可以重新生成；不向學生顯示 JSON／queue 等詞。 |

驗證是**格式與計分契約**，不是判定教學內容一定正確。Essay 嚴格評分契約不等於所有類型都使用同一 rubric；其餘類型保留既有結果驗證。自訂 rubric 是否每項都齊備，仍須正式樣本核對。

## 4. 最後一輪發現並修正的邊界

- 已取回的 Dify 結果再次遺失 queue delivery：保留 terminal cache，第三次 attempt 仍可保存已有結果，不能錯當作第四次付費生成。
- 提交已 commit、還沒建立 slot 就中斷：slot 改為與提交同一 DB transaction；只在 commit 後 enqueue。Speaking Essay 等附件完成後，在同 transaction 登記。Rollback 不留下 job，`saved_changes` 不被鎖定查詢覆寫。
- Speaking Essay 音訊／最後評分的舊工作失敗：寫入錯誤紀錄也檢查 token，不能污染新工作的錯誤歷史。
- 報告漏掉「主批改 graded，但補充練習卡住」：納入 stale supplement。
- 剛重排的舊作業被誤報：改看目前 slot 的 queued/started/next_retry 時間。
- 報告日期偏移：事件用 PostgreSQL `timestamptz`＋`clock_timestamp()`；Rails bind 和原生 SQL 時段條件保留 offset。未修改既有業務時間欄位。
- 錯誤通知在送出前失敗或 SMTP 中斷無紀錄：新增寄送狀態；render 失敗不消耗發送 claim；不明傳輸不盲目再寄。報告列出需核對通知。
- 并發 render 失敗不可把另一工作已 claim 的郵件改回 build_failed：以未 claim 條件做原子更新。

## 5. 重試、排隊及保護邊界

### 適用範圍

此非同步 coordinator：Essay、Speaking Essay、Speaking Conversation、Sentence Builder、Talk Lab Speaking，以及 Essay 的補充練習。Comprehension、Sentence Puzzle、Speaking Pronunciation 不使用這條通用非同步重試流程。Listening 排除。

### 次數和順序

- 明確失敗：首次＋最多兩次 retry，共三次；延遲 30 秒、2 分鐘。等待時仍 pending，不先 stopped、不先寄失敗信。
- 只重跑未成功階段；第三次仍失敗，主批改 stopped；若只練習失敗，作文保持 graded。
- 自動恢復不重設 attempts；失去 delivery 本身最多替換兩次。重用已保存結果不新增付費 attempt，但也不能無限替換。
- 恢復工作使用獨立 queue；真正批改回到原本正常 queue，沒有插入隊首、清空／搬動 queue。多 worker／多 queue 不承諾全局嚴格 FIFO。
- 手動 retry：沿用已確認失敗或 queued/retry_wait 超過兩小時的規則，終止失敗後冷卻一分鐘。後端鎖與 token 保證不能與已 claim 的工作同時開始；這不等於「兩小時一定已遺失」。手動流程沒有終身次數上限。
- running/checking/unknown 不因時間直接手動重跑；已保存的 Supplementary 學生答案（包括草稿）禁止覆蓋。修復含答案的壞題目需另行處理。

### 自動失聯檢查

每五分鐘；只查啟用時間後新建、且超過兩小時的受管 slot，最多 100 個候選。兩次完整 absent observation 至少隔一分鐘。queue/busy/scheduled/retry 存在：不動；Redis 不可查或掃描超過 20,000 jobs：不把它當作 absent。

- 尚未開始 provider、或成功階段已保存：安全重排剩餘部分。
- 有原 Dify workflow ID、原 app key 未改：GET 原結果。已完成就用原結果驗證／保存；仍執行就等。
- 無法確認：`generation.state=unknown`＋`requires_attention=true`；不 POST 新生成。主紀錄可能仍 pending，但 web 提示需要老師確認，報告／现有通知列出需介入。
- Revised completion、音訊分析、最後 Speaking Essay scoring 為不透明階段；失去在途結果不能靠 GET 證實，保持需確認。已保存 checkpoint 可重用。
- 舊 pending 沒有 slot 不自動接管；啟用時間前的 slot 不批量重跑。這需要獨立稽核。

## 6. 報告與郵件

澳門 `Asia/Macau`，區間含起點、不含終點：12:00 報 00:00–12:00；18:00 報 12:00–18:00；00:00 報前日 18:00–24:00。五分鐘 scheduler 核對到期邊界；實際寄達受 queue/SMTP 影響，不是秒級 SLA。

顯示每校老師建立作業、提交數、現時 graded/pending/stopped、曾失敗／恢復、平均／中位／P95 完成耗時、可信樣本數，以及跨時段未解決異常。需介入時主旨及最上方區塊突出顯示；連向既有 Admin 和 grading 頁，不帶可直接改資料的操作連結。

提交以首次正式提交事件為準，重跑不算新提交；完成時間含排隊。舊紀錄沒有可信事件會註明，不用 updated_at 猜完成時間。學校用 assignment/submission 明確歸屬，不猜老師目前學校。資料量上限、未知歸屬、歷史缺失都顯示警告。

沿用 `ADMIN_NOTIFICATION_EMAIL`、`MAILER_FROM` 及現有 SMTP。未設 recipient 時沿用既有預設，工程師必須核實實際群組／收件人。沒有加入另一個 email provider。

同一時段只有一個傳送 claim；同一 terminal token 同一類型通知也只 claim 一次。render 失敗可安全重試；SMTP 接受後記 sent，**不代表收件匣確認收到**。SMTP 中斷或 claim 後程序中斷不自動重寄，後續報告提示工程師核對。DB、Redis、SMTP 整體中斷仍需要獨立外部監控。

## 7. 部署前檢查清單（工程師必做）

1. 核實 GitHub branch/commit，review 完整差異，保存上線前 rollback SHA。前端先處理自動部署授權；不可把 GitHub push 當成必然不部署。
2. 備份 production DB 並確認可還原；檢查 schema、DB/Rails 時區、Redis endpoint、worker 監聽 queues。
3. **先核實既有存取控制風險**：此前唯讀檢查曾顯示 Sidekiq／一個 Admin API 未登入返回內容。此交付未改驗證機制，亦未重做線上驗證。若仍可公開存取，先由工程師限制相關入口；不得用 Quiet/Stop/Delete 等破壞性動作驗證。
4. 安排低流量切換，停止舊 worker 領新工作，讓既有 Dify 工作完成。不要強制 kill 在途 provider call。不要讓新舊 writer 同時處理同一批紀錄。
5. 遷移完成才啟動新版 Rails web／主 Sidekiq。先保持新報告／恢復開關關閉，完成基本 smoke test。

### 必要 migrations

依序 `20260911143000`（generation slots）、`20260912001000`（事件、報告、triggers）、`20260912030000`（provider journal／恢復欄位）、`20260912040000`（時區檢查、通知寄送表）。即使新排程關閉，程式仍需要相關欄位／表。

工程師先執行 `RAILS_ENV=production bundle exec rails db:migrate:status` 核對待執行清單。分支祖先包含 Listening migration；**不要未 review 就一律 db:migrate 將未核准 migration 順帶執行**。必要時按核准版本執行 `db:migrate:up VERSION=...`，記錄每個結果，再核對狀態。

如果早期報告草稿已上線並收集無時區事件，40000 會停止要求人工時區核對；不要刪資料、猜 UTC 或移除保護以通過。新安裝事件本來就是 timestamptz，可正常通過。

`schema.rb` 不保存 triggers。若環境來自 schema load，需執行 `RAILS_ENV=production bundle exec rake operations_reports:install_triggers`。只恢復本功能 triggers，不補寫歷史或寄信。報告會在 triggers 缺失時拒絕生成假的正常報表。

### 獨立 workers／設定

| 程序 | 設定及入口 |
|---|---|
| 主 web／grading worker | 現有 DB/Redis/provider/SMTP；主 worker 必須監聽 `default`，保留其他原有 queue 設定。 |
| 報告 worker | `AI_ENGLISH_REPORT_WORKER=true`、`AI_ENGLISH_REPORTS_ENABLED=true`、`AI_ENGLISH_REPORTS_ENABLED_AT=<實際啟用時間含 +08:00>`；`bundle exec sidekiq -e production -C config/sidekiq_operations_reports.yml`。 |
| 恢復 worker | `AI_ENGLISH_RECOVERY_WORKER=true`、`AI_ENGLISH_RECOVERY_ENABLED=true`、`AI_ENGLISH_RECOVERY_ENABLED_AT=<實際啟用時間含 +08:00>`；`bundle exec sidekiq -e production -C config/sidekiq_generation_recovery.yml`。 |

兩個 dedicated process concurrency 都是 1；不要在所有主 workers 上重複設 dedicated worker 旗標。不要照抄測試的 activation 時間，也不要 backdate 以納入未稽核舊作業。

啟動前執行唯讀 `RAILS_ENV=production bundle exec rake operations_reports:check`（使用上述報告環境設定），確認表、事件時區、triggers、開關、時間及收件人設定存在；它不能證明 SMTP 密碼或實際收件正確。

檢查排程 `ai_english_operations_report`、`ai_english_generation_recovery` 真正註冊及下次 tick，不只看到 process running。報告補寄最多最近七天；恢復開關與報告開關互不替代。

## 8. 已做本地驗證／尚未做

- 隔離 Rails/PostgreSQL 最終合併測試以兩個次序重跑（seed `12092026`、`9122026`）：每次 198 tests / 1,573 assertions，零失敗／錯誤／skip；涵蓋生成、真實 DB 併發、恢復、分數、Supplementary API、學生派發／權限及 admin 原有權限回歸。
- 前端相關 Node 回歸 139 項；在乾淨 release 副本中另做 TypeScript、targeted ESLint 和 production build，成功。保留既有其他檔案 Hook warnings，沒有關閉檢查。
- **真正啟動 clean production build 的本地 Next server＋Chrome**：18 項 grading（desktop/mobile/embed），12 項 Supplementary（desktop/mobile），無 runtime error／橫向溢出；排隊無 Retry、失敗可 Retry、結果不明及網路錯誤不會擅自 POST。
- 前輪已實際啟動獨立 loopback Redis＋報告／恢復 Sidekiq，驗證 scheduler tick、入隊及 test transport。最終補修後重跑 DB/API/郵件受控測試；不是正式 worker／正式 SMTP 驗收。
- migration 只在隔離 test DB 執行。Provider 與郵件使用合成／受控結果，瀏覽器攔截 API 並阻擋外部流量。沒有正式 Dify sample、實際收件、physical WeChat 或 production 驗收。
- 本地測試時 SQL join 欄位未限定曾被測試抓到，已修正；時區測試使用一秒跨程序時鐘容差，仍檢查 DB UTC/Macau 及時段端點，不放寬八小時偏移問題。

## 9. 上線 smoke test 與後續交回

用明確測試帳號／紀錄驗證，不改壞正式 Dify prompt 來製造失敗：

- 正常 Essay 和各受管類型：列表、分數、Grammar、Supplementary 同步；Comprehension 漏答滿分不變。
- 在隔離環境控制無分數／壞題目：最多三次；成功階段不重跑，僅最終通知。正式環境只做已核准正常小樣本。
- queued/running 超過門檻仍可在 queue／Dify 找到：不得產生新付費 request。
- 確认掉隊：兩次 absent 後恢復；舊 token 無法保存；原結果已完成則重用。
- unknown、壞 exercise 有草稿答案：不提供危險 Retry，不覆寫答案。
- 正式郵件實際收件、收件人、時間範圍、置頂紅色提示及連結；不要只以 DB sent 當作收件驗收。
- 非授權老師／學生仍不能取得他人資料；owner/shared/admin 維持既有授權。

請部署後提供：frontend/backend commit、部署時間、四個 migrations 狀態、兩個 worker/排程啟用狀態及 activation 時間、核准測試 grading ID、郵件實際收件結果。收到後可再做部署後唯讀核對；需要重跑／改正式資料時再取得明確授权。

## 10. 停用／回退

先將相應 ENABLED 設 false 並停止該 dedicated worker；queued tick 也會檢查旗標。主 grading 的已啟動工作仍須正常 drain。若切回舊版，先確認沒有新版在途工作；不要新舊混跑。

保留新增表、provider journal、事件與學生答案供稽核；不以 DROP 表、清 queue、批量 rerun 作為回退捷徑。恢復功能不自動修正舊 Comprehension 分數，也不自動收拾上線前全部 pending。

詳細規格：[生成可靠性](2026-09-11-grading-generation-reliability.md)、[失聯恢復](2026-09-12-pending-recovery.md)、[報告／郵件](2026-09-12-operations-email-reports.md)。
