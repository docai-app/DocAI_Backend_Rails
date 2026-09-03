# AI English Sidekiq concurrency 6 部署與驗證手冊

日期：2026-08-26

## 目的

將 AI English Rails backend 的單一 Sidekiq process 總並行數由 2 提升至 6，以縮短作文、Speaking Essay、Sentence Builder 等共用背景工作的排隊時間。

本次只修改：

```yaml
# config/sidekiq.yml
:concurrency: 6
```

本次不會：

- 新增 Sidekiq process；
- 將 EssayGradingJob 拆到獨立 queue；
- 改變現有 19 個 queue 的順序或權重；
- 改變 Essay、General Context、Revised Essay、Follow-Up Practice 的執行順序；
- 修改 Dify、Frontend、Puma、PostgreSQL、Redis 或閱讀理解生成服務；
- 令每種 Assignment 各自擁有 6 個位置。

## 並行語義

正式環境維持一個 Sidekiq process，因此部署後：

```text
1 Sidekiq process × concurrency 6 = 全部受監聽 queues 合計最多 6 個 jobs
```

這 6 個位置由同一個 Sidekiq process 監聽的所有 queues 共用。`EssayGradingJob`目前沒有指定自訂 queue，因此仍進入`default` queue；這是本次刻意保留的現有行為。

同一個`EssayGradingJob`內的 Dify calls仍然順序執行：

```text
Main grading
  → General Context（如有）
  → Revised Essay（如有）
  → graded / stopped
  → Follow-Up Practice（Essay才有）
```

所以 concurrency 6 一般代表最多 6 份背景工作同時處理，不代表一份作文的 4 個 stages同時執行。

## 2026-08-26正式環境只讀確認

部署前已在正式 AI English Rails Server完成以下只讀檢查：

| 項目 | 確認結果 |
|---|---|
| Sidekiq processes | 1 |
| 現時runtime concurrency | 2 |
| Sidekiq啟動命令 | `bundle exec sidekiq -e production` |
| CLI `-c`覆蓋 | 沒有 |
| concurrency環境變數覆蓋 | 沒有 |
| 生效設定檔 | `config/sidekiq.yml` |
| Rails production DB pool | 25 |
| PostgreSQL `max_connections` | 200 |
| 檢查時PostgreSQL全部connections | 18 |
| AI English Server | 4 vCPU、約12GB RAM |
| 檢查時可用RAM | 約8.6GB |
| 檢查時Sidekiq RAM | 約241MB |
| 檢查時Redis RAM | 約5.5MB |
| 檢查時Sidekiq busy | 0 / 2 |
| Enqueued / Scheduled / Retry / Dead | 0 / 0 / 0 / 0 |

正式Docker Compose的Sidekiq service沒有設定額外副本，也沒有用`-c`覆蓋設定：

```yaml
sidekiq:
  command: bundle exec sidekiq -e production
```

只要保持一個Sidekiq container，部署後總並行便是6，不會自動變成12或18。

## Dify容量依據

Dify Server曾執行以下真實模型突發測試：

- 5篇IELTS＋5篇JAE；
- 每篇300 words；
- 10份同時開始；
- 每份依序執行Main grading、General Context、Revised Essay、Follow-Up Practice；
- 40 / 40個Dify stage requests成功；
- 10 / 10條完整chains成功；
- 整批wall time為88.65秒；
- 最慢單份為88.64秒；
- 測試後Dify API回應HTTP 200；
- API、Worker、Plugin Daemon及PostgreSQL沒有新增error marker。

測試期間Dify host CPU曾達100%，因此本次只將正式並行提升至6；沒有足夠證據支持在現有Dify Server長期使用高於6的持續並行。

## 閱讀理解自動生成不受影響

正式環境的閱讀理解自動生成由獨立container執行：

```text
qg-backend-rails-comprehension_worker-1
  → bundle exec rake comprehension:work_loop
```

該worker不是AI English Sidekiq process，並且每次從durable pipeline取一個step處理。本次`2 → 6`不會改變它的並行、queue或生成順序。

舊`pormhub`的同步`comprehelp_mcq_eng`路徑亦不是本次Sidekiq process的一部分。

## 工程師Review清單

合併前確認diff只包含：

```text
config/sidekiq.yml
docs/sidekiq_concurrency_6_deployment_2026_08_26_zh.md
```

執行：

```bash
git diff --check
ruby -e 'require "yaml"; c = YAML.load_file("config/sidekiq.yml"); abort unless c[:concurrency] == 6; puts c[:concurrency]'
```

預期輸出：

```text
6
```

## 正式部署步驟

### 1. 確認Server worktree

```bash
cd /home/akali/aienglish/DocAI_Backend_Rails
git status --short
git branch --show-current
```

正式Server在2026-08-26已有兩個未追蹤font files。不要執行`git clean`、`git reset --hard`或刪除這些檔案：

```text
app/assets/fonts/ARIAL.ttf
app/assets/fonts/ARIALBD.ttf
```

### 2. 部署工程師核准的commit

依現有production部署流程合併及pull。完成後確認：

```bash
grep -n '^:concurrency:' config/sidekiq.yml
```

預期：

```text
1::concurrency: 6
```

### 3. Quiet Sidekiq並等待現有Job完成

先阻止Sidekiq再取新Job：

```bash
docker kill --signal=TSTP docai_backend_rails-sidekiq-1
```

檢查runtime：

```bash
docker exec docai_backend_rails-sidekiq-1 bundle exec rails runner '
require "sidekiq/api"
puts Sidekiq::ProcessSet.new.map { |p|
  { identity: p["identity"], concurrency: p["concurrency"], busy: p["busy"], quiet: p["quiet"] }
}.to_json
'
```

必須等待`busy: 0`才停止container。不要在作文、Speaking audio或其他長工作仍在執行時強制重啟。

### 4. 只重啟Sidekiq

```bash
docker compose stop -t 3600 sidekiq
docker compose up -d sidekiq
```

不需要重啟：

- `docai-rails`／Puma；
- Redis；
- Dify；
- Frontend；
- `qg-backend-rails-comprehension_worker-1`。

### 5. 驗證runtime確實為6

```bash
docker exec docai_backend_rails-sidekiq-1 bundle exec rails runner '
require "sidekiq/api"
processes = Sidekiq::ProcessSet.new
puts({
  process_count: processes.size,
  processes: processes.map { |p|
    { identity: p["identity"], concurrency: p["concurrency"], busy: p["busy"] }
  }
}.to_json)
'
```

驗收條件：

```json
{
  "process_count": 1,
  "processes": [
    { "concurrency": 6 }
  ]
}
```

同時確認：

```bash
docker compose ps sidekiq
docker logs --since 5m docai_backend_rails-sidekiq-1
```

## 部署後Smoke Test

使用非學生資料提交至少：

1. 一份普通Essay；
2. 一份有General Context及Revised Essay的Essay；
3. 如維護時段允許，一份Speaking Essay。

確認：

- API提交立即成功並返回`pending`；
- Sidekiq取出Job；
- Dify各stage依舊順序執行；
- 成功後狀態為`graded`；
- Follow-Up Practice可以完成；
- 失敗時狀態與error summary仍可保存；
- 閱讀理解worker保持運行。

## 部署後監察

至少觀察30至60分鐘及一個真實繁忙時段：

- `Sidekiq::ProcessSet`仍只有1個process；
- 每個process concurrency為6；
- busy不會超過6；
- Default queue最舊Job等待時間；
- Sidekiq retries及dead jobs；
- Dify HTTP 429、502、503、504、524及timeout；
- Dify API、Plugin Daemon、PostgreSQL、Redis的CPU/RAM；
- AI English Server RAM、Swap及database connections；
- Essay由`pending`轉為`graded`的P50/P95時間。

建議告警門檻：

- Dify錯誤率超過1%；
- 主批改P95超過60秒；
- queue最舊Job等待超過3分鐘；
- Dify host CPU持續10分鐘高於85%；
- Dify可用RAM低於700MB；
- Swap持續增加或出現明顯swap-in/swap-out。

## 回滾

如出現持續timeout、Dify錯誤率增加或其他服務受到影響：

1. TSTP quiet Sidekiq；
2. 等待`busy: 0`；
3. 將核准版本回滾至`:concurrency: 2`；
4. 只重啟Sidekiq；
5. 驗證runtime重新顯示一個process、concurrency 2。

回滾不需要修改Dify workflows、API keys、Rails database或Redis資料。

## 已知限制

- 本次容量測試證明10份完整Dify chains的單次突發可以成功，不代表任何流量模式都能100%無錯誤；
- Moonshot、OpenAI等provider的rate limit及臨時故障不受Sidekiq控制；
- 未來如果增加Sidekiq replicas，總並行會變成`6 × process數量`，必須重新容量評估；
- Follow-Up Practice仍在同一個EssayGradingJob內執行，會繼續佔用一個Sidekiq位置，直到Follow-Up完成；
- 本次沒有加入全域Dify semaphore，所以Frontend直連Dify或其他同步Rails calls不受這6個Sidekiq slots限制。
