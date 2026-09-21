# Pending/Stopped 補充練習異常監控

## 行為與範圍

原有作文 Pending/Stopped 範圍及篩選不變。頁面請求 `include_supplement=true` 後，額外納入今學年、已完成作文批改的 essay 提交，補充練習為 failed/unknown，或 queued/retry_wait/running/checking 按報告相同 waiting clock 超過兩小時。正常在途、ready/cancelled 與往年補充練習不納入。學年使用 CurrentAcademicYearGradings（active 且澳門當日落在起訖日期；提交快照優先、assignment 學年為 fallback）。

- 「全部異常」同時顯示兩類問題，另有「補充練習異常（今學年）」篩選。
- 補充練習行顯示錯誤代碼、獨立任務狀態及「作文已完成」，不將作文偽裝成 pending/stopped。
- 「重試補充練習」只呼叫原有 supplement POST，帶 `retry_failed_only: true`，後端在 grading 行鎖內重驗 can_retry；仍保護 unknown/在途任務、已完成結果、學生作答及一分鐘冷卻。
- 只重試補充練習，保留作文及分數。確認框顯示學生及作業；結果不明不自動重送，先 GET 刷新。
- 補充練習行不能勾入主批改 bulk rerun 或改草稿。全選、選取保留、執行前再次過濾均排除這些行。
- 後端缺少 supplement_monitor 能力標記時明確提示未就緒，不能將空列表當成沒有異常。篩選請求按版本忽略舊回覆，刷新失敗保留原資料及警告。
- 沒有修改學生頁面、報告 email、Redis、學年資料、migration 或正式學生紀錄。

## 驗證

- Rails 明確隔離本機資料庫：22 tests / 164 assertions 通過，涵蓋新 monitor、Admin generation diagnostics 及既有 override。補充練習測試包含篩選/計數、舊學年、submission-year 優先、recent/future retry、恢復後移除、重複重試、分數/答案保留及 Admin 授權。
- Admin 既有登入、API proxy、generation status：27 tests 通過；TypeScript、修改檔 ESLint、production build 通過。
- 完整頁面瀏覽器測試：tests/supplement-monitor.browser.cjs，使用實際 page/Tremor/Tailwind，loopback 合成 API，不代表正式 Dify 或登入後正式資料驗收。1440／820／390 三種尺寸共 46 項檢查通過，包括完整 page 的 loading、篩選、bulk 排除、獨立 POST、keyboard Escape/焦點返回、stale refresh、empty 和不明 POST 結果不重送。目視確認桌面及手機畫面；表格捲動保持在卡片內。
- 全倉 UI 靜態 audit 仍有 20 項既有問題，這次修改檔無匹配項；沒有順帶改全站介面。DESIGN.md 沿用既有設計，AGENTS.md / UX-CONTRACT.md 記錄新增契約。

## 發布與回退

這次需要先部署 Backend 再發布總 Admin。沒有新增 migration；發布前仍須核對目標實際版本及未執行 migrations，若存在任何未確認結構變更則交工程師。Backend code 交付 development，正式部署及 Admin main push/Vercel 必須取得本次範圍的明確授權。不能借用之前郵件修復的正式部署授權。

Backend 部署沿用所有 Rails/worker 同版及 quiet/drain 流程，保留 Redis/queue 和排程啟用時間。Admin 使用既有登入與私有代理，密鑰不變。驗收只 GET 查看空列表／真實問題與篩選，不為驗收重跑已修好的五份。回退 Admin 後可保留 Backend additive opt-in API；若回退 Backend 必須先回退 Admin，以免新頁面要求未支援的補充練習篩選。

Backend code 已推送 development：`3e7d9b8`。總 Admin 修改在隔離分支 `codex/admin-supplement-monitor`，尚未 push main 或觸發 Vercel。兩者尚未正式部署。

### 本機重現

Backend 使用 Ruby 3.1.0，`LISTENING_RAILS_ISOLATED_TEST=1 RAILS_ENV=test PARALLEL_WORKERS=1`，並提供本機佔位 `DEVISE_JWT_SECRET_KEY` / `AZURE_STORAGE_NAME` / `AZURE_STORAGE_ACCESS_KEY`，執行 admin_supplement_monitor、admin_generation_status、admin_grading_override 三個 integration tests。沒有連接正式資料庫／SMTP／Dify。

Admin 瀏覽器測試需要本機 esbuild / playwright；`PLAYWRIGHT_CHANNEL=chrome node tests/supplement-monitor.browser.cjs` 使用已安裝 Chrome。套件透過測試環境提供，不因此修改產品依賴。既有 package.json Node types 24 與 lockfile Node types 20 不一致；除了鎖定依賴環境，另用隔離 @types/node 24.10.1 執行 TypeScript 檢查，不順帶改鎖定檔。
