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

- 狀態報告的作業異常及相關通知異常只列各校 `SchoolAcademicYear.active`：優先使用提交時 `submission_academic_year_id`，缺少時才使用 assignment 的明確學年；不按建立日期、學年名稱或目前 enrollment 猜測。舊學年資料保留、不批量重跑；無法歸屬的紀錄只提示數量。時段活動統計／系統寄送健康維持原範圍。共用篩選及只讀 pending 稽核見 `docs/2026-09-20-report-scope-and-audio-concurrency.md`。
- Preset Speaking answer 音檔上傳在 `AssignmentDraftSession.write(prepare:)` 的短檢查之後、釋放 DB 連線後執行；保存前重新鎖定核對 revision／request_id，恢復原租戶 search_path。不可在外層 transaction 使用 prepare。服務端補上的 answered_at 不可參與請求指紋；失敗上傳不能被當作已保存。回歸 `assignment_audio_preparation_test.rb`；不代表全部附件路徑或正式吞吐量已驗收。

- Redis 防護、私有 ACL 切換、獨立於 Redis 的排程 watchdog 見 `docs/2026-09-19-reliability-hardening-handoff.md`。禁止對正式 Redis 執行 FLUSHALL／FLUSHDB、開放公網 6379 或用 compose down/prune 發布。排程健康須同時核對 registry、worker、tick 和完成 heartbeat；容器存活不能代替排程驗收。Redis credentials／RDB／incident evidence 不入 Git，應用回退仍須保留驗證及網路防護。

- 所有类型的学生草稿写入使用 `AssignmentDraftSession`：学生＋assignment advisory lock、固定 grading ID、request_id 精确重送及 draft_revision 检查。managed draft 缺版本返回 409，不能为兼容旧客户端放宽；历史多草稿保留并要求核对。预留 draft 不计正式提交，普通写入不能改回已提交状态，Admin 独立操作仍受 token／counter 规则保护。无新增 DB 唯一约束，禁止新旧 writer 混跑；小程序配套、Talk Lab 非续接边界及回归见 `docs/2026-09-18-all-assignment-drafts-handoff.md`。

- 報告／恢復專用容器的可重現啟動與 Sidekiq 私有帳密工具在 `ops/reliability/README.md`。工具預設 dry run，啟用時間必須為實際時間，不倒填或刪除 runtime 檔來重設。後續 source bind mount 發布須同時盤點主 worker、`operations_reports` 與 `generation_recovery`，安全 drain 在途工作後才換應用程式；不得只照舊重啟主 worker。私有 runtime／帳密檔不入 Git；SMTP 接受不等於收件匣驗收。

- 普通 grading 更新在行锁内禁止已提交记录改回 pending/draft（文字及整数 enum）；Admin 的独立 `request_admin_rerun!` 仍可覆盖未知／在途状态，以 token 防止旧任务回写，不代表取消了外部 Dify 调用。自动恢复不能继承 Admin 强制覆盖权限。安全诊断只输出状态，不输出 provider context／密钥／原文。健康指令 `bundle exec rake aienglish:recovery_status` 只证明扫描执行，不证明正式 Dify 恢复成功。见 `docs/2026-09-17-production-release-candidate.md`。

- 用户要求交付的代码、migration 及非敏感部署配置应按授权提交 GitHub，记录对应 commit；普通变更可按上述规则部署到指定测试服务器，涉及 migration 的发布及正式部署交由工程师。不得只留在服务器，上述数据库部署限制始终适用。
- 密钥、数据库备份、`.env` 实际值、本地 `output/` 产物及其他无关修改不得顺带提交。推送前核对远端更新，不 force push。
- 修改范围以当前任务为准；不因 Backend 改动而顺带修改或发布微信小程序、Listening 或其他服务。

## 學校子帳號的班級密碼授權

- 學校密碼子帳號使用 `GeneralUser.meta.school_password_access`，角色為 `school_password_manager`，不新增表／欄位。權限寫入只經本校主管理員接口；一般資料更新不可接受 meta／角色／學校歸屬欄位。
- 必須同時保護 `/api/school/v1`、`/api/school_admin/v1` 及共用 API；授權精確匹配 active 学年＋active enrollment＋班名，空授權不得回退整校資料。撤權、停用及新密碼要檢查已發 token。
- 回歸：`test/integration/school_password_delegation_test.rb` 加 `test/integration/admin_api_authentication_test.rb`，沿用明確隔離 test DB；沒有本次 migration。詳情及部署狀態見 `docs/school-password-delegation.md`。
