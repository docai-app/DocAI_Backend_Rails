# AIEnglish × 第三方站点：账号绑定与作业推送对接文档

> **版本**：v1.0  
> **日期**：2026-08-27  
> **适用对象**：KonnecAI（原 To-Do-Share-AI）及其他希望接收 AIEnglish 作业推送的合作方  
> **前置依赖**：已完成 [AIEnglish OAuth 账号登录对接](./AIEnglish%20OAuth%20账号登录对接文档.md)（Authorization Code + PKCE）  
> **身份主体**：AIEnglish `GeneralUser`（UserInfo `sub` = `general_users.id`）  
> **API 版本**：`api_version = 2026-08-27`

---

## 0. 你能获得什么

在用户用 AIEnglish 账号登录贵方站点之后，再完成本文对接，即可：

| 能力 | 说明 |
|------|------|
| **账号绑定上报** | 把贵方本地用户 ID 与 AIEnglish `sub` 关联，供管理后台统计与作业推送匹配 |
| **作业推送** | 老师在 AIEnglish 向该学生分配 / 更新作业时，AIEnglish **主动 POST** 到贵方 Webhook |
| **解绑同步** | 用户解绑时，AIEnglish 吊销 OAuth 并（若已启用推送）通知贵方清理本地关联 |

```text
用户 ──OAuth──► AIEnglish IdP ──code/token──► 贵方站点
                      │
                      │ ① POST /api/v1/oauth/partner_bindings（贵方上报绑定）
                      │
老师分配作业 ─────────┤
                      │ ② POST 贵方 Webhook（AIEnglish 出站推送）
                      ▼
                 贵方收件箱 / Todo
```

> **说明：** OAuth 登录本身见《AIEnglish OAuth 账号登录对接文档》。本文只覆盖 **绑定 + Webhook**。

---

## 1. 开通清单（找 AIEnglish 管理员）

请管理员在平台后台为贵方创建 / 配置 OAuth Client，并交付：

| 交付物 | 说明 |
|--------|------|
| `{ISSUER}` | 如 `https://docai-dev.m2mda.com` |
| `client_id` / `client_secret` | OAuth Client 凭证 |
| `redirect_uris` | 已白名单的回调地址 |
| **Webhook URL** | 贵方 HTTPS 接收地址（管理员填入后台） |
| **Webhook `signing_secret`** | HMAC 验签密钥（创建/轮换时**只展示一次**，请妥善保存） |
| 推送开关 | 后台「启用推送」必须打开，否则不会出站 |

管理员侧路径示例：**OAuth 应用 → 详情 → 推送配置**。

贵方需提供给管理员的信息：

1. 站点名称、Homepage URL（建议填 Origin，如 `https://app.konnec.ai`）  
2. OAuth `redirect_uri`（精确匹配）  
3. Webhook URL（必须 `https://`；本地联调可用 `webhook.site` 临时地址）  
4. 需要订阅的事件（默认 `assignment.*`、`oauth.binding.*`、`webhook.ping`）

---

## 2. 端点总表

| 方法 | 路径 | 方向 | 认证 | 说明 |
|------|------|------|------|------|
| `POST` | `{ISSUER}/api/v1/oauth/partner_bindings` | 贵方 → AIEnglish | Bearer **用户** access_token | 上报/更新账号绑定 |
| `POST` | `{ISSUER}/oauth/revoke_binding` | 贵方 → AIEnglish | Bearer **用户** access_token | 解绑：吊销该 user+client 全部 token/grant |
| `POST` | `{贵方 Webhook URL}` | AIEnglish → 贵方 | HMAC 签名头 | 作业 / 绑定事件推送 |
| `POST` | （管理员点「测试 Ping」） | AIEnglish → 贵方 | 同上 | `webhook.ping` 联通性测试 |

OAuth 登录相关端点（`/oauth/authorize`、`/oauth/token`、`/oauth/userinfo`、`/oauth/web_login` 等）见 OAuth 登录文档，本文不重复。

---

## 3. 账号绑定上报（必做）

### 3.1 何时调用

用户完成 OAuth、贵方取得 `access_token` 并调用 UserInfo 拿到 `sub`、且已创建/关联**本地用户**之后，立即由**贵方后端**调用一次（幂等，可重复调用）。

### 3.2 请求

```http
POST {ISSUER}/api/v1/oauth/partner_bindings
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "general_user_id": "{UserInfo.sub}",
  "external_user_id": "{贵方本地用户主键}",
  "external_site": "https://app.konnec.ai"
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `general_user_id` | 建议填 | 必须等于 access_token 对应的 `sub`；可省略，服务端用 token 主体 |
| `external_user_id` | **是** | 贵方侧用户 ID（字符串，建议稳定主键） |
| `external_site` | 否 | 来源站点 Origin；省略则回落 Client 的 `homepage_url` |

### 3.3 成功响应 `201`

```json
{
  "status": "success",
  "data": {
    "id": "uuid",
    "general_user_id": "uuid",
    "external_user_id": "partner-user-001",
    "external_site": "https://app.konnec.ai",
    "status": "active",
    "linked_at": "2026-08-27T06:00:00.000Z"
  }
}
```

### 3.4 错误

| HTTP | 含义 |
|------|------|
| 401 | token 无效 / 用户不存在 |
| 403 | Client 未启用，或 `general_user_id` 与 token `sub` 不一致 |
| 422 | 缺少 `external_user_id` |

### 3.5 示例（Node）

```ts
await fetch(`${ISSUER}/api/v1/oauth/partner_bindings`, {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${accessToken}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    general_user_id: userInfo.sub,
    external_user_id: localUser.id,
    external_site: 'https://app.konnec.ai',
  }),
});
```

### 3.6 未上报绑定的后果

- 管理后台「第三方账号 ID」可能为空（仅有 AIEnglish 侧登录骨架）  
- **作业推送不会匹配到贵方用户**（`partner.external_user_id` 为空或无法路由）  
- **强烈建议：登录成功路径上强制上报**

---

## 4. 解绑（必做对称流程）

用户在贵方点击「解除 AIEnglish 绑定」时，**必须**按以下顺序：

1. 用当前用户的 AIEnglish `access_token` 调用：

```http
POST {ISSUER}/oauth/revoke_binding
Authorization: Bearer {access_token}
```

成功示例：

```json
{
  "success": true,
  "message": "OAuth binding revoked. You can authorize again."
}
```

2. 清除贵方本地 session / `meta.authProviders.aienglish` 等  
3. （若已启用 Webhook）稍后会收到 `oauth.binding.revoked`，用于归档同步 Todo  

> **错误示例：** 只清本地绑定、不调 `revoke_binding` → AIEnglish 侧仍认为有效绑定，作业会继续推送。

---

## 5. Webhook 接收规范

### 5.1 基本要求

| 项 | 要求 |
|----|------|
| URL | 公网 HTTPS（生产）；开发可用 webhook.site 验证 |
| 方法 | 仅 `POST` |
| 响应 | **尽快返回 2xx**（建议 &lt; 3s）；重逻辑放队列 |
| 幂等 | 以 envelope.`id`（= `X-AIEnglish-Delivery-Id`）去重 |
| 验签 | **必须**校验 HMAC（见下） |

### 5.2 请求头

| Header | 说明 |
|--------|------|
| `Content-Type` | `application/json` |
| `User-Agent` | `AIEnglish-Webhook/1.0` |
| `X-AIEnglish-Event` | 事件类型，如 `assignment.distributed` |
| `X-AIEnglish-Delivery-Id` | 投递 ID（UUID），与 body.`id` 一致 |
| `X-AIEnglish-Timestamp` | Unix 秒级时间戳 |
| `X-AIEnglish-Signature` | `sha256=` + hex(HMAC-SHA256) |

### 5.3 签名算法

```text
signed_payload = "{timestamp}." + raw_request_body
signature      = HMAC_SHA256_HEX(signing_secret, signed_payload)
header_value   = "sha256=" + signature
```

校验步骤：

1. 读取 `X-AIEnglish-Timestamp`、`X-AIEnglish-Signature`  
2. 若 `|now - timestamp| > 300` 秒 → 拒绝（防重放）  
3. 用**原始 body 字符串**（不可先 JSON.parse 再 stringify）计算签名  
4. **恒定时间比较** header 与本地计算结果  
5. 通过后再 `JSON.parse`

### 5.4 验签示例（Node.js / TypeScript）

```ts
import crypto from 'crypto';

export function verifyAiEnglishWebhook(opts: {
  rawBody: string;
  timestampHeader: string | null;
  signatureHeader: string | null;
  signingSecret: string;
  maxSkewSeconds?: number;
}): boolean {
  const { rawBody, timestampHeader, signatureHeader, signingSecret } = opts;
  const maxSkew = opts.maxSkewSeconds ?? 300;
  if (!timestampHeader || !signatureHeader) return false;

  const ts = Number(timestampHeader);
  if (!Number.isFinite(ts)) return false;
  if (Math.abs(Math.floor(Date.now() / 1000) - ts) > maxSkew) return false;

  const expected =
    'sha256=' +
    crypto
      .createHmac('sha256', signingSecret)
      .update(`${ts}.${rawBody}`)
      .digest('hex');

  const a = Buffer.from(expected);
  const b = Buffer.from(signatureHeader);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}
```

**Next.js App Router 注意：** 必须用 `request.text()` 取原始 body，不能先 `request.json()`。

```ts
// app/api/integrations/aienglish/webhook/route.ts（示例路径）
export async function POST(request: Request) {
  const rawBody = await request.text();
  const ok = verifyAiEnglishWebhook({
    rawBody,
    timestampHeader: request.headers.get('x-aienglish-timestamp'),
    signatureHeader: request.headers.get('x-aienglish-signature'),
    signingSecret: process.env.AIENGLISH_WEBHOOK_SECRET!,
  });
  if (!ok) {
    return Response.json({ error: 'invalid_signature' }, { status: 401 });
  }

  const envelope = JSON.parse(rawBody);
  // TODO: 按 envelope.id 幂等入库，再异步处理 envelope.type
  return Response.json({ received: true }, { status: 200 });
}
```

### 5.5 贵方应返回的 HTTP

| 状态码 | AIEnglish 行为 |
|--------|----------------|
| **2xx** | 标记投递成功 |
| **410** | 视为永久失败，不再重试（可用于废弃 URL） |
| **429** | 失败并重试（请尽量带合理负载） |
| **5xx / 超时** | 指数退避重试（约 1m → 5m → 15m → 1h → 6h，默认最多 5 次） |

---

## 6. 事件类型与 Payload

### 6.1 通用 Envelope

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "assignment.distributed",
  "created_at": "2026-08-27T06:00:00Z",
  "api_version": "2026-08-27",
  "client_id": "your-oauth-client-uid",
  "data": {}
}
```

| 字段 | 说明 |
|------|------|
| `id` | 投递唯一 ID，幂等键 |
| `type` | 事件名（与 `X-AIEnglish-Event` 相同） |
| `client_id` | 贵方 OAuth `client_id`（uid） |
| `api_version` | Payload 版本，破坏性变更会升版 |
| `data` | 业务载荷 |

### 6.2 `webhook.ping`（联通测试）

管理员在后台点击「发送测试 Ping」时发送。

```json
{
  "type": "webhook.ping",
  "data": {
    "message": "AIEnglish webhook test ping",
    "sent_at": "2026-08-27T06:00:00Z"
  }
}
```

贵方应返回 2xx。可用于上线前验收。

### 6.3 `oauth.binding.created`

绑定上报成功且 Client 启用推送时可能发送（贵方已有本地状态时可忽略）。

```json
{
  "type": "oauth.binding.created",
  "data": {
    "general_user_id": "uuid",
    "external_user_id": "partner-user-001",
    "external_site": "https://app.konnec.ai",
    "linked_at": "2026-08-27T06:00:00Z"
  }
}
```

### 6.4 `oauth.binding.revoked`

```json
{
  "type": "oauth.binding.revoked",
  "data": {
    "general_user_id": "uuid",
    "external_user_id": "partner-user-001",
    "external_site": "https://app.konnec.ai",
    "revoked_at": "2026-08-27T06:10:00Z",
    "reason": "user_revoke_binding"
  }
}
```

建议处理：标记本地 AIEnglish 关联失效；归档未完成的同步作业 Todo。

### 6.5 `assignment.distributed`（核心）

老师向学生分配作业，且该学生对该 Client 存在 **active** 绑定时推送。

```json
{
  "type": "assignment.distributed",
  "data": {
    "assignment": {
      "id": "uuid",
      "title": "Unit 3 Essay",
      "topic": "Environment",
      "code": "ESS-2026-001",
      "category": "essay",
      "deadline": "2026-09-01T15:59:59Z",
      "url": "https://docai-dev.m2mda.com/assignments/uuid"
    },
    "distribution": {
      "id": "uuid",
      "distribution_type": "individual",
      "school_id": "uuid"
    },
    "student": {
      "general_user_id": "uuid",
      "email": "student@school.edu",
      "nickname": "李四"
    },
    "partner": {
      "external_user_id": "partner-user-001",
      "external_site": "https://app.konnec.ai"
    }
  }
}
```

**路由用户：** 用 `data.partner.external_user_id`（优先）或 `data.student.general_user_id` 映射贵方用户。  
**打开作业：** 使用 `data.assignment.url`（AIEnglish 深链；具体前端路径以环境为准）。

### 6.6 `assignment.updated`

作业分发 deadline 等变更时推送（字段为精简版）。

```json
{
  "type": "assignment.updated",
  "data": {
    "assignment": {
      "id": "uuid",
      "title": "Unit 3 Essay",
      "deadline": "2026-09-05T15:59:59Z",
      "url": "https://docai-dev.m2mda.com/assignments/uuid"
    },
    "distribution": { "id": "uuid" },
    "student": {
      "general_user_id": "uuid",
      "email": "student@school.edu",
      "nickname": "李四"
    },
    "partner": {
      "external_user_id": "partner-user-001",
      "external_site": "https://app.konnec.ai"
    }
  }
}
```

建议：更新本地 Todo 的截止时间，勿新建重复条目（按 `assignment.id` 更新）。

### 6.7 事件订阅

管理员可配置订阅模式，支持通配：

| 模式 | 匹配 |
|------|------|
| `assignment.*` | `assignment.distributed`、`assignment.updated`、… |
| `oauth.binding.*` | `oauth.binding.created`、`oauth.binding.revoked` |
| `webhook.ping` | 测试 Ping |
| 精确名 | 仅该事件 |

未订阅的事件不会投递（`webhook.ping` 测试可强制发送）。

---

## 7. 贵方产品侧建议

### 7.1 建议数据表

**`aienglish_webhook_events`**

| 字段 | 说明 |
|------|------|
| `delivery_id` | 唯一 = envelope.id |
| `event_type` | |
| `payload` | jsonb |
| `processed_at` / `status` | received / processed / failed |

**`aienglish_assignments`（或映射到现有 Todo）**

| 字段 | 说明 |
|------|------|
| `aienglish_assignment_id` | = `data.assignment.id` |
| `local_user_id` | = `external_user_id` |
| `title` / `deadline` / `deep_link_url` | |
| `status` | open / done / archived |

### 7.2 用户界面（建议）

| 界面 | 内容 |
|------|------|
| 登录方式 | 「使用 AIEnglish 登录」+ 已绑定状态 |
| 解绑 | 调 `revoke_binding` 再清本地 |
| 作业收件箱 | 展示 Webhook 同步来的 Assignment；点击跳转 `assignment.url` |

### 7.3 KonnecAI 映射示例

| AIEnglish 事件 | KonnecAI 行为 |
|----------------|---------------|
| `assignment.distributed` | 为学生创建/更新 Todo（`source: aienglish`） |
| `assignment.updated` | 更新原 Todo deadline |
| `oauth.binding.revoked` | 归档相关 Todo，提示重新绑定 |

---

## 8. 安全要求

1. `signing_secret`、`client_secret` 只放服务端环境变量，禁止进前端包  
2. Webhook 必须验签 + 时间窗；失败返回 401  
3. 幂等：同一 `delivery_id` 只处理一次  
4. 生产 URL 使用 HTTPS；勿在公开仓库提交真实 secret  
5. PII：payload 含邮箱，按贵方隐私政策处理  

---

## 9. 联调与验收清单

### 9.1 最小联调（不依赖完整 UI）

1. 管理员配置 Webhook URL + 启用推送 + 交付 `signing_secret`  
2. 管理员点「发送测试 Ping」→ 贵方返回 2xx → 后台投递日志 `delivered`  
3. 用户 OAuth 登录 → 贵方调 `partner_bindings` → 后台「账号绑定」可见第三方账号 ID  
4. 老师给该学生分配作业 → 贵方收到 `assignment.distributed`  
5. 用户 `revoke_binding` → 收到 `oauth.binding.revoked` → 再分配不再推给该用户  

### 9.2 验收标准

- [ ] Ping 验签通过且 2xx  
- [ ] 重复投递同一 `id` 不产生重复业务对象  
- [ ] 绑定上报后 Admin 可见 `external_user_id`  
- [ ] 作业推送可按 `external_user_id` 路由到正确用户  
- [ ] 解绑后不再收到新作业推送  
- [ ] 签名错误返回 401，且投递日志可见失败  

### 9.3 常见问题

| 现象 | 原因 / 处理 |
|------|-------------|
| 投递 404（webhook.site） | URL 占位符无效，需用真实 inbox UUID |
| 一直 `pending` | AIEnglish Sidekiq 未运行 |
| 有登录无作业推送 | 未调 `partner_bindings`，或推送未启用，或学生无 active 绑定 |
| 验签失败 | 未用 raw body；secret 错误；时钟偏差 &gt; 300s |
| 只清本地未调 revoke | AIEnglish 仍会推送 |

---

## 10. 环境变量建议（贵方）

```bash
AIENGLISH_OAUTH_ISSUER=https://docai-dev.m2mda.com
AIENGLISH_OAUTH_CLIENT_ID=...
AIENGLISH_OAUTH_CLIENT_SECRET=...
AIENGLISH_OAUTH_REDIRECT_URI=https://app.konnec.ai/api/auth/aienglish/callback
AIENGLISH_WEBHOOK_SECRET=...   # 管理员轮换后交付的 signing_secret
```

---

## 11. 相关文档

| 文档 | 内容 |
|------|------|
| [AIEnglish OAuth 账号登录对接文档](./AIEnglish%20OAuth%20账号登录对接文档.md) | 登录 / PKCE / web_login / UserInfo |
| [oauth_partner_账号绑定统计与作业推送实施方案](./oauth_partner_账号绑定统计与作业推送实施方案_2026_08_27_zh.md) | 内部实施方案（含 Admin 能力） |

---

## 12. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0 | 2026-08-27 | 初版：绑定上报、Webhook 验签、作业事件、解绑、验收清单（面向 KonnecAI / 其他合作方） |

---

**对接支持：** 请将 `{ISSUER}`、Client 开通与 Webhook 配置问题联系 AIEnglish 平台管理员；工程问题可附带 `X-AIEnglish-Delivery-Id` 与投递日志截图以便排查。
