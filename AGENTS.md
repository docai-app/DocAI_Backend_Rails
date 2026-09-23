# AI English Rails Backend 协作规则

适用于本仓库及子目录。用户当前明确指示优先；如子目录另有 `AGENTS.md`，同时阅读。操作前确认实际仓库、Git remote、分支与 `git status --short`，保留已有修改及未跟踪文件，不与相邻 Rails checkout 或微信小程序 worktree 混淆。

## 默认开发分支与测试部署

- 用户于 2026-09-13 指定：日后本 Rails Backend 默认在 `development` 分支开发、测试及交付，不再默认使用 `bobby-codex-backend`。先 fetch `origin/development`，核对差异并安全更新；不得覆盖未提交内容或未经检查把其他分支全部合并过来。
- 用户指定的测试服务器：`ssh akali@103.230.15.190`；repo 实际路径已核对为 `/home/akali/aienglish/DocAI_Backend_Rails`。用户原提供的入口为账号 `aienglish` 目录下的 `bash deploy.sh`；2026-09-13 实查该脚本会 down／up Redis 及全机清理无标签 images，因此不得原样盲目执行。该次用户另行批准 quiet／drain 后只停止、更新并启动 Rails／Sidekiq，保留 Redis、queue、images 与脚本。后续仍先检查当前脚本与影响范围；细节见 `docs/2026-09-13-development-server-deployment-check.md`。
- 用户允许后续在任务范围内完成开发、测试并推送 `development` 后，直接部署至上述测试服务器；只适用于该测试目标。**不得推送 `production` 或部署正式环境，也不得借用之前的正式部署授权。** 其他 repo／分支／服务器不自动获得同样授权。
- 执行部署前只读核对远端实际目录、repo、分支、commit、`deploy.sh` 及其调用的脚本，确认它们使用 `development`、测试环境和独立测试数据库，不会推送／拉取 production、触及正式服务或运行未获批准的 migration。若不符、无法确认或脚本会操作其他服务，停止并说明，不盲目执行或擅自修改脚本。
- 部署代码必须先在 GitHub 的 `development` 可追溯，记录精确 SHA；部署后核对服务器实际 SHA、服务状态及小范围验收。不得仅手改服务器而不提交 GitHub，不得 force push。
- 以下数据库结构／migration 限制仍然适用，测试服务器部署授权不覆盖它们；遇到待迁移或结构变更时交给工程师先处理，不自行执行 `deploy.sh` 中的 migration 或发布。
- SSH 密码不得写入 `AGENTS.md`、代码、脚本、日志或 Git；使用安全凭证提供方式，优先 SSH key。不得关闭 SSH 主机身份校验。

## 数据库结构与部署：必须由工程师把关

- 默认不要修改 `db/migrate/`、`db/schema.rb`、`db/structure.sql` 或通过 SQL 改表、字段、索引、约束及 trigger。任务确实需要结构变更时，先向用户说明必要性、影响及 migration 方案，取得明确同意后才编写。不能把普通功能修改或之前的笼统部署授权当成许可。
- 不手改 schema 文件代替 migration，不修改已执行的历史 migration 来绕过问题，不直接改正式数据库。
- **发布范围包含任何待执行 migration 或数据库结构变更时，AI 不得自行部署，也不得在正式环境替工程师执行 migration。** 由工程师先检查并执行所需 migration，确认成功后，才由工程师部署依赖新结构的应用及 workers。
- migration 失败、执行状态不明或工程师尚未确认时，停止发布；不得跳过检查、伪造 migration 状态、删表重建或强行启动依赖新结构的程序。工程师确认迁移成功不代表授权 AI 接着部署。
- 交接文件必须列明目标 commit、migration 版本、执行顺序及依赖、备份与还原要求、验证步骤、worker 切换和回退注意事项，区分「代码已写／已 push」「migration 已执行」「已部署／已验收」。
- GitHub push 若可能触发自动部署，也受上述限制。先协调工程师处理自动部署与迁移顺序；未经确认，不推送到会绕过 migration 前置条件自动上线的目标。不擅自修改部署集成或触发 Deploy Hook。
- 可以在任务范围内做只读检查；明确隔离的本地测试不是正式数据库迁移或部署授权。不得因测试而连接正式数据库执行写入。

## 代码交付

- 总 Admin Pending/Stopped 可用 `include_supplement=true` 加入今学年已 graded 的 essay 补充练习异常；`status=supplement` 仅筛选新增范围，主批改筛选保持原义。failed/unknown 立即列出，其他活跃状态沿用报告的两小时与 waiting clock。`retry_failed_only: true` 必须在 grading 行锁内重新核对 can_retry，不能覆盖 ready/unknown/在途结果或学生答案；回归见 `test/integration/admin_supplement_monitor_test.rb`。

- 狀態報告的作業異常及相關通知異常只列各校 `SchoolAcademicYear.active` 且起訖日期涵蓋報告快照的澳門當日（含首尾日）：優先使用提交時 `submission_academic_year_id`，缺少時才使用 assignment 的明確學年；不按建立日期、學年名稱或目前 enrollment 猜測。舊學年資料保留、不批量重跑；無法歸屬的紀錄只提示數量。時段活動統計／系統寄送健康維持原範圍。共用篩選及只讀 pending 稽核見 `docs/2026-09-20-report-scope-and-audio-concurrency.md`。
- Preset Speaking answer 音檔上傳在 `AssignmentDraftSession.write(prepare:)` 的短檢查之後、釋放 DB 連線後執行；保存前重新鎖定核對 revision／request_id，恢復原租戶 search_path。不可在外層 transaction 使用 prepare。服務端補上的 answered_at 不可參與請求指紋；失敗上傳不能被當作已保存。回歸 `assignment_audio_preparation_test.rb`；不代表全部附件路徑或正式吞吐量已驗收。

- Redis 防護、私有 ACL 切換、獨立於 Redis 的排程 watchdog 見 `docs/2026-09-19-reliability-hardening-handoff.md`。禁止對正式 Redis 執行 FLUSHALL／FLUSHDB、開放公網 6379 或用 compose down/prune 發布。排程健康須同時核對 registry、worker、tick 和完成 heartbeat；近期新 tick 為 running 時可沿用近期成功完成，避免時間重疊誤報，failed／過期／沒有成功仍告警。容器存活不能代替排程驗收。修復與發布核對見 `docs/2026-09-21-report-alert-corrections.md`。Redis credentials／RDB／incident evidence 不入 Git，應用回退仍須保留驗證及網路防護。

- 所有类型的学生草稿写入使用 `AssignmentDraftSession`：学生＋assignment advisory lock、固定 grading ID、request_id 精确重送及 draft_revision 检查。managed draft 缺版本返回 409，不能为兼容旧客户端放宽；历史多草稿按用户明确打开的 ID 独立保存／提交，不能仅因存在另一份草稿而返回冲突；code／派发入口按 created_at、id 选定已有草稿，不新增、不合并、不删除其他草稿。见 `docs/2026-09-21-legacy-draft-compatibility.md`。预留 draft 不计正式提交，普通写入不能改回已提交状态，Admin 独立操作仍受 token／counter 规则保护。无新增 DB 唯一约束，禁止新旧 writer 混跑；小程序配套、Talk Lab 非续接边界及回归见 `docs/2026-09-18-all-assignment-drafts-handoff.md`。

- 報告／恢復專用容器的可重現啟動與 Sidekiq 私有帳密工具在 `ops/reliability/README.md`。工具預設 dry run，啟用時間必須為實際時間，不倒填或刪除 runtime 檔來重設。後續 source bind mount 發布須同時盤點主 worker、`operations_reports` 與 `generation_recovery`，安全 drain 在途工作後才換應用程式；不得只照舊重啟主 worker。私有 runtime／帳密檔不入 Git；SMTP 接受不等於收件匣驗收。

- 普通 grading 更新在行锁内禁止已提交记录改回 pending/draft（文字及整数 enum）；Admin 的独立 `request_admin_rerun!` 仍可覆盖未知／在途状态，以 token 防止旧任务回写，不代表取消了外部 Dify 调用。自动恢复不能继承 Admin 强制覆盖权限。安全诊断只输出状态，不输出 provider context／密钥／原文。健康指令 `bundle exec rake aienglish:recovery_status` 只证明扫描执行，不证明正式 Dify 恢复成功。见 `docs/2026-09-17-production-release-candidate.md`。

- 用户要求交付的代码、migration 及非敏感部署配置应按授权提交 GitHub，记录对应 commit；普通变更可按上述规则部署到指定测试服务器，涉及 migration 的发布及正式部署交由工程师。不得只留在服务器，上述数据库部署限制始终适用。
- 密钥、数据库备份、`.env` 实际值、本地 `output/` 产物及其他无关修改不得顺带提交。推送前核对远端更新，不 force push。
- 修改范围以当前任务为准；不因 Backend 改动而顺带修改或发布微信小程序、Listening 或其他服务。

## 學校子帳號的班級密碼授權

- 學校學生重設密碼同時清除 Devise 的 `locked_at`、`failed_attempts`、`unlock_token`，與新密碼在學生 row lock 內一次 validated save，沿用 actor row lock 與精確班級授權。密碼驗證失敗不得先解鎖；audit 記錄 `account_unlocked`，不記密碼。兩個 API 別名及既有老師後台登入均須驗證；`school_password_reset_transaction_test.rb` 使用實際 transaction 驗證 audit 失敗回滾及同一學生併發重設，鎖等待觀察須 uncached。見 `docs/school-password-reset-unlock-2026-09-23.md`。
- 學校密碼授權使用 `GeneralUser.meta.school_password_access`，不新增表／欄位。新增流程從本校 active TeacherAssignment 的 teacher 選人，保留其角色、密碼、features 和原 school_id；meta 另記後台 school_id。舊獨立子帳號維持 school_password_manager。權限寫入只經本校主管理員接口；一般資料更新不可接受 meta／角色／學校歸屬欄位。
- 必須同時保護 `/api/school/v1`、`/api/school_admin/v1` 及共用 API；授權精確匹配 active 学年＋active enrollment＋班名，空授權不得回退整校資料。撤權、停用及新密碼要檢查已發後台 token；既有老師的教學登入不受後台停用／移除影響。
- 子帳號刪除使用既有 meta 的 deleted_at、enabled、grants 與 session_version，保留歷史及 Email 唯一性；不可透過 PATCH 復活。`SchoolPasswordAccess` 必須在 Devise modules 之後 include，避免 authentication hook 被覆蓋。班級清單為批次查詢，學年 include_classes 回應只供獲授權班級；class_name_exact 不可回退模糊比對。見 `docs/school-portal-management-2026-09-21.md`。
- 學校 API 的唯讀 Rails runner 核查須與 ApiController 一樣切到 `public` tenant；不能用 runner 預設 search_path 查不到帳號便判斷正式資料不存在。不得輸出 JWT、密碼或學生資料。
- 回歸：`test/integration/school_password_delegation_test.rb` 加 `test/integration/admin_api_authentication_test.rb`，沿用明確隔離 test DB；沒有本次 migration。詳情及部署狀態見 `docs/school-password-delegation.md`。

- 既有老師的後台 JWT 只在 school session 派發時帶 school_password_version；它在通用 API 也受 allowlist 限制。普通教學 JWT 不帶此欄位。不可將老師持久角色改成管理員，也不可用後台 enabled/deleted_at 停用教學登入。單一老師目前只有一個後台學校上下文，不可跨校覆蓋既有授權。詳見 `docs/school-teacher-portal-access-2026-09-21.md`；回歸包含撤權前後舊／新教學登入與作業列表。

- 學校 API 清單不得為提交數量 preload 全部 essay_gradings；用本頁作業 ID 做 grouped count，詳情／總覽的 grading 載入保持 10／30 筆界限。受限學生 scope 直接在同一 enrollment join 套用學校、active 狀態及按學年分組的精確班級條件，不可拆成年份／班級交叉組合。效能回歸、隔離 benchmark 與實測限制見 `docs/school-portal-api-performance-2026-09-21.md`。

- 學校作業 scope 不可僅按老師任教關係：有明確學年的作業須屬本校學年；無學年的舊作業僅在老師沒有任何他校任教關係時保留相容讀取，跨校歸屬不明則隱藏，不猜測歸屬。首頁 grading／統計也必須重用 assignments_scope。Snapshot 與 audit_logs 回傳均遮蔽历史密碼 metadata。複查與回歸見 `docs/school-portal-bug-review-2026-09-21.md`。
