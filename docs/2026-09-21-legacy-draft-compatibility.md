# 歷史多草稿相容修復

日期：2026-09-21。Backend-only；程式交付不代表已正式部署。

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

交付至 Backend `development`；本次未部署正式環境、未寫入正式學生資料。正式目前另有未發布的 Admin supplement 變更，不能把整個 development 當成本次已批准發布範圍。

正式發布只取本次修復 commit，核對和當前版本的差異；兩個 runtime 檔案為 `app/services/assignment_draft_session.rb`、`app/models/concerns/assignment_draft_guard.rb`。無 migration、無學生資料修補、無舊草稿清理。按既有 web／三個 workers 安全切換流程，保留 Redis 與啟用時間。

部署後先唯讀確認兩份仍完整、current draft 可正常返回，使用隔離驗收帳號測試保存／提交；不替真實學生提交。回退此次應用修改會再次阻擋多草稿，但不要刪除錄音、答案或版本回執。正式部署須取得本次明確授權。
