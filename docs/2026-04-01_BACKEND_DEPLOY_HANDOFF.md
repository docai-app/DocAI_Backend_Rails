# 2026-04-01 Backend Deploy Handoff

## 1. 本次 backend 已落地的核心功能

- `Essay Type` 存入 `essay_assignments`
- `revised_essay` 存入 `essay_gradings`
- `Teacher Review`
  - `meta.teacher_review`
  - `meta.teacher_review_history`
- `Full / Simplified Report`
- 新 PDF 模板
- `Grammar Phase 2` 第一版保存链
- `History / Restore`
- `speaking audio handoff` 相关后端改动

## 2. Teacher Review 数据规则

- 不覆盖 AI 原始结果
- 老师确认版另存于：
  - `essay_gradings.meta.teacher_review`
- 历史版本另存于：
  - `essay_gradings.meta.teacher_review_history`
- 学生端与报告优先显示老师确认后的最新版本
- 学生端不返回 history

## 3. Grammar 规则

- 已支持：
  - 编辑现有 error
  - 新增 error
  - 删除 error
- `A1 / A2 / B1` 为显示编号，不是稳定存储 ID
- 稳定存储请使用：
  - `sentence_id`
  - `error_id`

## 4. Report 规则

- `Full Report`
  - 完整内容
- `Simplified Report`
  - 精简内容
- 有 school logo 时显示 logo
- 没 logo 时不影响排版
- Page number 统一黑色

## 5. 重要 migration

请确认以下 migration 已在目标环境执行：

- `db/migrate/20260331093000_add_essay_type_and_revised_essay_to_essay_workflow.rb`

## 6. 重要环境变量

### Dify

- `essay_revised_argumentative_writing_app_key`
- `essay_revised_causes_effects_problems_writing_app_key`
- `essay_revised_cause_effect_solution_hybrid_writing_app_key`
- `essay_revised_compare_and_contrast_writing_app_key`
- `essay_grading_supplement_practice_app_key`

### SSL / Runtime

- `SSL_CERT_FILE`
- `REDIS_URL`
- DB 连接参数

## 7. 部署提醒

- 请确保 Sidekiq 与 Redis 正常运行
- `supplementary exercise` 作为后续流程，不阻塞 `graded`
- 若 production 使用不同 CA bundle，请明确设置 `SSL_CERT_FILE`

## 8. 检查结论

本次同步后，以下关键文件已通过 `ruby -c`：

- `app/controllers/api/v1/essay_assignments_controller.rb`
- `app/controllers/api/v1/essay_gradings_controller.rb`
- `app/models/essay_assignment.rb`
- `app/models/essay_grading.rb`
- `app/services/essay_grading_service.rb`
- `app/services/pronunciation_ipa_transcriber_service.rb`
- `app/services/speaking_audio_attachment_normalizer_service.rb`
- `config/routes.rb`

