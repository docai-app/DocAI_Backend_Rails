# 本學年異常報告及語音提交連線修復 — 2026-09-20

## 行為

使用者要求不再處理上一學年 stopped／pending。`CurrentAcademicYearGradings` 在 SQL 篩選後才套異常清單上限；各校 active 學年為準，不硬編 2026-2027、不用建立日期猜測。submission_academic_year_id 優先，只有缺少快照才使用 assignment.school_academic_year_id。沒有可確認學年的 pending／stopped 只列總數提醒；archived／preparing 不列。沒有刪除紀錄、修改狀態或重新批改。

同一範圍套用作業 stopped／長 pending／generation 異常及相關通知異常，避免舊作業經其他提醒路徑再出現。報告的當期新增作業、提交及事件統計維持原定義；報告本身的寄送健康、Redis／worker watchdog 不按學年隱藏。郵件顯示範圍說明。

`ops/reliability/pending_audit.rb` 仍唯讀：總 pending、當年、排除及無歸屬數量分開輸出，逐筆 queue 稽核只列當年。上一輪 163 筆是 9 月 19 日快照，不能當作今天數字，也未證實全部屬於上一學年。

## 語音答案的併發

Preset Speaking answer 原本在 DB transaction／學生＋作業 advisory lock 內上傳。現在先在短鎖中驗證，再釋放連線上傳，最後在原協議下重新鎖定驗證才寫入。中間若有新版保存或已提交，返回 409，不覆蓋。不同 pool checkout 恢復原 search_path 並清理 query cache。prepare 不允許外層 transaction，防止假裝釋放了仍在使用的交易。

已完成的同 request_id 重送跳過上傳及寫入；相同 key 不同內容仍 409。缺少 answered_at 時只在真正保存時補伺服器時間，不讓每次請求的時間改變 fingerprint。上傳回傳空值視為未確認，回 500 且不增加 revision，前端可按既有同 payload 重送規則處理。

ActiveStorage fallback 的 blob metadata 以短 checkout 保存，上傳在 checkout 外完成。保留原 bytes／URL 行為。沒有 schema／migration、新 queue 或 worker 併發設定變更。

限制：同時在途的相同請求可能各自上傳檔案，但只一個版本提交成功；失敗／衝突可能留下未被答案引用的儲存物件，本次不自動刪除它們。一般附件、Speaking Essay 及其他語音生成路徑不因此被宣稱已全面移出 transaction。外部 Azure 延遲、Puma／DB／Dify 正式吞吐量仍需獨立驗收。

## 驗證

在 127.0.0.1:55439 的 listening_rails_isolated_test（test-only 開關）執行：

```sh
LISTENING_RAILS_ISOLATED_TEST=1 RAILS_ENV=test PARALLEL_WORKERS=1 bundle exec rails test test/integration/assignment_audio_preparation_test.rb test/integration/assignment_draft_concurrency_test.rb test/integration/assignment_draft_lifecycle_test.rb test/integration/operations_reporting_test.rb test/integration/essay_generation_recovery_health_test.rb test/integration/essay_generation_reliability_test.rb test/integration/essay_generation_recovery_edges_test.rb
```

97 tests／823 assertions 通過（新增郵件文案斷言後另重跑 reporting）。包含真實 HTTP、不同 DB 連線競爭、6 個模擬慢上傳超過 5 個 pool slots 而頁面查詢仍成功、上傳失敗後重送、上傳期間新版寫入、租戶路徑恢復及 ActiveStorage 實際檔案 bytes。外部 Azure/Dify/SMTP 不發送真實請求；郵件使用測試投遞。

## 交付與線上邊界

基準為 GitHub development `a4cb9dd`；此變更只交付 development，不 push production。本次沒有 migration，沒有改小程序、總 Admin、Listening 生成流程或 Redis 配置。

2026-09-20 本轮尝试对正式主机做只读 SHA 核查，SSH BatchMode 返回认证失败，未进入服务器、未部署、未重启。上一輪任務記錄曾回報 Redis ACL／外部封鎖、三個 worker 啟動及 00:05／00:10 兩次 tick 完成；這些是當時紀錄，不能代替本次 fresh 驗收。

正式啟用此報告篩選仍須工程師取得本次 GitHub commit 後核對分支／完整差異、無待 migration，再 quiet／drain 三個 worker，保留 Redis／原啟用時間／私有憑證，更新並重啟所有載入程式的 Rails／worker。不得用 compose down 或僅修改 bind-mount 檔案而不重啟 Ruby。核对 source SHA、四項 schedule health、登入／受權 API、下個定期報告學年範圍與實際收件；不為驗收手動重寄或製造正式學生提交。

回退本次程式需同樣協調四個應用容器，保留 Redis ACL／網路防護與資料。退回篩選前版本會重新顯示舊學年提醒；不要重設報告啟用時間／delivery state。音檔修復與舊版指紋的相容邊界：帶明確 answered_at 的既有客戶端不變；舊版伺服器自填時間的請求原本已不能可靠精確重送，不可藉回退放寬 revision。
