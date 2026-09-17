# 防止提交倒退、恢復 worker 及 Admin 狀態交接

日期：2026-09-17（澳門）。涉及 Backend、學生／老師 frontend、總 Admin frontend。

## 狀態與發布範圍

本輪為本地修改，未 push／部署，沒有新 migration、正式資料修改或寄信。dev／production 的恢復 worker 尚未在本輪啟用；需先確認目標環境。隔離本地排程已實際驗收，不能當成正式啟用。

工作區另有 Comprehension、Admin Rerun、Listening 等先前改動。請分清差異，不可整包提交／發布。Backend 交付分支為 development；其餘 repo 核對分支及自動部署相依。配套共享 Confirm／Button 修改不可漏交付。

## 改了什麼及原因

### Backend 普通更新保護

`Api::V1::EssayGradingsController#update` 在 transaction 中鎖定並重新讀取 grading，再判斷狀態。原本是 pending／graded／stopped 時，普通更新要求 draft／pending 會返回 409，不寫答案、不建立批改工作。涵蓋文字及整數 enum，避免數字輸入繞過。這解決舊頁面或較晚請求把已提交紀錄改回等待處理的缺口。

Comprehension 優先沿用專用 revision／request 去重流程；Admin 主批改 Rerun 仍走 `request_admin_rerun!`，不會誤封。未要求倒退狀態的 metadata 更新不因此全面禁止。沒有新增學生「重新作答」入口或改變既有另開新一次的政策。直接 SQL、其他專用入口或舊版服務不等於受此 HTTP guard 保護；不可混跑舊 writer。

共用 guard 也可能先於 Listening 原保護返回 409（原部分情況為 422），未放寬限制、未加入 Listening 恢復功能；呼叫方需驗收 409 提示。沒有修改 Listening 專用功能。

### Sentence Builder 同步提交鎖

`SentenceBuildingForm` 在首次 await 前設 ref 鎖，確認視窗等待結果；成功後鎖定直到離開。雙擊、舊確認 callback 不能重送。載入的非 draft 紀錄唯讀。embedded draft 保存返回的 grading ID，之後更新同一筆。

未知網絡結果／409／5xx 保留答案並停止重送，提示到 dashboard 核對；已明確拒絕的其他 4xx 保留答案，可修正後再試。背景刷新不覆蓋輸入，父元件按 assignment／grading identity 設 key。沒有自動保存，也沒有跨 reload／跨裝置的新建請求持久去重，不能宣稱解決所有新建重複紀錄。

交付時必須核對先前未提交的 ModalContext `waitForSave`、Confirm `waitForResult`、ConfirmUI 和 native Button 修改；不能漏掉，也不能順帶整包發布其他改動。前端詳見同 repo `docs/2026-09-17-sentence-builder-submission-lock.md`。

### Admin 真實處理狀態

下列 Admin-only API 增加 `generation`／`supplement_generation`：pending_or_stopped、grading show、assignment submissions。共用 `Admin::EssayGradings::GenerationStatus`；列表預載 generation 關聯。

只輸出 state、stage、failure_stage、failure_code、attempts、requires_attention、recovery_count、檢查／完成時間、resume_pending 等安全診斷；不輸出 provider context、key／digest、原始輸出或工作流 ID。舊錯誤 metadata 非物件也不讓列表壞掉。

Admin 的 pending/stopped 清單及 assignment submissions 表格共用 `GenerationStatusCell`，明確區分「結果待確認」、排隊、處理中、等待重試；列出失敗階段、人工檢查、恢復次數與澳門時間的最近檢查。任務終止但提交仍 pending 顯示「狀態需核對」。沒有舊 metadata 時說明未提供狀態，不假設仍在排隊；錯誤欄不再只留空。診斷不是重跑授權或寄信證明。

Admin `tailwind.config.ts` 要包含 components/grading，避免正式建構漏樣式。API 已提供 supplement_generation，但本輪沒有另做補充練習狀態專欄。認證機制未變。

### 恢復 worker 可驗證性

保留已有五分鐘掃描、兩小時門檻、兩次完整 absent 觀察及 token fencing。本輪加 Redis 心跳（24 小時有效），含 started／completed／failed、checked_count、error_count；逐筆異常為 completed_with_errors，整輪失敗為 failed。只記錯誤類別，不記學生內容／憑證。

新增唯讀檢查：

```sh
bundle exec rake aienglish:recovery_status
```

核對 schedule_registered、worker_count、heartbeat、recent_successful_scan；舊心跳欄位可能保留，應以最新 state／時間為準。心跳不是個別 Dify 恢復成功證明，也不取代外部監控。

## 恢復邊界

- 仍在 busy／queue／scheduled／retry：不重跑、不插隊。Redis 觀察失敗不能當成空 queue。
- Dify 已完成：GET 原結果，經既有驗證及保存接續，不重 POST 該階段。
- 結果未知、缺 ID、key 改變或不支援查回的階段：需要人工確認，不盲目付費重跑。
- 保留成功階段、重試預算及學生補充練習答案；一般確認失敗仍是首次加兩次重試。
- 只掃啟用時間後建立的 tracked run；舊 pending 不會自動全部修好。
- coordinator 範圍：Essay、Speaking Essay、Speaking Conversation、Sentence Builder、Talk Lab Speaking。Comprehension／Sentence Puzzle／Speaking Pronunciation 不屬同一 coordinator；Listening 排除。不是所有 Dify 呼叫都能 GET 原結果。
- 完整階段、預算、通知及排隊規則見 `2026-09-12-pending-recovery.md`。Admin 強制重跑的獨立風險見 `2026-09-17-admin-grading-rerun-override.md`。

## 工程師啟用步驟

1. 整理 scoped diff、測試、GitHub commit／回退 SHA，排除未驗收 Listening 等修改。協調 frontend/Admin 自動部署相依。本文件不授權 push/deploy。
2. 核對目標 DB／Redis、備份及既有 migration：20260911143000、20260912001000、20260912030000、20260912040000。本輪不新增 migration；若前置缺失或不確定，停止，由工程師處理，不讓 AI 遷移／部署。
3. 舊 worker 先停止領新工作、等在跑工作完成，再換相容 web／workers；不強制終止 Dify 呼叫。
4. 專用恢復程序設定 AI_ENGLISH_RECOVERY_WORKER=true、AI_ENGLISH_RECOVERY_ENABLED=true、AI_ENGLISH_RECOVERY_ENABLED_AT=實際 ISO8601 啟用時間（+08:00）。不可倒填。沿用對應 DB／Redis／Dify 憑證，secret 不入庫。
5. 工程師在已核對的目標環境，以 supervisor 啟動 `bundle exec sidekiq -e production -C config/sidekiq_generation_recovery.yml`，設重啟管理；主批改 worker 繼續監聽 default。不要在未知環境直接複製執行。
6. recovery_status 確認獨立 queue、cron `*/5 * * * * Asia/Macau`、startup 及下一次 tick 都有新心跳。只看到程序或註冊排程不算通過。
7. 專用測試紀錄驗收原 Dify GET、驗證及存回、舊 token 防寫、權限、主 queue 消費及現有通知實際收件。受控失敗／掉隊測試用隔離環境，不改壞正式 Dify。
8. 回退時關閉掃描並安全停止專用程序，保留 journal／答案／表；不清 Redis、不批量改 status。已入主 queue 的工作另行核對，停 scanner 不會取消它們。報告 worker 獨立，本輪未啟用。

## 本輪驗證

- Backend：110 tests／994 assertions，全通過（最終 seed 65314），涵蓋 enum 防繞過、狀態保護、Admin Rerun、恢復競爭、草稿並發、序列化防洩漏及心跳錯誤。真實隔離 PostgreSQL，Dify／郵件為替身。
- Frontend：10 DOM tests；真實 Form／MUI／Modal Provider／Confirm 於1280／390瀏覽器18項。Admin：5規則tests；真實狀態元件及正式Tailwind於1440／390瀏覽器14項。登入與API為假資料，不是整個正式頁面聯調。
- 兩前端 TypeScript、相關 ESLint通過；未執行整產品 production build／真實帳號驗收。
- 真實 Sidekiq 7.3＋專用 loopback Redis＋隔離 DB：15:47 startup、15:50 cron 入隊／完成；新版計數重啟後15:56 startup、16:00 cron完成。cutoff刻意排除既有資料，未呼叫正式 Dify／寄信。
- 全 repo UI 靜態稽核仍有 frontend80／Admin20個其他元件或既有檢查項，未順帶重構；本次 SB upload／generation 元件無命中。不能宣稱全站無 bug。

沒有修改小程序。各客戶端收到新409的實際體驗、dev/prod啟用、原結果恢復、SMTP收件仍需正式驗收；沒有清除歷史重複紀錄或批量重跑 pending。
