# 全作業類型草稿／提交保護：工程師交接

日期：2026-09-18。這是程式交付文件，不是正式環境已部署證明。

## 1. 發布範圍與版本

- Backend：`docai-app/DocAI_Backend_Rails`，`development`。本次功能 commit `086bd63`，已基於遠端 `2173fd6`（學校密碼管理授權）整合。後續文件 commit 不改變此功能範圍。
- Frontend：`loveson821/essay-checker`，`bobby-codex`；基於 `0550326`，配套文件 `docs/2026-09-18-all-assignment-drafts.md`。發布時記錄兩邊實際完整 SHA，不只記分支名稱。
- 只推 GitHub；前端分支自動 Preview 已获允許。正式部署由工程師執行。本次未切換任何正式／測試伺服器、未操作學生紀錄。
- **本次沒有 migration、表／欄位／索引／trigger 變更。** 不要順帶執行其他 migration。若實際部署範圍另含未執行 migration，停止並按原部署規範處理。
- 未修改總 Admin 或微信小程序，未合併原工作區其他未提交的 Listening、學校或語音功能。

## 2. 為甚麼修改

原本不同表單自行決定 create/update：同一草稿可能被當成新提交；快速連點、丟失回應、舊分頁儲存可能重複新增或覆蓋狀態。前端 loading 本身不能保證同一時刻只送一個請求；後端必須同時校驗固定紀錄、版本和操作識別碼。

新不變條件：同一學生＋同一 assignment 最多一份經新版寫入流程建立的 draft；已有 draft 時先恢復它，最終提交沿用同一 grading ID；舊版頁面不能把已提交紀錄改回 draft。

## 3. 類型覆蓋與刻意保留的差異

| 類型 | 本次行為 |
|---|---|
| Essay、Sentence Builder | 恢復文字／句子答案；手動儲存與提交固定 ID；即時提交鎖 |
| Comprehension | 恢復答案／自訂文章資料；題目未載入不能提交；全未作答需確認 |
| Sentence Puzzle | 恢復既有遊戲進度；保留原有進度儲存，不把空白預留 draft 誤當已開始遊戲 |
| Speaking Essay | 恢復已保存錄音 URL／逐字稿；multipart 保存及提交同一附件；提交前轉錄有即時鎖 |
| Speaking Pronunciation | 恢復已保存句子及結果；保存／提交沿用 ID |
| Speaking Conversation — Preset | 恢復已保存答案；逐題保存串行化並帶版本；End 等待保存完成，提交沿用 ID |
| Speaking Conversation — AI Followup | 恢復既有保存的對話；End 提交固定 ID。不新增每句聊天 autosave |
| Listening | 只適配已提交到 Git 的現有學生表單；恢復答案時重新取得題目後按 ID 合併；不返回答案 key，不擴展新 Listening 教材功能 |
| Talk Lab Speaking | 預留固定 draft ID，End 精確重送同一內容／操作 ID；已有非空歷史 draft 不覆蓋，提示教師核對。**沒有新增即時 RTC 通話續接或 Save as Draft 功能** |

使用者明確排除的行為：**提交後再次從入口進入，仍允許既有的新一次作答行為**，不是一律跳原提交。這意味着跨重新載入的新作答不能被誤稱為全域「永遠只交一次」。本次不做每次輸入自動保存；沒有按 Save as Draft 的文字不承諾刷新後保留。

## 4. Backend 實作

主要檔案：`AssignmentDraftSession`、`AssignmentDraftGuard`、`AssignmentDraftEndpoints`、`EssayGradingsController`、Preset endpoints、`EssayGenerationRun`。

1. 開啟／準備：`POST /api/v1/essay_assignments/:code/essay_gradings/current_draft`，body `{request_id: UUID}`。在學生＋作業範圍內取得或預留 draft，回傳 `essay_grading.id/status/meta.assignment_draft_session.revision`。同一開啟請求重送不新建。`GET` 仍可唯讀找草稿。
2. 儲存／提交：`PUT /api/v1/essay_gradings/:id.json`，body 包含 `request_id`、`draft_revision`、`essay_grading`。仍支援 multipart，相同欄位放外層。Preset 逐題 PATCH／最終 POST 亦帶這兩欄。
3. 同一操作的網絡重送必須使用**相同 ID、相同版本、相同完整 payload**。最近一筆操作已成功則返回原紀錄，不重跑 callback；同 key 不同 payload 返回 409。舊 receipt 被後續操作取代時返回衝突，不重做舊寫入。
4. PostgreSQL transaction advisory lock 以學生＋assignment 為粒度，配合 row lock；驗證版本／狀態、寫答案與回執在同一交易中。一般 model draft save 同樣防重複；Admin 明確改回草稿取得同序鎖、撤銷舊生成 token 並增加 revision。
5. 預留空 draft 不計正式 submission 數，提交才計一次。Admin 明確重跑預留草稿亦只計一次；刪除未計數 draft 不扣正式提交數。
6. 不改各類型既有評分算法；不能由 client 自報 graded 就跳過批改。套裝入口仍校驗是否解鎖，成功提交仍更新套裝進度。
7. Listening 回傳保留既有答案保護：草稿只給 question ID／user_answer／允許的播放資訊，不暴露正確答案。兼容發版前的 Listening Idempotency-Key 回執，避免切換時重送新增一筆。

這是**應用層併發保護，不是新增 DB 唯一約束**。raw SQL／update_columns／未升級寫入程序能繞過一般 callback；不能新舊 web 寫入程式長期混跑。歷史多份 draft 返回 409，全部保留；不自動選最新、合併、刪除或批量 rerun。

## 5. Frontend 行為

共用 `useAssignmentDraft`＋`AssignmentDraftBoundary`＋`assignmentDraft` service；沿用既有授權／embed 請求封裝。載入完成才開放表單；背景刷新不重設正在編輯的答案。

- 同步 ref 鎖避免 React 更新之前的第二次提交；成功後舊頁面保持禁止寫入，正常跳回 dashboard／通知 embed。
- 返回仍是 draft、ID 不符或格式不完整時不顯示提交成功。
- 網絡結果不明：保留當前頁答案與原 payload，只能「Retry same save」確認同一操作；不盲目 create。
- 409：保留當前畫面答案，停止覆蓋，提示重新核對；不自动丟棄本地內容或強行帶新版本覆寫。
- 4xx 可修正錯誤：允許檢查答案／登入後再操作；普通用戶提示不顯示 JSON 或內部技術資訊。
- 不保證關閉瀏覽器後仍保留未保存的文字／內存重送 payload；這不是離線自動同步。

## 6. 舊網頁／微信小程序的相容性（上線前必讀）

尚未升級的 client 可繼續寫未登記新版版本保護的舊 draft；Backend 會在相同作業範圍找 draft 而不是另建。但一旦新版網頁開啟／保存使它成為 managed draft，**缺 request_id／draft_revision 的舊 client 會收到 409**，不能以接受無版本覆寫來保持表面相容。

因此小程序如需接續網頁草稿，工程師必須協調其 agent：開啟專屬草稿入口取得 ID／revision；保存提交傳原 ID、revision、本次操作 key；未知結果精確重送；409 保留輸入並提示核對。本次沒有改或驗收小程序。若它仍使用舊協議，不可宣稱跨端全部可用；先於測試環境驗收、安排配套發布，再向正式學生開放。

## 7. 驗證與界限

- Backend 功能／併發／權限／評分／恢復測試（整合遠端前）：161 tests、1,718 assertions 通過。覆蓋九類型、同時開啟、save/submit 競爭、操作重送、Admin、附件、套裝、歷史重複草稿。
- 整合遠端學校權限更新後：**173 tests／1,799 assertions，0 failures／errors**；測試入口另加 `school_password_delegation_test.rb`。
- Frontend：28 項單元／DOM 測試通過；Comprehension 20、Sentence Builder 18、另外七種表單桌面／手機 56 項瀏覽器檢查通過。Talk Lab 使用 scenario 測試，未連真實 RTC provider。
- 真實 React 表單與共享 hook 在隔離瀏覽器運行；身份、API、錄音／OCR／RTC provider 為 fixture。Rails 測試使用本地隔離 PostgreSQL、Sidekiq fake、ActiveStorage test disk；不接 production DB、Dify 或 Azure。
- 既有三項 package model 測試因隔離資料庫缺 `abilities` fixture table 失敗，基準版亦相同；本次另有實際 package HTTP 回歸通過。不宣称全 repo 所有測試皆通過。
- 不能保證零 bug。正式資料、真實手機錄音、Azure／Dify、微信 WebView、RTC、跨端連續操作及所有歷史異常仍需部署後驗收。

## 8. 工程師發布順序

1. Fetch 並固定兩 repo 精確 SHA，review 完整部署差異；本文件只批准上述 slice，不代表整個 development 與正式差異均已驗收。保存舊 SHA／設定與完整備份還原資料。
2. 先部署到隔離測試站，核對實際 API 指向。準備測試老師／學生，不用正式學生答案製造失敗。
3. 本次無 migration；核對實際發布範圍沒有混入其他待遷移內容。若有，交由工程師按既有流程先處理，不能直接部署。
4. Backend 先上配套版本，再發布前端。新版前端依賴 POST current_draft；舊 Backend 缺此入口會阻止作答。協調前端 Preview 不連未兼容的正式 API。
5. 安全切換所有相關 web／主批改／報告／恢復 worker，讓在途工作完成，不強制清 queue，不新舊混寫。這次不調整已啟用的報告／恢復設定、不批量 rerun 歷史 pending。
6. 配合小程序版本相容性核查；無法配套時先暫緩正式 rollout，不刪版本保護。
7. 完成下節驗收才宣布上線。GitHub push／Vercel Preview 不等於正式發布完成。

## 9. 發布後必做驗收清單

每類型至少一筆隔離測試作業：code 入口及派發入口互相恢復同一 ID；手動保存後重新進入答案一致；保存＋提交後只留一筆非 draft；快速連點不新增；兩分頁不同答案舊版本不能覆寫；未知網絡結果重送仍同 ID；提交成功後返回 dashboard 狀態刷新。

另驗收：Comprehension 題目未載入／全空；自訂文章；Speaking Essay 真實錄音及附件；Pronunciation 結果；Preset 保存後 End；AI Followup End；Puzzle 進度；Listening 播放次數及答案保密；Talk Lab End 超時再確認；套裝下一題解鎖；學生不能改別人 draft；Admin Rerun 不受學生版本鎖限制。歷史多 draft 僅核對，不清除。

## 10. 回退與交付回報

先停止繼續發布，記錄失敗樣本與兩端 SHA，不清除 receipt／meta 或學生答案。優先回退有問題的前端並保留新版 Backend 保護；旧 client 遇到新版 managed draft 可能 409，需提示暫停編輯並修復配套。**不要直接將 Backend 回退至可接受舊頁面覆寫的版本而放任學生繼續操作。** 若必須回退 Backend，先暫停相關寫入，工程師評估安全窗口及資料保護。

工程師回覆：兩 repo 完整 SHA、部署環境／時間、migration 核查、web/workers 版本一致性、各類型驗收結果、mini 相容性、已知未完成項與回退 SHA。不要把密鑰或學生作文貼到交接文件。
