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

## 發布與回退（實際發布結果見下方）
正式主機 43.228.217.157，repo /home/akali/aienglish/DocAI_Backend_Rails，起點 9c2f82a。需本次明確正式發布授權，不能借用之前的授權。
1. 只讀核對 HEAD、tracked dirty、實際程序及既有 migration 狀態；本次沒有 migration。保留 runtime env、啟用時間、Redis、watchdog 狀態。
2. 對主 worker/reports/recovery 分別 quiet；核對 busy=0 才依序停止。保留服務及容器設定；不能 force-stop 在途工作。
3. 從 GitHub 取得此次修復精確 SHA，核對完整差異後 fast-forward；安全切換所有載入 Ruby 的 web／三 worker。不可 compose down、Redis restart、prune 或清 queue。
4. 確認實際啟動時間與 source 對齊；重新登記兩個排程，原啟用時間不變。驗證健康及至少兩次 tick；下次定期報告核對 summary scope/count、郵件主旨／內容與實際收件。不補寄 388 項舊報告、不主動重跑五份補充練習。
5. watchdog 每次另起 Rails runner 讀取 source，無 Python watchdog 修改，不需重設 timer 或 cooldown。
回退需要相同 drain/停止/一致版本流程，退回 9c2f82a 會恢復已知日期篩選及 running 誤報問題。不能回退 Redis 保護或變更學年設定。

## 正式發布（2026-09-21，用戶本次明確授權）

程式版本：9a482cb42bccefdad4d3cace5bee22faad591898，GitHub development 與正式 checkout 均已核對。沒有推送 GitHub production 分支。正式更新前 HEAD=9c2f82a，tracked 工作區乾淨，pending_migrations=false。

- 16:42:09 已確認主 worker、reports、recovery 全部 quiet=true／busy=0，才安全停止；沒有強制終止在途作業。
- 16:42:57–58 web 與三個 worker 全部重新啟動，source bind mount 已為上述修復版本。重用原容器／image／設定，舊 image 或 release label 不作為已載入程式版本的判據。
- 四個容器 ID、環境設定摘要雜湊前後完全相同；reports 啟用時間仍 2026-09-18T11:21:43+08:00，recovery 仍 2026-09-18T11:21:44+08:00。
- Redis 啟動時間仍為 2026-09-20T10:34:39Z，沒有重啟，6379 沒有公開端口。沒有 migration、學生資料修改、人工 rerun、補寄舊報告或調整 watchdog cooldown。
- 16:43:54 由 reports 容器內的新 Rails runner 唯讀產生報告、只渲染不寄出：alert_count=5；4 份補充練習長時間排隊、1 份結果不明。主旨及 HTML／text 計數一致。當前有效學年 pending=0、stopped=0；29 筆學年未確認紀錄維持獨立警告。
- 正式首頁及 login HTTP 200，伺服器內未登入 grading API 401；這不是學生登入／提交完整端到端測試。
- 16:44:11 排程健康 healthy=true；16:45 reports/recovery cron 均完成；16:46:34 主機 watchdog healthy=true／issues=[]，timer active；16:47 主 worker 重啟後 ERROR／FATAL 日誌行數為 0。
- 16:45、16:50 兩個專用排程均連續完成；16:50:36 最終健康檢查 healthy=true，三個 worker 均 quiet=false／busy=0，reports completed_at=16:50:03、recovery completed_at=16:50:01／error_count=0。實際下一封定期報告預計 18:00，SMTP／收件匣尚未驗收，不把渲染結果當成已寄送。

本次 AGENTS.md 的報告有效日期及健康檢查重疊規則已隨程式提交。以下完成紀錄只更新 docs，不更改產品程式。
