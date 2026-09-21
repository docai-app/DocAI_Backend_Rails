# 報告舊學年計數與排程誤報修復（2026-09-21）

## 已查明
- 09:51 正式唯讀查詢確認 00:00 郵件 summary.alert_count=388，definitions 仍是未限定學年的舊版本。18:34 更新 checkout 到 9c2f82a 時僅 web 與主 worker 重啟；reports/recovery 仍於 09-20 00:04 啟動，舊 Ruby 程序繼續建報告。模板來自新磁碟檔案也不能證明資料計算已更新。
- 09:40 watchdog 的磁碟 attempted_at=1789954801.796489；report tick 在 09:40:00 開始、約 09:40:03 完成，前後定期檢查健康。原健康條件要求 state=completed，正好在新一次 running 的幾秒內會誤報 successful_completion_stale。09:40 告警由這個時間重疊解釋；沒有關閉真正故障監控或清掉 cooldown。
- 正式有 3 個 2024–2025 學年仍 active，但 end_date 已在 2025 年。只檢查 active 無法排除舊學年。

## 修復
- CurrentAcademicYearGradings 同時要求 active 且 start_date <= 澳門當日 <= end_date。報告用 snapshot @now，不按伺服器時區、學年名稱或作業建立日猜測；提交時學年優先，缺少才用作業學年。shared pending audit 也沿用此規則。沒有改學校設定、migration 或學生資料。
- 主旨及 HTML／text 內文沿用同一個篩選後 alert_count；範圍說明同步更新。期內活動統計維持原定義。無法歸屬學年的紀錄保留獨立警告，不混入今學年待處理數。
- 健康檢查允許近期 running 與上一次近期 completed 重疊；仍要求 15 分鐘內的成功、有效排程、live worker、近期 tick。failed、沒有成功紀錄、過期 running／completion 均保持告警。
- watchdog 六小時寄送嘗試冷卻及寄送結果不明不得盲目重試的規則不變。

## 驗證
- 隔離本機 DB：operations_reporting_test.rb 32 tests／143 assertions 通過；包含 expired/future active、兩種郵件及主旨一致、日期含首尾及澳門跨日、補報使用快照日期。
- reliability_schedule_health_standalone_test.rb 7 tests／38 assertions 通過，包含 running overlap 與真正 stale／failed。
- 09:55 正式資料 READ ONLY 預覽（僅 runner 內匿名報告 subclass，未部署／寄信）：alert_count=5；4 份 supplement 長時間排隊、1 份結果不明。主旨為「需人工處理 5 項／請查看警告」。29 筆未確認學年另外警告。數量隨時間變動，不把此預覽當作已寄出的郵件。
- git diff --check 通過。無 .github workflow；development fetch 未見其他更新。

## 發布與回退（尚未執行）
正式主機 43.228.217.157，repo /home/akali/aienglish/DocAI_Backend_Rails，起點 9c2f82a。需本次明確正式發布授權，不能借用之前的授權。
1. 只讀核對 HEAD、tracked dirty、實際程序及既有 migration 狀態；本次沒有 migration。保留 runtime env、啟用時間、Redis、watchdog 狀態。
2. 對主 worker/reports/recovery 分別 quiet；核對 busy=0 才依序停止。保留服務及容器設定；不能 force-stop 在途工作。
3. 從 GitHub 取得此次修復精確 SHA，核對完整差異後 fast-forward；安全切換所有載入 Ruby 的 web／三 worker。不可 compose down、Redis restart、prune 或清 queue。
4. 確認實際啟動時間與 source 對齊；重新登記兩個排程，原啟用時間不變。驗證健康及至少兩次 tick；下次定期報告核對 summary scope/count、郵件主旨／內容與實際收件。不補寄 388 項舊報告、不主動重跑五份補充練習。
5. watchdog 每次另起 Rails runner 讀取 source，無 Python watchdog 修改，不需重設 timer 或 cooldown。
回退需要相同 drain/停止/一致版本流程，退回 9c2f82a 會恢復已知日期篩選及 running 誤報問題。不能回退 Redis 保護或變更學年設定。
