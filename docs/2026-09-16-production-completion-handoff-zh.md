# AI English 正式環境部署補完與驗收交接

文件日期：2026-09-16。現場證據時間：澳門時間 2026-09-16 15:47–15:49。

**交給工程師的主文件：請依此完成 Backend 安全修正、報告排程、失聯恢復及正式驗收。** 功能已在 GitHub，主要工作是 review、設定及部署，不是重新寫整套功能。任何新增缺陷修正仍須獨立提交、測試及核准。

本文件是該時間的只讀檢查結果及後續操作要求，**不是已部署完成或全面驗收通過的聲明**。工程師執行前須重新核對版本與狀態。此前文件的「尚未 push／未 migration」等歷史狀態，以本文件的現場快照為準；程式細節仍可參考文末附錄。

## 1. 要完成的事情與放行條件

按順序完成：

1. 優先限制仍公開的 Backend 管理入口，協調 Admin 私有 token，部署安全修正。
2. 保留現有主批改 worker／Redis／資料，新增兩個獨立、可自動啟動的 worker。
3. 分別設定報告及恢復的真實啟用時間，不倒填、不批量處理舊 pending。
4. 驗收管理登入與拒絕路徑、主批改、兩個週期排程及真實收件。
5. 回傳第 12 節的部署證據，才能判定完成。

**不得只因容器 running、Vercel success、SMTP 已設定或 Sidekiq 顯示 Schedules Loaded，就宣稱全部完成。**

## 2. 現場快照：哪些已做、哪些仍缺

| 項目 | 2026-09-16 15:49 澳門時間的證據 | 後續要求 |
|---|---|---|
| 總 Admin | `main` 的 `946b8d9` 已成功部署；包含 `622eb09` 登入／私有 API proxy 修正及後續工程師更新 | 保留後續更新；驗收真實登入及與新 Backend 的 token 配合 |
| 正式 Backend | 主機 checkout 分支 `production`，SHA `94c1210`；Rails／主 worker 仍為 9 月 13 日啟動 | 尚未包含 `9f81058` 安全修正，需工程師發布 |
| 測試 Backend | 分支 `development`，SHA `c567186`，包含 `9f81058` | 已有安全修正，但不是正式已更新的證明 |
| migrations | 正式／測試四個指定版本均已登記；四張相關 public 表存在，事件捕捉檢查未報錯 | 部署前重查，不重跑已完成 migration |
| Admin 網頁未登入 | 管理頁 307 到 `/admin-login`；同源 Admin proxy 401 | 網頁保護已生效，不代表 Rails 已受保護 |
| 正式 Rails 管理 API | 無憑證 GET `/api/admin/v1/essay_assignments/categories` 仍返回 200 | 必須改為拒絕未授權請求 |
| 正式 Sidekiq Web | 無憑證 GET `/sidekiq/busy` 仍返回 200 並含管理狀態頁 | 必須限制存取；未測試任何停止／刪除操作 |
| 報告 | 無 dedicated worker、無 `ai_english_operations_report` 排程，寄送表無紀錄 | 尚未啟用每日三封報告 |
| 恢復 | 無 dedicated worker、無 `ai_english_generation_recovery` 排程，相關開關／啟用時間未設定 | 尚未啟用每五分鐘失聯檢查 |
| SMTP | Rails 使用 SMTP，寄送開關開啟，伺服器／port／帳號／密碼設定存在 | 不代表報告已寄出；須確認正式收件 |
| 收件人 | `ADMIN_NOTIFICATION_EMAIL` 未明確設定，程式有既有預設地址 | 請明確設定及確認，不只依賴預設值 |

本次 GitHub 查驗：Admin 的 production deployment 在 9 月 14 日 10:31 澳門時間成功；版本 `946b8d9` 比登入修正 `622eb09` 多一個提交。不要為了部署安全功能把 Admin 回退到 `622eb09`，否則會丟失工程師後續更新。

### 批改資料快照的正確解讀

- 最近 24 小時「建立」的 public grading 紀錄：543 graded、74 draft，未查到 pending／stopped。這是 created_at 群體，不等於最近 24 小時所有提交事件；更不代表 543 筆內容已逐筆品質驗收。
- public grading 中仍有 163 條 pending 且 created_at 超過兩小時，最早可追溯至 2025 年。這只是歷史候選數，**不是 163 條都已證實失聯**。
- 查核時主 worker busy=0，retry／scheduled 均為 0；generation 表另有 4 個 queued、488 個 ready。這些總數不能直接一一對應，也不能單憑 queue 空就把 queued 全部重跑。
- 上述數字會變動，請勿把快照當成部署後的即時狀態。

## 3. 版本、repo 與發布範圍

| 用途 | Repo／版本 |
|---|---|
| Rails Backend | `https://github.com/docai-app/DocAI_Backend_Rails` |
| Backend 開發交付分支 | `development` |
| 已在 GitHub 的審核基準 | `c56718685ade416fb9a3a16214cdcecaff3b4837` |
| 必須包含的安全修正 | `9f81058bbbcddacccb0054efc90b1e0cdbf881e3` |
| 本次查到的正式回退基準 | `94c1210ce67f0470b7bd221d81193ed497c11794`；**此版管理入口不安全，不能直接公開回退** |
| 總 Admin | `https://github.com/qq505810824/AIEnglish_Admin_Dashboard_Frontend`，`main` |
| 本次查到的 Admin 正式版本 | `946b8d9e3ff901c669243e4231d6fe10b4f1ea79` |
| Admin 原登入／proxy 修正 | `622eb09c65e6efa5b51aeda1784787f042da3ec4`，已被上述版本包含 |

Backend `94c1210..c567186` 差異是管理驗證、Sidekiq 保護、對應測試及交接／規則文件；**沒有新增 migration、沒有新增報告／恢復 worker 程式**。後兩項程式原本已在正式基準內，現在缺的是獨立程序及啟用設定。

工程師須先 fetch，review 當時的完整差異。如果 GitHub 已有新提交，不能盲目把整個最新分支部署；記錄最後核准 SHA。依團隊正式發布流程整合到 release／production，再將該精確 SHA 提交到 GitHub 並部署。**不必把正式服務改用 development 環境；development 是交付分支，正式仍使用 Rails production 環境與正式設定。**

此次不要求重部署學生／老師 frontend，不修改微信小程序，不發布未驗收的 Listening 業務。學生／老師端既有的「需要檢查」提示仍需列入驗收，若缺少對應版本再獨立安排，不能把檢查當成已發布。

## 4. 操作前安全準備

### 4.1 先控制公開管理入口

在修正正式生效前，工程師可透過現有 VPN、可信來源 IP、反向代理或 WAF 限制 `/sidekiq` 及管理 API。必須先盤點 Admin server／其他合法管理客戶端的來源，避免誤擋正常代理。

- 不要阻擋普通學生／教師 `/api/v1`、學校管理 `/api/school*` 或公開 OAuth／SSO 路由。
- 不要用 Sidekiq 的 Stop All、Quiet All、Clear／Delete queue 測試權限。
- 檢查現有存取紀錄是否有异常來源；曾公開不等於已確認遭到濫用，但也不能宣稱沒有外洩。
- 增加管理登入及 Sidekiq 的網路／速率限制；本次程式不是 MFA 或逐個管理員權限系統。

### 4.2 備份及還原準備

- 保存正式 DB 備份位置、時間與還原驗證結果；備份受保護且不入 Git。
- 記錄部署前 SHA、container/image IDs、程序啟動命令、queue 清單及私有環境設定的安全備份。
- 核對 Redis 是否有持久化及可用備份，保留原容器及 queue／retry／scheduled 狀態。
- 非敏感部署配置及啟動／回退步驟須能在 GitHub 追溯；密鑰及 runtime secret 檔不可提交。

已知測試機原 `deploy.sh` 會 `docker-compose down/up` 及全機清理 image，不可盲目套用到正式。正式腳本也須先審核。不要使用 reset/clean 覆蓋伺服器既有字型差異，不清 Redis、不批量刪 image。

### 4.3 migrations：只核對，不盲目重跑

在正式應用容器／正確服務環境內執行只讀 `RAILS_ENV=production bundle exec rails db:migrate:status`，確認：

| 順序 | 版本 | 檔案／用途 |
|---|---|---|
| 1 | `20260911143000` | `create_essay_generation_runs`：生成協調表 |
| 2 | `20260912001000` | `create_operations_reporting`：事件、報告寄送表及 trigger |
| 3 | `20260912030000` | `add_essay_generation_recovery`：恢復追蹤 |
| 4 | `20260912040000` | `harden_operations_delivery`：通知及寄送／時區保護 |

本次都已查到 up。**已 up 不重跑；若當時狀態不同，停止發布並由工程師處理依賴。** 不把其他未核准 migration 一起執行，不跳過時區檢查，不手改 schema_migrations。

核對 public 的 `essay_generation_runs`、`essay_operation_events`、`operations_report_deliveries`、`essay_generation_notifications`；`essay_operations_status`、`essay_operations_generation` trigger 啟用；事件時間型別正確。可用只讀 Rails 檢查 `OperationsStatusReport.verify_capture!`。成功時可能不輸出內容，不以空白當作失敗。

`operations_reports:install_triggers` 是結構寫入，**不是一般健康檢查，不要在這次已正常的資料庫直接執行**。只有確認 trigger 缺失且工程師核准修復方案後才處理。

## 5. Backend 與總 Admin 安全設定及切換

### 必須核對的私有設定

| 程序 | 變數 | 要求 |
|---|---|---|
| Rails web | `ADMIN_TOKEN` | 新的高強度隨機私有值，至少 32 字元；盤點所有合法使用者後輪換 |
| Admin server | `ADMIN_RAILS_TOKEN` | 與 Rails `ADMIN_TOKEN` 完全一致，不能進瀏覽器 bundle |
| Admin server | `ADMIN_RAILS_ORIGIN` | 正式固定 HTTPS origin：`https://docai.m2mda.com` |
| Admin server | `ADMIN_PUBLIC_ORIGIN` | 總 Admin 為 `https://aienglish-admin.docai.net`；其他 project 各自設定 |
| Admin server | `ADMIN_BASIC_USER`、`ADMIN_BASIC_PASSWORD` | 正常登入頁使用的私有帳密；曾公開的舊值須輪換 |
| Admin server | `ADMIN_SESSION_SECRET` | 至少 32 字元隨機私有值 |
| Admin server | `ADMIN_SESSION_TTL_SECONDS` | 300–86400 秒；與團隊核准的有效期一致 |
| Rails web | `SIDEKIQ_ADMIN_USER`、`SIDEKIQ_ADMIN_PASSWORD` | Sidekiq 獨立管理帳密；缺少設定應拒絕，不可回退公開 |

清除／淘汰曾公開的 `NEXT_PUBLIC_BEARER_TOKEN`、`NEXT_PUBLIC_BASIC_USER`、`NEXT_PUBLIC_BASIC_PASSWORD`。只從環境變數移除仍不夠，舊值可能在已發布 bundle 中，必須輪換。不得把教師／學生 JWT 或 `Bearer null` 當作全局管理 token。

Admin repo 同時連接總 Admin、school-admin、dev Vercel projects，變更私有變數時必須核對各 project 的 origin／backend，不可全部複製同一套正式設定。既有 QG 私有 token 另屬 QG，不與 Rails token 盲目同步。

### 切換順序

1. 確認現有 Admin `946b8d9` 的真實帳號登入正常，代理路徑已使用 server-only token；Vercel success 不等於上述設定一定正確。
2. 安排同一窗口輪換 Rails／Admin 私有 token；必要時管理介面短暫維護。不要為了避免短暫 502 接受無效 token。
3. 只對目標主批改 worker 停止領取新工作，等正在執行的工作完成；核實 busy=0。不要強制終止正在呼叫 Dify 的工作。
4. 部署已核准、可在 GitHub 找到的 Backend SHA；保持原正式 DB、Redis、主 queue、其他服務配置。記錄 web 和 worker 實際使用版本，source bind mount 時尤其避免舊程序讀到一半新程式。
5. 用既有 supervisor／容器服務安全啟動相容的 web／主 worker；確認主 worker 仍監聽 `default` 及既有 queue，不 quiet 卡住、不與舊寫入程序混跑。
6. 完成下方安全驗收，再處理兩個專用 worker。安全入口修正可獨立先完成，不須等歷史 pending 清理。

### 安全驗收標準

- 無登入、無 token／錯 token／`Bearer null`：直接 Rails 管理 API 返回 401，不含業務資料；不能只有 Admin 網頁擋住。
- 可用無憑證 GET `/api/admin/v1/essay_assignments/categories` 作低風險測試；並抽查作業、提交、學校、OAuth 管理入口。普通教師／學生 JWT 不可取得全局管理資料。
- Sidekiq `/sidekiq`、`/sidekiq/busy`、`/sidekiq/queues` 未提供有效帳密不可讀取；有效獨立帳密可讀，原 CSRF 保護保留。
- 正常 Admin 登入、deep link 回跳、作業／提交／學校／學生／老師列表及登出後拒絕 API；合法修改僅用專用測試紀錄驗收。
- 學生／教師與学校管理員原流程正常；不得要求普通用戶提供 `ADMIN_TOKEN`。
- 不自動重試有寫入的 Admin 請求；跨站寫入應拒絕。查驗時不要在日誌或截圖輸出 token。
- session cookie 不持久化，但瀏覽器恢復上次視窗可能保留 session；登出及絕對有效期另需驗收，不能承諾關閉視窗一定立即失效。

## 6. 新增報告 worker：每日三封

用既有容器／systemd／supervisor 增加**一個獨立程序**，設定開機啟動、異常退出重啟及日誌保留。不要只在 SSH 視窗前景執行後關掉。

該程序使用與 Rails 正式環境相同的核准程式、DB、Redis、SMTP、mailer 設定。不要誤連 dev Redis／測試資料庫；也不要讓 dev 另外寄一份正式報告。

| 報告 worker 變數 | 值／要求 |
|---|---|
| `AI_ENGLISH_REPORT_WORKER` | `true`，只設在 dedicated report worker |
| `AI_ENGLISH_REPORTS_ENABLED` | `true` |
| `AI_ENGLISH_REPORTS_ENABLED_AT` | 當次真實核准啟用時間，ISO 8601、明確 `+08:00`；不照抄文件時間 |
| `ADMIN_NOTIFICATION_EMAIL` | 明確設定核准收件地址；若仍寄 Bobby，可設 `bobby.lian@docai.net`；團隊群組須另外確認 |
| SMTP／寄件人設定 | 沿用已核准的現有 ActionMailer 設定，包括實際需要的 `MAILER_FROM` |

現有停止／人工確認通知由既有通知工作寄送；也要在其執行程序核對相同收件人與 SMTP，不能只替新報告 worker 設定收件人。

在具有上述報告設定的正式服務環境內執行：

```sh
RAILS_ENV=production bundle exec rake operations_reports:check
```

此命令只讀檢查表、trigger、時間、開關與收件人；**不測 SMTP 收件，也不啟動 worker**。

由服務管理器使用以下啟動命令：

```sh
bundle exec sidekiq -e production -C config/sidekiq_operations_reports.yml
```

應只監聽 `operations_reports`，concurrency=1；不得加入 grading queue，也不要讓主 worker 同時註冊報告排程。

### 排程及寄送驗收

- Redis 中存在 `ai_english_operations_report`，class=`OperationsReportTickJob`、queue=`operations_reports`、cron=`*/5 * * * * Asia/Macau`。
- 啟動核對及其後至少兩個五分鐘 tick 有真實入隊／完成證據；不是只有 scheduler 設定存在。
- 實際報告時段如下，包含起點、不包含終點：

| 截止時間（澳門） | 統計時段 |
|---|---|
| 12:00 | 當日 00:00–12:00 |
| 18:00 | 當日 12:00–18:00 |
| 00:00 | 前日 18:00–24:00 |

- 例如若實際在 15:30 啟用，第一個自動截止點應是當天 18:00；不補寄啟用前的 12:00。第一份仍是完整 12:00–18:00 時段，不是只統計啟用後。
- 實際寄達時間受查詢／queue／SMTP 影響，不保證到秒；無作業時段也會寄。中斷後最多補最近七天，不能把這解讀成永久完整歷史補寄。
- 收件人回覆確實收到第一封；檢查主旨、HTML／純文字、時段及 Admin／grading 連結。需介入時主旨及最上方異常區塊必須醒目。
- 內容核對每校／類型提交、老師建立作業、完成時間及樣本數、pending／stopped／unknown／補充練習失敗。資料截斷或缺歷史事件須有警告，不接受假全零報告。
- `operations_report_deliveries` 該 `period_end` 只有一筆，state=`sent` 並有 sent_at；**sent 只代表傳輸接受，仍需收件人確認**。
- SMTP 結果不明的 `unknown` 或卡在 `delivering`，先查供應商紀錄；不要直接改回 preparing／刪紀錄重寄。既有去重保護不要繞過。
- 若要在下一個截止點前額外寄測試信，須核准固定時段及收件人，避免佔用真實時段或重複寄送；不倒填啟用時間來觸發測試。

## 7. 新增失聯恢復 worker：每五分鐘檢查

另一個獨立、受服務管理器管理的程序，同正式 code／DB／Redis，也須有現有通知所需配置。

| 恢復 worker 變數 | 值／要求 |
|---|---|
| `AI_ENGLISH_RECOVERY_WORKER` | `true`，只設在 dedicated recovery worker |
| `AI_ENGLISH_RECOVERY_ENABLED` | `true` |
| `AI_ENGLISH_RECOVERY_ENABLED_AT` | 當次真實核准啟用時間，ISO 8601、明確 `+08:00`；**不得倒填** |

由服務管理器使用：

```sh
bundle exec sidekiq -e production -C config/sidekiq_generation_recovery.yml
```

只監聽 `generation_recovery`，concurrency=1。主 worker 不加這個角色 flag，不改其既有 queue。

### 適用範圍與安全規則

- 適用受 `EssayGenerationRun` 協調的 Essay、Speaking Essay、Speaking Conversation、Sentence Builder、Talk Lab Speaking，以及 Essay 的獨立 supplementary slot。
- **不是所有 assignment 通用**：Comprehension、Sentence Puzzle、Speaking Pronunciation 不走此非同步 coordinator；Listening 排除。
- 只掃描啟用時間後建立、超過兩小時的合資格受管 slot。兩小時是開始查核門檻，不是保證完成／直接重跑時間。
- 核對 busy、queues、scheduled、retry；仍存在就不重跑、不搬隊、不插隊。Redis／查核失敗不當成 queue 空。
- 工作遺失須兩次完整 absent observation，至少隔一分鐘，正常通常跨兩次五分鐘 tick；還需資料庫鎖、token 與 provider 記錄確認才能安全恢復。
- 原 Dify 結果已完成：以 GET 取回、驗證及保存，不 POST 再生成。仍在跑就等；結果不明標示需人工確認，不盲目付費重跑。
- 明確失敗仍按原規則首次＋最多兩次 retry，共三次；延遲 30 秒、2 分鐘。恢復不重設 attempts／成功階段，遺失 delivery 的替換另有兩次上限。
- 只 supplementary 失敗不能把已成功作文改回失敗，不覆蓋學生已保存答案。
- 重排的批改進入既有正常 queue，沒有插隊；多 queue／worker 不承諾全局嚴格 FIFO。
- 音訊分析、Revised completion、Speaking Essay 最後評分等部分在途結果不可可靠查回時，維持需人工確認；不是任何 Dify 問題都能自動恢復。

### 恢復驗收

- Redis 存在 `ai_english_generation_recovery`，class=`EssayGenerationRecoveryJob`、queue=`generation_recovery`、cron=`*/5 * * * * Asia/Macau`。
- 啟動及其後至少兩個 tick 真實執行；記錄專用 worker identity、queues、concurrency 及無錯誤退出證據。
- 新的專用測試提交在工作 claim 後記錄 `recovery_version=1`，可支援的 provider stage 保存 workflow ID／journal；內部 journal 不出現在公開 API。
- 正式用核准新測試紀錄驗收正常批改及 Dify GET 存取能力；不為測試修改學生狀態、kill 正式 worker 或移除正式 queue 工作。
- 在**隔離環境**測試遺失 delivery、工作仍在排隊、provider 開始前後失聯、已完成結果回收、結果不明、重試上限、兩次同時恢復及不覆蓋成功答案。
- 沒有待恢復候選時，只能證明排程執行，不能宣稱已驗收真實遺失工作恢復。不要為取得證據倒填啟用時間。

## 8. 歷史 pending：另開清理任務，不混入啟用

本次看到的 163 條歷史 pending 不會因開啟新 scanner 全部自動恢復。工程師需另列只讀清單：record／assignment ID、類型、建立時間、generation slot、queue/busy/scheduled/retry、provider ID／結果、是否已有成功內容或答案。

逐條分類為仍在跑、已有結果待回收、可安全重跑、無法確認、歷史不再需要處理，再由負責人核准動作。不能單憑 created_at、updated_at 或畫面 pending 判定失聯；不能批量改 graded／stopped、刪資料或全部 rerun。

歷史異常可能反覆出現在郵件；應標記為待稽核，不為讓報告變綠而隱藏或改掉紀錄。

## 9. 故障與回退

| 狀況 | 正確處理 |
|---|---|
| Admin 502／新登入後列表失敗 | 核對同源 proxy、固定上游及兩端私有 token；不放寬 Rails 認證、不接受 null |
| Sidekiq 管理頁登入不了 | 核對獨立帳密、代理／網路限制；Sidekiq Web 被擋不等於批改 worker 停止 |
| 只有 schedule 設定、沒有 job 執行 | 檢查 dedicated process 角色 flags、啟用時間、Redis、scheduler reload、監聽 queue、服務日誌及時間同步 |
| 報告 build_failed | 核對表／trigger、時間、資料及 mailer 渲染，不寄假全零報告 |
| 報告 unknown／長時間 delivering | 核對 SMTP 接受紀錄及實際收件；不直接重寄或刪防重紀錄 |
| 恢復判定／provider lookup 異常 | 停用恢復角色的 enabled flag 並安全停止該專用 worker，保留主批改與歷史資料；檢查原因後再決定 |

停用報告：將該程序 `AI_ENGLISH_REPORTS_ENABLED=false` 並依服務管理方式更新／重啟專用 worker；停用恢復同理使用 `AI_ENGLISH_RECOVERY_ENABLED=false`。不要只修改磁碟上的 env 而不更新運行程序。確認没有另一個舊啟用程序，並核對是否仍有在途工作，**不能把切開關當作瞬間取消在途寄信／恢復的保證**。

回退程式前安全 drain 相關 worker，使用已保存的相容 SHA 與設定；維持管理入口的網路保護，不能回到公開無驗證 API。保留新增表／trigger／事件、學生答案、成功批改及 Redis；不執行 down migration 作為一般回退。

報告／scanner 可各自停止，不須停掉整個批改服務。完整 DB／Redis／SMTP 故障時它們可能無法告警，仍需獨立外部監控。

## 10. 這次不包含的缺陷及限制

- 9 月 16 日另外確認 Comprehension 防重複提交缺口：前端缺即時提交鎖及載入就緒限制，後端此類型缺同一次提交的去重。**本文件的 auth／worker 啟用不能修復它**；需 frontend＋backend 另行修正、測試及交付，不自動刪除學生既有紀錄。
- 163 條歷史 pending 的分類、校正／重跑是獨立任務。
- 先前交接另有 Speaking Essay 非數字分數等未完成項，不能因本次部署就標為已修復；需逐项核對最新實作。
- 格式驗證、有限重試不代表所有題型都用同一評分規則，也不保證 AI 教學內容完全正確。
- 備份可還原性、私有 token 是否確實輪換、WAF／速率限制、真實帳號操作、Dify／郵件驗收，均需工程師提供證據，不能只沿用本地測試結果。

## 11. 完成標準

- [ ] 正式 web／主 worker 的核准 SHA 與 GitHub 一致，包含安全修正；無無關未驗收功能混入。
- [ ] 四個 migrations／public tables／trigger 已確認，無未解決 migration 或時區錯誤。
- [ ] 管理入口匿名／錯誤 token 被拒絕；Admin 真實登入與合法操作正常；普通用戶不受誤擋。
- [ ] 舊公開 token 已輪換並盤點其他消費者；Sidekiq 獨立帳密與入口限制就緒。
- [ ] 主批改正常、原 queue 保留，無舊 worker 混跑或 Redis 被替換清空。
- [ ] 報告及恢復各一個 dedicated worker，實際啟用時間與重啟／自動啟動設定可追溯。
- [ ] 兩個五分鐘排程有真實執行紀錄，不只配置／容器 running。
- [ ] 正式正常批改／補充練習與 Dify 可查結果驗收；受控失敗／失聯案例在隔離環境驗收。
- [ ] 至少第一封正式排程報告實際收到、內容及連結正確；後續兩個邊界持續觀察，最終覆蓋 12:00／18:00／00:00 三個時段。
- [ ] 郵件未收件／結果不明、歷史 pending 及其他未完成缺陷有負責人，不宣稱零 bug。

## 12. 請工程師完成後回覆這份清單

```text
部署時間（澳門）：
Backend 正式分支／完整 SHA／GitHub 連結：
Rails web、主 worker 實際版本：
Admin 正式 SHA／Vercel deployment：
DB 備份時間／受保護位置／還原驗證：
四個 migration status、表／trigger 驗證：
Admin 私有 token 輪換完成：是／否（不要填 token）
Admin 真實登入、匿名／錯誤 token 拒絕、普通用戶測試：
Sidekiq 無憑證拒絕／合法登入／網路限制：
主 worker queues／busy／版本相容：
報告 worker 服務名／queues／concurrency／實際啟用時間：
恢復 worker 服務名／queues／concurrency／實際啟用時間：
兩個排程名稱及至少兩次真實 tick 時間／結果：
正常批改、Dify 結果查詢、隔離失聯／重試測試：
核准收件地址、第一封 period_end／寄送狀態／實際收件確認：
12:00／18:00／00:00 各時段驗收或待觀察項：
歷史 pending 的獨立處理計劃：
其他未完成／風險／負責人：
回退 SHA／步驟與保留的安全限制：
```

工程師回覆後可再做只讀部署後核查。該核查不能替代工程師的備份還原證明、實際收件確認及使用者驗收。

## 13. 原始實作與詳細參考

本文件已整合執行必需的版本、順序、設定、限制及驗收要求，工程師可先只讀本文件；需要追實作時再查：

- [Backend 安全修正交接](2026-09-13-admin-api-auth-handoff-zh.md)
- [測試機部署記錄及原腳本風險](2026-09-13-development-server-deployment-check.md)
- [報告規則及郵件資料模型](2026-09-12-operations-email-reports.md)
- [失聯恢復邊界](2026-09-12-pending-recovery.md)
- [可靠性原始整體交接](2026-09-12-reliability-release-handoff-zh.md)
- [Admin 配套登入／API proxy 交接（固定原實作 SHA）](https://github.com/qq505810824/AIEnglish_Admin_Dashboard_Frontend/blob/622eb09c65e6efa5b51aeda1784787f042da3ec4/docs/2026-09-13-admin-api-auth-handoff-zh.md)

本輪僅新增本交接文件，未改應用程式、資料結構、AGENTS.md、伺服器設定，未 push／部署／寄信／重跑。文件未包含密碼、token 或學生個人資料。
