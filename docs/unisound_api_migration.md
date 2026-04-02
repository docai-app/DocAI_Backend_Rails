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

已与原 Next.js `route.ts` 保持一致，返回字段包括：

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

## 错误格式（与原逻辑对齐）

- 参数缺失：`400` + `{ error: 'Missing text or audio file' }`
- 云知声响应异常：`500` + `{ error, details }`
- 处理结果失败：`500` + `{ error: 'Failed to process result data' }`
- 网络超时/无响应：`500` + `{ error: 'No response from external API', details }`

## 相关代码位置

- 控制器：`app/controllers/api/v1/unisound_controller.rb`
- 路由：`config/routes.rb`（`post 'unisound/eval', to: 'unisound#create'`）

## 环境变量

支持通过环境变量覆盖云知声 `appkey`：

- `UNISOUND_APPKEY`

未设置时会回退到当前兼容值（与旧实现一致），建议在生产环境配置为环境变量，避免明文硬编码。

## 前端改造建议

将原先请求：

- `/api/unisound`（Next.js API Route）

改为：

- `${后端域名}/api/v1/unisound/eval`

其余请求参数（`text` + `voice`）与响应字段无需改动，可无缝复用现有解析逻辑。

## 观测与排障建议

1. 在 Rails 侧增加请求链路日志（请求 ID、耗时、云知声响应码）。
2. 对外部请求失败记录 `status/code/body`，便于定位云知声侧问题。
3. 监控接口 P95/P99 与 5xx 比例，验证迁移后是否显著改善。
