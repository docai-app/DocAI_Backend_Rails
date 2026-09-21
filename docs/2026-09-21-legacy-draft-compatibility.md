# 歷史多草稿相容修復

日期：2026-09-21。Backend-only；正式發布結果見末節。

## 原因與行為

舊版可能已建立同一學生、同一作業的多份草稿。原本 `AssignmentDraftSession.current` 在看到兩份時一律拋出衝突，連帶讓明確指定 ID 的保存／提交也被拒絕；model callback 同時禁止更新這類既有 draft。

按使用者要求移除以上限制：

- 明確開啟哪個 grading ID，就保存／提交該筆；另一份答案、录音及狀態不變。兩份可以各自完成，不自動合併、刪除或替學生提交。
- code／老師派發入口沒有指定 ID 時，按 `created_at ASC, id ASC` 沿用最早的 draft，避免每次選擇不同或另建第三份。
- model 仍禁止新增重複 draft，以及普通寫入將已提交紀錄改回 draft。Admin 改回 draft 仍不能新增重複草稿。
- 學生／作業歸屬、同一學生＋作業鎖、revision、request_id 精確重送及已提交狀態檢查全部保留。managed draft 仍不接受缺版本寫入。
- 不改評分、音檔上傳、queue、排程或學年篩選；不需要前端改版或 migration。

現有前端 `useAssignmentDraft` 在收到明確 initial draft 時直接使用該 ID；只有 code 入口才呼叫 prepare，因此可直接配合這次後端修改。

## 驗證

本地隔離 Rails DB（127.0.0.1 的 test DB），Sidekiq fake、ActiveStorage test disk。沒有操作正式學生作業，沒有真實 Dify／Azure 呼叫。

執行 `assignment_draft_lifecycle_test.rb`、`assignment_draft_concurrency_test.rb`、`assignment_audio_preparation_test.rb`、`admin_grading_override_test.rb`：**56 tests / 801 assertions，0 failures、0 errors**。

覆蓋九種作業各自保存／提交兩份歷史草稿、十題發音錄音保留、另一份草稿完全不變、第三份草稿建立被拒絕、跨學生拒絕、重送／舊版本拒絕、Admin 與音檔上傳保護。真實獨立 DB 連線競爭測試包含 10 輪新草稿及 10 輪歷史多草稿的並發操作。拼句歷史草稿 fixture 按舊 controller 行為排除提交計數；提交後各計一次。

## 發布與回退

開發修復 `43bbf100044d7320d9affcc45f1772cf12494b0c` 已交付至 Backend `development`。由於 development 另有未批准本次上線的 Admin supplement 變更，正式發布從原版本 `9a482cb` 僅 cherry-pick 此修復，形成 `041a3215ca341e1401089f58d2ba90b5608eb024`，先推 GitHub `codex/legacy-draft-production-release`，再部署精確 SHA。

正式發布只取本次修復 commit，核對和當前版本的差異；兩個 runtime 檔案為 `app/services/assignment_draft_session.rb`、`app/models/concerns/assignment_draft_guard.rb`。無 migration、無學生資料修補、無舊草稿清理。按既有 web／三個 workers 安全切換流程，保留 Redis 與啟用時間。

部署後先唯讀確認兩份仍完整、current draft 可正常返回，使用隔離驗收帳號測試保存／提交；不替真實學生提交。回退此次應用修改會再次阻擋多草稿，但不要刪除錄音、答案或版本回執。使用者已於本次明確授權 push GitHub 及 deploy 至正式伺服器。


## 正式發布驗收（2026-09-21）

- 正式主機 `43.228.217.157`，checkout `/home/akali/aienglish/DocAI_Backend_Rails`，由 `9a482cb42bccefdad4d3cace5bee22faad591898` fast-forward 至 `041a3215ca341e1401089f58d2ba90b5608eb024`。沒有推送 GitHub production 分支。
- 精確發布組合再次在本地隔離 DB 通過 56 tests／801 assertions。相對正式起點僅兩個 runtime Ruby 檔案、兩個測試及協作／交接文件變更；無 Gemfile、migration 或資料庫結構變更。正式唯讀 migration 檢查 pending=false，沒有執行 migration。
- 主 worker／reports／recovery 先 TSTP；確認三個 quiet=true、busy=0 後才停止並切換。19:32:13（澳門時間）web 及三個 worker 重用原容器啟動；四個容器的環境摘要 hash 與切換前一致，reports／recovery 啟用時間未變。
- Redis ID／啟動時間維持不變（2026-09-20T10:34:39Z），沒有重啟、清空或公開 6379。未操作其他服務、未重建 image、未清 queue、未批量 rerun。
- 正式首頁及 login HTTP 200；未登入 grading API 401；兩份驗收個案的登入後 detail GET 均 HTTP 200，返回各自正確 ID 與十題資料。JWT 僅記憶體使用，沒有保存或輸出。
- 切換前 current draft 會拋出多草稿衝突；切換後可正常返回最早的既有草稿。切換後第一輪唯讀比對兩份完整 attributes 摘要與切換前相同。
- 隨後於 19:33:06，較新一份由正常寫入流程轉成 graded、revision=1，十段錄音仍齊全，stored score／前端共用 metrics 顯示均為 91；驗收程序只執行 GET／唯讀查詢，没有替學生保存或提交。另一份仍 draft，完整 attributes 摘要與切換前一致。不能把這次正常提交造成的內容摘要變動說成部署修改資料。
- 啟動後 web／三 worker 沒有 ERROR／FATAL 日誌，restart_count=0；三 worker quiet=false、busy=0。獨立 watchdog timer active，排程健康 healthy=true；reports／recovery 的啟動 tick 於 19:32:32／19:32:31 完成，recovery error_count=0。
- 19:35 首次重啟後定時 tick：reports 19:35:03、recovery 19:35:01 均 completed，error_count=0；19:35:14 排程健康 healthy=true，兩角色各有一個正常 worker，issues 為空。
- 前端產品程式、Vercel 及總 Admin 都沒有在本次部署；前端本機只同步本文件及 AGENTS.md 的歷史草稿規則。

回退 SHA：`9a482cb42bccefdad4d3cace5bee22faad591898`。若需要回退，仍須安全 drain 三 worker、同步切換 web／workers，保留 Redis、runtime 與草稿；回退會重新出現舊多草稿阻擋。本文後續文件 commit 不表示伺服器程式版本已變動。
