# 云知声接口迁移说明（Next.js -> Rails API）

## 背景

原流程由前端页面调用 Next.js API Route（`essay-checker/src/app/api/unisound/route.ts`）再转发到云知声。  
在 Vercel 场景中，网络抖动、函数超时、日志追踪分散，容易出现慢响应和偶发错误难定位的问题。

本次迁移将云知声转发逻辑下沉到后端 Rails 服务（`DocAI_Backend_Rails`），由前端直接调用服务器 API。

## 新接口

- **Method**: `POST`
- **Path**: `/api/v1/unisound/eval`
- **Content-Type**: `multipart/form-data`
- **字段**:
  - `text`: 要评测的文本
  - `voice`: 音频文件（wav）

## 返回格式

**成功时 HTTP 200 直接返回评测对象**（无 `{ success, data }` 包装），字段与 `essay-checker/src/app/api/unisound/eval/route_bobby.ts` 中 `handleResult` 完全一致，包括：

- `origin_data`
- `real_transcript`
- `ipa_transcript`
- `pronunciation_accuracy`
- `real_transcripts`
- `matched_transcripts`
- `real_transcripts_ipa`
- `matched_transcripts_ipa`
- `pair_accuracy_category`
- `start_time`
- `end_time`
- `is_letter_correct_all_words`

## 错误格式（与原 Next.js route 对齐）

- 参数校验：`400` + `{ error: '...' }`（无 `attemptsUsed`）
- 上游失败：`502` / `504` + `{ error, details?, attemptsUsed }`
- 处理/配置异常：`500` / `503` + `{ error, details? }`
- 追踪 ID 在响应头 `x-request-id`（不在 body 中增加额外字段）

## 相关代码位置

- 控制器：`app/controllers/api/v1/unisound_controller.rb`（`rescue_from` 避免 `{ success: false }` 包装）
- 格式化：`app/services/unisound/result_formatter.rb`（对齐 `handleResult`）
- 转发：`app/services/unisound/eval_service.rb`
- 路由：`config/routes.rb`（`post 'unisound/eval', to: 'unisound#create'`）

## 环境变量

云知声凭证（任选一种）：

- `UNISOUND_APP_KEY` + `UNISOUND_APP_SECRET`（推荐）
- `UNISOUND_APPKEY`（`appkey@secret` 合并格式）

可选：

- `UNISOUND_SCORE_COEFFICIENT`（默认 `1.5`）
- `UNISOUND_EVAL_URL`（默认 `https://edu.hivoice.cn/eval/pcm`）

未设置时非 production 会回退到兼容默认值；**production 必须配置凭证**。

## 前端改造（已完成 speaking_pronunciation）

- **推荐**：`POST ${NEXT_PUBLIC_API_SERVER}/api/v1/unisound/eval`（Rails 转发云知声）
- **兼容**：`POST /api/unisound/eval`（Next.js 仅代理到 Rails，不再直连云知声）

请求字段：`text`、`voice`（wav）、可选 `durationMs`。响应字段与原先 Next.js Route 一致。

## 观测与排障建议

1. 在 Rails 侧增加请求链路日志（请求 ID、耗时、云知声响应码）。
2. 对外部请求失败记录 `status/code/body`，便于定位云知声侧问题。
3. 监控接口 P95/P99 与 5xx 比例，验证迁移后是否显著改善。
