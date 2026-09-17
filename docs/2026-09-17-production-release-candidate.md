# 正式部署補完候選版與當次前置檢查

2026-09-17，澳門時間。使用者本次明確授權正式部署，但 migration 只核對不執行、歷史 pending 不批量重跑。**目前只有候選版整理及測試，尚未切換正式服務。** 精確提交SHA以GitHub交付回覆及Git log為準；推送development不是正式已部署。

## 乾淨候選版範圍

基於GitHub `development` 的 c56718685ade416fb9a3a16214cdcecaff3b4837，已包含管理API／Sidekiq安全修正9f81058。另合入：

- 普通 update 鎖內禁止非draft改回pending/draft，文字／整数狀態均檢查。
- 總Admin獨立單筆／批量Rerun可以替代先前任務；舊token不能寫入，保留學生補充練習答案。外部呼叫不保證取消，可能重複計費，不能讓學生或自動恢復使用此覆蓋入口。
- Admin-only generation診斷序列化，預載關聯；不輸出provider憑證或原輸出。
- 恢復scanner心跳及唯讀 `aienglish:recovery_status`，含逐筆錯誤計數。
- 對應回歸與文件。

**沒有合入 ComprehensionDraftSession／revision／新草稿入口，沒有新增migration、Listening功能、微信小程序或其他repo代碼。** 原工作區未提交內容仍保留。這是針對部署風險分拆，不代表那些其他功能已完成發布。`2026-09-17-pending-prevention-and-admin-status.md` 描述原本本地整套實作，本候選版排除草稿功能的範圍以本文件為準。

## 候選版測試

乾淨worktree使用明確隔離本地PostgreSQL：175 tests／1689 assertions，全通過，seed4819。包含 Admin API/Sidekiq驗證、generation可靠性／恢復競爭、Admin覆蓋、防狀態倒退、報告、作業摘要及Comprehension滿分計算。沒有正式Dify、SMTP或學生資料寫入。無migration/schema差異。

## 本輪正式只讀證據

- SSH已用使用者本次提供的資料成功登入；密碼未存檔／入Git。不要使用歷史對話提取密碼的舊輔助工具。
- 正式checkout為production，94c1210ce67f0470b7bd221d81193ed497c11794；web與主worker使用同一source bind mount，必須安全停領新工作、drain後才換碼，避免舊程序讀取新文件。
- 四個指定migration皆已記錄；四張public表存在；`OperationsStatusReport.verify_capture!`通過；事件時間型別為timestamp with time zone。未執行migration或trigger寫入。
- 單一主Sidekiq concurrency6，包含default及原有其他queues；檢查時busy0、default queue0、scheduled0、retry0、schedules空。這是瞬時狀態，切換前必須重新查。
- 沒有報告／恢復專用worker及排程。報告寄送紀錄為空。
- Redis已使用持久化volume；不得down/up替換或清除。正式compose和圖片／其他服務不屬整機重建範圍。
- Rails載入ADMIN_TOKEN；Sidekiq獨立帳密缺失。SMTP必要設定存在、delivery開啟；ADMIN_NOTIFICATION_EMAIL未明確設定，使用Bobby.lian@docai.net預設。未寄信／未證實收件。
- 現場有未追蹤ARIAL字型檔，保留。其他QG、Listening、IBKR服務不動。
- 正式DB約18.45GB、PostgreSQL13.23；可見備份目录只有9/13事故資料，不是完整DB備份或還原證據。應由工程師提供現行完整備份／還原證明或核准相符備份方式，不把小型JSON檔當完整備份。
- 当前Vercel帳號 info-1802 所屬 infom2mdacoms-projects 已列完27個專案；可見學生／老師frontend，但未見正式總Admin專案。不能因此更改其他project或假設ADMIN_RAILS_TOKEN已配好。

## 切換前阻擋項

1. 取得正式總Admin Vercel project存取或工程師同步協助，核對並輪換 `ADMIN_RAILS_TOKEN` 與 Rails `ADMIN_TOKEN`，盤點其他合法消費者。不可只部署Backend導致管理頁失效，也不可接受Bearer null維持相容。
2. 確認完整DB備份及還原準備、Sidekiq獨立帳密交付、入口網路／速率限制，以及正式回退方案。
3. 候選SHA先在GitHub可追溯，發布前再fetch核对无远端冲突；不force push。正式切換同一SHA，記錄web/worker與遠端一致，不能只看檔案checkout。
4. 開關與實際+08:00啟用時間只設定到對應專用worker，不倒填。按附件啟動兩個worker，觀察各至少兩次五分鐘tick。主worker保留原queues及其他服務。
5. 正常批改／原Dify GET、真實管理登入、學生老師流程、SMTP實際收件及三個時間邊界需實際驗收。無候選只證明scanner執行，不證明恢復成功。

完整步驟及第12節回覆格式見 `2026-09-16-production-completion-handoff-zh.md`。目前該節的部署時間／正式新SHA、token輪換、worker啟用、排程tick、正常批改及真實收件仍為未完成；migration／表／trigger核對已完成。歷史pending沒有重跑，未修改正式配置、未quiet/停止主worker。
