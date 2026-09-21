# 五份補充練習逐筆修復（2026-09-21）

## 授權與範圍
使用者於本任務明確要求修復先前查出的 5 份補充練習。只處理指定 allowlist；不重新批改主作文、不處理其他歷史 pending、不修改學年設定或資料庫結構。正式 checkout 為 9a482cb42bccefdad4d3cace5bee22faad591898；沿用既有 EssayGenerationReconciler／token fence／正常 worker，沒有新程式部署。

## 修復前核對
- 16:56 逐筆查核：五份主作文皆 graded、補充練習答案紀錄皆為 0、沒有有效練習題目；queue 均未見對應工作。
- 四份 queued 任務 attempts=0、started_at 為空、provider_context 為空；未開始過生成，且符合恢復条件。
- 一份 unknown 任務 attempts=1，保留 workflow run ID、provider key digest。用既有 key 對原工作做 GET，17:00 前已確認 succeeded 且原輸出通過 SupplementPracticeValidator；没有為這一份再發生成 POST。
- 操作前在正式伺服器私有權限檔保存指定 ID、run token 和主作文內容指紋；不包含作文原文、題目、學生身份或密鑰，不入 Git。指紋覆蓋 grading 以外各欄位（排除 updated_at），以及 grading 中除 supplement_practice 外的內容。

## 執行
- 16:58:45–56 第一次透過既有 reconciler 記錄缺失觀察。
- 相隔超過一分鐘重新取得 bounded queue snapshot；逐筆再確認 token/state、主作文指紋、graded 狀態及無既有練習答案。
- 第二次 reconciler 按行鎖／token fence 恢復：四份重新入隊，recovery_count=1；原結果已成功的一份將 terminal 輸出帶回 queue，resume_pending=true，沿用原 attempts=1。
- 所有題目都由正常 worker 走既有輸出驗證／保存流程；没有手寫或捏造題目、分數或生成成功狀態。

## 實際驗收
17:01:58 澳門時間：
- 5/5 state=ready、主作文 status=graded、failure_code 為空。
- 每份 15 題；SupplementPracticeValidator 及學生版 parse_for_student 均通過。
- 5/5 主作文指紋與操作前相同，答案紀錄數與操作前相同。沒有動分數、主批改內容或學生答案。
- 四份首次生成各 attempts=1；原結果恢復的一份 attempts 仍為 1。完成時間分別介於 17:01:07–17:01:35。
- 正式資料重新計算 OperationsStatusReport：alert_count=0，這五項已不再列入異常清單。
- 29 筆未確認學年 pending／stopped 仍屬獨立資料歸屬警告，不是這五份補充練習問題；未擅自刪除、歸檔或重跑。
- 本次只驗證正式資料、學生版解析及報告計算，沒有冒用學生登入或代學生提交練習。實際下一封定期郵件尚未驗收；沒有額外寄信。

本次沒有程式碼或持久工作規則變更，因此不修改 AGENTS.md；僅把本次授權修復與驗收紀錄同步 GitHub。
