# Redis／排程健康／pending 稽核交接（2026-09-19）

## 範圍與禁止事項

只處理 AI English Rails 的 Redis、三個 Sidekiq worker、Rails web、報告及恢復健康檢查。沒有 migration、資料表變更、Listening／總 Admin／小程序修改。不要執行原 deploy.sh、compose down、FLUSHALL、FLUSHDB、volume prune；不要批量重跑歷史 pending。

## 已確認問題

- 正式 Redis 曾公開 6379、default user 無驗證，指令統計有 6 次成功 FLUSHALL。這不代表已確認執行者或時間；Redis 指令統計不能證明攻擊來源。
- 排程 registry 消失，但既有 worker 的記憶體排程仍可觸發；因此「容器活著／最近有 tick」不是完整健康判定。
- 23:40 澳門時間只讀稽核：163 筆 pending，全部無 generation run；沒有 9 月 17 日之後建立的 pending。這批歷史紀錄不能推定為此次掉隊，不直接 rerun。私有稽核檔留伺服器，不放學生資訊進 Git。
- 使用者本輪已確認收到 9 月 19 日 12:00、18:00 的正式報告。資料庫的 sent 僅表示 SMTP 接受；本項另有收件人確認。

## 實作

1. `redis_ingress_guard.py`：先保存私有證據，再只攔截 ens3 外部 TCP 6379，IPv4／IPv6 INPUT 及 DOCKER-USER。系統 service 在 Docker 啟動前套用，timer 每分鐘確認；不清空其他防火牆規則。
2. `RedisCredentials`：dotenv 之後、clients 載入前，僅在明確設定 `AI_ENGLISH_REDIS_USERNAME/PASSWORD` 才為既有 Redis URL 加驗證；不改 host、DB index。分開的其他 Redis host 會中止而非猜測替換。
3. `redis_auth_runtime.py`：兩階段私有 ACL／配置工具。prepare 建立應用與 operator 帳號、保存私有備份，應用帳號禁止 flush/config/acl 等管理命令。cutover 必須確認四個應用容器已安全停止；先 SAVE／備份 RDB，再只替換 Redis 容器，保留原 volume、取消公開 ports、從 volume ACL file 啟動。腳本拒絕重複切換；中途失敗必須先核對，不能盲目重跑。現存 compose 為被 Git ignore 的私有部署檔，工具保留其他服務設定並以有效 JSON/YAML 寫回；密鑰只存在私有 runtime／.env。
4. `ReliabilityScheduleHealth`：同時核對 schedule 定義、活躍且非 quiet worker、15 分鐘內 tick、15 分鐘內成功完成。排程缺失即不健康，即使 worker、tick 正常。
5. Report tick 新增成功／失敗 heartbeat，不更動報告時段或重送規則。
6. `schedule_watchdog.py`：獨立於 Redis 的主機 systemd timer，每 5 分鐘檢查；故障沿用 Rails Mailer／SMTP直接寄通知。私有磁碟狀態在送信前記錄 attempt，6 小時內不重複嘗試；傳送不明不盲目重寄。健康正常不寄。通知不會修復或 rerun 作業。

Redis ACL 官方規則：[Redis ACL](https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/)。採用 named user 並禁止應用執行清空指令，不能只依賴密碼。

## 發布及核對順序

所有應用／ops 程式先推 `development`，記錄 SHA；只核對 migration，不執行任何 migration。

1. 保存 private evidence，套用／持久化 ingress guard，外部 TCP 測試失敗、內部 PING 正常。
2. 對主 worker、reports、recovery 發 TSTP；核對 quiet=true、busy=0 才停止。保留原 env、activation、容器配置，不倒填時間。停止 Rails web 後才切 Redis；期間 web 有短暫維護中斷。
3. 套用候選 GitHub SHA。依 `redis_auth_runtime.py --help` 審查 prepare（此步需 web 的 Ruby YAML parser，所以應於停止 web 前執行）；不要將密碼輸出。
4. cutover 保留 RDB 和 volume，驗證 unauthenticated NOAUTH、named user PING、ACL DRYRUN flush 拒絕（不可實際試 FLUSH）。再啟動 web、主 worker、兩專用 worker。
5. startup 重新登記各自排程。核對原啟用時間完全相同，等待兩次五分鐘 tick 和完成 heartbeat。
6. root-owned 安裝 watchdog Python 至 `/usr/local/lib/aienglish/`；建立 `/var/lib/aienglish-schedule-watchdog` 700，安裝 service/timer 至 `/etc/systemd/system/`、啟用 timer。先只讀手動檢查通過，不能把不健康狀態當成完成。
7. 保存 Git SHA、container StartedAt、排程與 heartbeat、HTTP／worker／SMTP結果。分清 runtime code 與 image label；source bind mount 更新不會自動更新已載入 Ruby。

## 回退及限制

- Redis backup、credentials、原 .env／compose／inspect 留私有 runtime。應用回退不能順便退掉網路隔離或 ACL。舊版應用若不懂 named user，須先配好帶驗證 REDIS_URL，否則不能直接回退。
- 切換保留舊停止 Redis 容器供檢查；**絕不與新容器同時啟動同一 volume**。驗收後才可移除舊容器（不帶 -v、不移除 volume），避免 compose 誤識別兩個同 service 容器。
- 健康告警沿用既有 SMTP；整台 host／Docker／SMTP 都故障時不保證能發信，仍需主機外監控。通知 cooldown 保存於磁碟，不受 Redis 清空影響。發送不明需人工查 SMTP，不可刪 cooldown 強行補寄。
- 163 筆歷史 pending 無可用 generation metadata，不能自動確認原 Dify 結果；逐筆補充線索後由管理員決定，不屬於已自動修復。
- 前端 Grading tab／Sentence Builder edit 另有前端交接文檔，Backend 發布不會自動修前端。

## 驗證與實際狀態

本節須在部署後補記精確 SHA／實際驗收；上述步驟不是已完成聲明。
本地：恢復／報告／可靠性 60 tests、400 assertions；獨立健康模型 6 tests、28 assertions；URL 認證 2 tests、7 assertions；Python ops 16 tests 通過。ACL／scheduler 真實隔離 Redis 測試及新增 mailer 測試結果另補。没有向正式學生紀錄寫入。
