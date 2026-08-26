# AIEnglish OAuth 账号登录对接文档（第三方站点）

> 版本：v1.1  
> 日期：2026-08-26（v1.1 增补生产联调经验）  
> 适用对象：希望使用 **AIEnglish 账号（GeneralUser）** 登录自家网站 / App 的合作方  
> 协议：OAuth 2.0 Authorization Code + PKCE（S256）  
> 身份主体：仅 AIEnglish `GeneralUser`（学生 / 教师等业务账号），不含管理后台 User  
> 相关内部文档：  
> - 设计：`docs/oauth_oidc_identity_provider_design_2026_08_26_zh.md`  
> - Phase 1 落地：`docs/oauth_idp_phase1_handoff_2026_08_26_zh.md`  
> - 管理后台 OAuth 演示参考：`AIEnglish_Admin_Dashboard_Frontend`（`/login` + `/api/auth/aienglish/*`）

---

## 1. 文档目的与能力边界

本文说明第三方如何把「使用 AIEnglish 账号登录」接到自己的网站，可直接交给合作方工程团队实施。

### 1.1 当前已可用（Phase 1）

| 能力 | 说明 |
|------|------|
| Authorization Code | 浏览器交互式登录唯一支持方式 |
| PKCE S256 | **所有 Client 强制**（含 Confidential） |
| Access Token | **Opaque** 字符串，非 JWT |
| Refresh Token | 支持；**每次刷新都会轮换**（旧 refresh 立即失效） |
| **UserInfo** | `GET /oauth/userinfo`（Bearer access_token；按 scope 返回 claims） |
| 跨域登录桥接 | `POST /oauth/web_login`（合作方自有登录页 → AS Session，见 §7.6） |
| 解绑演示 | `POST /oauth/revoke_binding`（吊销当前 user+client 全部 grant/token，测试用） |
| Client 开通 | **仅 AIEnglish 管理员后台开通**，不可自助注册 |
| Client 门禁 | 必须 `enabled=true` 才能授权登录 |

### 1.2 即将提供（Phase 2，对接时可先预留）

| 能力 | 说明 |
|------|------|
| OpenID Connect `id_token` | JWT，RS256；申请 `openid` scope 后签发 |
| Discovery | `/.well-known/openid-configuration` |
| JWKS | `/oauth/jwks` |
| Token Revocation（RFC 7009） | `POST /oauth/revoke`（标准吊销单 token） |

> **对接建议：** Phase 1 用「code → token → UserInfo 取 `sub` → 己方建会话」即可上生产。若贵方库强依赖 OIDC Discovery / `id_token`，请与我们确认 Phase 2 窗口。

### 1.3 明确不支持

- Implicit Grant / Resource Owner Password Credentials（第三方不得直接收用户密码调 AS 换 token，除 §7.6 规定的 `web_login` 表单桥接）
- 第三方自助注册 Client
- 用 OAuth Access Token 直接调用全部 AIEnglish 业务 API（除非另行开通 Resource API scopes）
- 学校维度 Client 绑定（任意学校的 GeneralUser 均可登录已开通 Client）

---

## 2. 角色与术语

| 术语 | 含义 |
|------|------|
| **IdP / AS** | AIEnglish Authorization Server（`DocAI_Backend_Rails`） |
| **Client** | 贵方应用（由管理员登记的 OAuth Application） |
| **Resource Owner** | 持有 AIEnglish 账号的终端用户（`GeneralUser`） |
| **Issuer / API Base** | OAuth 端点所在主机，下文记为 `{ISSUER}` |
| **Partner Login** | **贵方**托管的账号密码页（非 AIEnglish 主站）；未登录授权时 AS 会跳转到此页 |
| **client_id** | 公开标识（可出现在浏览器 URL） |
| **client_secret** | 机密，**仅允许放在贵方服务端**；创建/轮换时只展示一次 |

### 2.1 环境地址（示例，以管理员下发为准）

| 环境 | `{ISSUER}` 示例 | 说明 |
|------|-----------------|------|
| 开发 | `https://docai-dev.m2mda.com` | 联调常用 |
| 生产 | `https://docai.m2mda.com` | 正式上线 |

| 占位符 | 说明 | 示例 |
|--------|------|------|
| `{REDIRECT_URI}` | 贵方回调，须预先白名单 **精确登记** | `https://partner.example.com/oauth/callback` |
| `{PARTNER_LOGIN}` | 贵方登录页（由 `redirect_uri` 推导，见 §7.2） | `https://partner.example.com/login` |

> **重要：** 未登录时，AS **不会**固定跳到 AIEnglish 主站，而是根据 Client 已登记的 `redirect_uri` 推导贵方登录页 origin（例如 `…/api/auth/…/callback` → `…/login`）。因此合作方通常在自己域名实现登录 UI。

---

## 3. 开通流程（商务 / 运维）

第三方 **不能** 自行创建 Client，请按下列流程：

1. 向 AIEnglish 管理员提交申请（模板见 **附录 B**），至少包含：
   - 应用名称（Consent 页展示）
   - 回调地址列表 `redirect_uris`（**精确匹配**）
   - 贵方 **生产/开发站点 origin**（用于 CORS、`web_login` 白名单，见 §7.6、§9.4）
   - 是否 Confidential（有安全后端 → 推荐 `true`）
   - 所需 scopes（见第 6 节）
2. 管理员在 **Admin Dashboard → OAuth 应用** 创建并 **启用（enable）** Client
3. 创建响应中的 **`client_secret` 只出现一次**，请立即安全保存
4. 管理员交付：`client_id`、`client_secret`、`redirect_uris`、scopes、`{ISSUER}`

**变更回调 / 轮换 Secret / 停用 / 新增合作方域名：** 均须管理员操作。

---

## 4. 推荐架构

### 4.1 Confidential Client + 服务端换 Token（标准，优先）

适用：贵方有稳定后端，且 `{ISSUER}` **未被 Cloudflare Bot Fight 拦截机房 IP**（见 §9.5）。

```text
用户浏览器          贵方前端              贵方后端                 AIEnglish AS
    |                   |                     |                         |
    |-- 点击登录 ------>|                     |                         |
    |                   |-- 302 authorize --->| (写 PKCE 到 session)    |
    |<- 302 authorize URL ---------------------------------------------->|
    |  未登录 → 跳 {PARTNER_LOGIN}?return_to=authorize                   |
    |  用户登录(§7.6) + Consent                                          |
    |<- 302 {REDIRECT_URI}?code&state -----------------------------------|
    |-- 回调 --------->|                     |                         |
    |                   |-- code+verifier -->|                         |
    |                   |                     |-- POST /oauth/token ---->|
    |                   |                     |<- tokens ---------------|
    |                   |                     |-- 建贵方 session         |
    |<- 已登录 ---------|<--------------------|                         |
```

要点：

- **`client_secret` 与换 token 必须在贵方服务端**（或 BFF）完成。
- **PKCE 仍强制**：authorize 与 token 都必须带 challenge / verifier。
- 换 token 成功后调用 `GET /oauth/userinfo` 取 `sub` 关联本地用户。

### 4.2 Public Client（纯 SPA / 移动端无安全后端）

- `confidential=false`，token 交换不可带 secret
- **必须**完整 PKCE；强烈建议仍用 BFF 代理换 token

### 4.3 浏览器换 Token + 服务端写 Session（Cloudflare 场景）

当贵方后端部署在 **Vercel / 其他云机房**，而 `{ISSUER}` 前有 **Cloudflare 人机验证** 时，服务端 `POST /oauth/token` 可能收到 **403 + HTML「Just a moment…」**（见 §9.5）。

此时推荐：

```text
callback 页（浏览器）
  → fetch POST {ISSUER}/oauth/token  （带 credentials，用户浏览器已过 CF）
  → POST 贵方 /oauth/complete        （把 token 交给己方 BFF 写 httpOnly cookie）
  → 跳转贵方已登录页
```

`client_secret` 会短暂出现在浏览器（仅 callback 页内脚本）。**仍须**：
- callback 页为一次性、无第三方脚本；
- 尽快换成贵方 httpOnly session；
- 生产优先请 AIEnglish 运维对 `/oauth/token` 等路径配置 CF 放行（§9.5）。

管理后台演示实现可参考：`AIEnglish_Admin_Dashboard_Frontend/app/api/auth/aienglish/callback` + `complete`。

---

## 5. 端点一览

| 端点 | 方法 | Phase | 调用方 | 说明 |
|------|------|-------|--------|------|
| `{ISSUER}/oauth/authorize` | GET | 1 | 浏览器 | 授权入口 |
| `{ISSUER}/oauth/token` | POST | 1 | **贵方后端**（或浏览器，§4.3） | 换 code / 刷新 token |
| `{ISSUER}/oauth/userinfo` | GET | 1 | 贵方后端 | Bearer access_token；返回 `sub` 等 |
| `{ISSUER}/oauth/web_login` | POST | 1 | 浏览器 form | 跨域登录桥接（§7.6） |
| `{ISSUER}/oauth/revoke_binding` | POST | 1 | 贵方 | 演示：吊销 user+client 全部绑定（§12） |
| `{ISSUER}/oauth/session` | POST/DELETE | 1 | AIEnglish 自有前端 | JWT → AS Session；**第三方通常不用** |
| `{ISSUER}/.well-known/openid-configuration` | GET | 2 | - | OIDC Discovery |
| `{ISSUER}/oauth/jwks` | GET | 2 | - | 验签公钥 |
| `{ISSUER}/oauth/revoke` | POST | 2 | 贵方后端 | RFC 7009 标准吊销 |

Token 请求 Content-Type：`application/x-www-form-urlencoded`

---

## 6. Scopes

| Scope | 推荐 | UserInfo 字段（Phase 1） |
|-------|------|-------------------------|
| `openid` | 是 | 建议申请；Phase 1 主要保证 `sub` 语义 |
| `profile` | 是 | `name`, `nickname`, `updated_at` |
| `email` | 是 | `email`, `email_verified`（当前固定 `false`） |
| `offline_access` | 需长期登录 | 返回 `refresh_token` |

示例：`scope=openid profile email offline_access`

Client 注册时会配置允许的最大 scope；请勿申请未开通项。

---

## 7. 完整授权码流程（Phase 1）

### 7.1 生成 PKCE 与 state（贵方后端）

1. `code_verifier`：43–128 字符，`[A-Za-z0-9-._~]`
2. `code_challenge = BASE64URL(SHA256(code_verifier))`，`method=S256`
3. `state`：防 CSRF，绑定用户浏览器会话
4. 将 `code_verifier`、`state` 存入 **贵方服务端 session** 或 **签名 state**（见 §9.3）

**Node.js 示例：**

```javascript
import crypto from 'crypto';

function base64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function createPkce() {
  const codeVerifier = base64url(crypto.randomBytes(32));
  const codeChallenge = base64url(
    crypto.createHash('sha256').update(codeVerifier).digest()
  );
  const state = base64url(crypto.randomBytes(16));
  return { codeVerifier, codeChallenge, state };
}
```

### 7.2 引导用户打开授权页

```http
GET {ISSUER}/oauth/authorize
  ?response_type=code
  &client_id={CLIENT_ID}
  &redirect_uri={REDIRECT_URI}
  &scope=openid%20profile%20email%20offline_access
  &state={STATE}
  &code_challenge={CODE_CHALLENGE}
  &code_challenge_method=S256
```

| 参数 | 必填 | 说明 |
|------|------|------|
| `response_type` | 是 | 固定 `code` |
| `client_id` | 是 | 管理员下发 |
| `redirect_uri` | 是 | 与白名单 **完全一致** |
| `scope` | 是 | 空格分隔，URL 编码 |
| `state` | **强烈建议** | 回调必须校验 |
| `code_challenge` / `code_challenge_method` | **是** | 仅 `S256` |
| `nonce` | Phase 2 | 写入 `id_token` |

**用户未在 AS 登录时（由 AIEnglish AS 自动处理）：**

1. AS 根据 Client 登记的 `redirect_uri` 推导 `{PARTNER_LOGIN}`  
   例：`https://essay-admin.docai.net/api/auth/aienglish/callback`  
   → 跳转 `https://essay-admin.docai.net/login?return_to={encode(authorize_url)}`
2. 用户在 **贵方登录页** 输入 AIEnglish 账号密码（§7.6）
3. 回到 `/oauth/authorize`，展示 Consent（`trusted` Client 可能跳过）
4. 同意 → 302：

```text
{REDIRECT_URI}?code={CODE}&state={STATE}
```

拒绝：

```text
{REDIRECT_URI}?error=access_denied&state={STATE}
```

### 7.3 回调换 Token（贵方后端 — 标准模式）

1. 校验 `state`
2. **仅服务端** 换 token：

```http
POST {ISSUER}/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code={CODE}
&redirect_uri={REDIRECT_URI}
&client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET}
&code_verifier={CODE_VERIFIER}
```

Public Client 省略 `client_secret`。

**成功响应示例：**

```json
{
  "access_token": "……opaque……",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "……opaque……",
  "scope": "openid profile email offline_access"
}
```

3. **授权码一次性**，TTL 约 **10 分钟**；勿重复用同一 `code`
4. `GET /oauth/userinfo` 取 `sub`（§7.5）
5. 建立贵方 session；清除 `code_verifier` / `state`

### 7.4 刷新 Access Token

```http
POST {ISSUER}/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
&refresh_token={REFRESH_TOKEN}
&client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET}
```

**Refresh Token Rotation：** 每次成功刷新返回 **新** `refresh_token`，旧值 **立即失效**；必须覆盖存储。

### 7.5 使用 Access Token 与 UserInfo（Phase 1 已可用）

```http
GET {ISSUER}/oauth/userinfo
Authorization: Bearer {ACCESS_TOKEN}
Accept: application/json
```

**响应示例（scope 含 profile + email）：**

```json
{
  "sub": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "name": "Alice",
  "nickname": "Alice",
  "updated_at": "2026-08-26T10:00:00+08:00",
  "email": "student@school.edu",
  "email_verified": false
}
```

| 字段 | 说明 |
|------|------|
| **`sub`** | **稳定主键**（GeneralUser UUID 字符串）；本地账号关联必须用 `sub` |
| `email` | 展示/通知可用；变更时仍以 `sub` 为准 |

若 token 无效：`401` + `{"error":"invalid_token",…}`

> **注意：** 从 **云机房后端** 调 userinfo 也可能被 Cloudflare 拦截；可改为在用户浏览器侧调用（需 CORS，§9.4），或请运维放行。

### 7.6 跨域账号登录：`POST /oauth/web_login`

当贵方站点与 `{ISSUER}` **不同域** 时，**禁止**用 `fetch` 跨域调 `POST /general_users/sign_in.json` 再在浏览器里指望 AS Session 生效 —— `SameSite=Lax` 下跨站 XHR **写不了** AS 的 session cookie。

**正确做法：** 在贵方登录页用 **HTML form 整页 POST** 到 AS：

```http
POST {ISSUER}/oauth/web_login
Content-Type: application/x-www-form-urlencoded

email={EMAIL}
&password={PASSWORD}
&return_to={ENCODED_AUTHORIZE_URL}
&login_origin={ENCODED_PARTNER_ORIGIN}
```

| 字段 | 说明 |
|------|------|
| `email` / `password` | GeneralUser 凭据 |
| `return_to` | 完整 authorize URL；须通过 AS `ReturnToValidator`（仅允许 `{ISSUER}` 下 `/oauth/authorize`） |
| `login_origin` | 贵方站点 origin，如 `https://partner.example.com`；**须事先加入 AS 白名单** |

**成功：** AS 建立 session → `302` 到 `return_to`（继续 OAuth）  
**失败：** `302` 到 `{login_origin}/login?return_to=…&error=…`

**前端示例（JavaScript）：**

```javascript
function submitWebLogin(email, password, returnTo) {
  const issuer = 'https://docai-dev.m2mda.com';
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = `${issuer}/oauth/web_login`;
  for (const [name, value] of Object.entries({
    email,
    password,
    return_to: returnTo,
    login_origin: window.location.origin
  })) {
    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = name;
    input.value = value;
    form.appendChild(input);
  }
  document.body.appendChild(form);
  form.submit();
}
```

开通 Client 时请将贵方 **开发/生产 origin** 一并提供给管理员配置白名单。

---

## 8. 贵方账号关联建议

| 步骤 | 建议 |
|------|------|
| 首次登录 | 用 UserInfo `sub` 查本地用户；不存在则创建并绑定 `aienglish_sub` |
| Email | 展示/通知；**关联键仍是 `sub`** |
| 会话 | 贵方 Session / JWT；勿长期把 AS `access_token` 当全站 session |
| 续期 | 服务端 `refresh_token`；失败则重新 authorize |
| 退出 | 清贵方 session；可选调 AS 吊销（§12） |

---

## 9. 安全与生产注意事项

### 9.1 基础安全（必须）

1. 生产全程 **HTTPS**
2. **`redirect_uri` 精确匹配**（scheme / host / path / 尾斜杠）
3. **校验 `state`**
4. **`client_secret` 仅服务端**；禁止进 Git / 前端包
5. **强制 PKCE S256**
6. **Code 仅后端换一次 token**（浏览器换 token 模式见 §4.3 例外）
7. **Refresh 轮换**后必须更新存储
8. **日志脱敏**（勿打印 code / token / secret）

### 9.2 跨站 Cookie 与登录

| 场景 | 结果 |
|------|------|
| 贵方页 `fetch` AS 登录 API + `credentials: include` | ❌ 通常 **无法** 建立 AS session |
| 贵方页 **form POST** `{ISSUER}/oauth/web_login` | ✅ 可建立 AS session |
| 用户直接访问 AS 域名登录 | ✅（不适合第三方 UX） |

### 9.3 PKCE verifier 存储

跨站 redirect 回到 callback 时，临时 PKCE cookie 可能丢失（Safari / 跨站策略）。

可选方案（任选其一）：

1. **服务端 session** 存 verifier（同域 BFF 最稳）
2. **HMAC 签名 state** 内嵌 verifier（演示 Client 采用；`state` 密钥仅服务端）
3. 浏览器换 token（§4.3）减少对 PKCE cookie 的依赖

### 9.4 CORS（浏览器直连 AS 时）

若 callback 在 **浏览器** 调 `/oauth/token` 或 `/oauth/userinfo`，贵方 origin 须在 AS CORS 白名单（开通 Client 时提交域名）。请求示例：

```javascript
await fetch(`${ISSUER}/oauth/token`, {
  method: 'POST',
  credentials: 'include',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ /* … */ })
});
```

### 9.5 Cloudflare / 云机房 IP（重要）

**现象：** 贵方 **服务端** `POST {ISSUER}/oauth/token` 返回 **403**，body 为 Cloudflare「Just a moment…」HTML；本地开发正常。

**原因：** AS 前 Cloudflare Bot Fight 拦截数据中心 IP（Vercel、AWS 等）。

**处理优先级：**

1. **推荐（运维）：** 在 Cloudflare 对 `{ISSUER}` 配置规则，对以下路径 **跳过 Bot Fight / Managed Challenge**：
   - `/oauth/token`
   - `/oauth/userinfo`
   - `/oauth/revoke_binding`
   - `/oauth/web_login`
2. **应用层绕过（已实现于 Admin 演示）：** callback 页由 **浏览器** 换 token → POST 贵方 BFF 写 session（§4.3）
3. **解绑 / 刷新：** 若服务端被拦，同样改为浏览器带 Bearer 调 AS，或由运维放行

### 9.6 redirect_uri 规范

| 允许 | 不允许 |
|------|--------|
| `https://app.example.com/oauth/callback` | 通配 `https://*.example.com/*` |
| 开发 Client 登记 `http://localhost:3000/...` | 生产使用未登记回调 |
| path / query 与登记完全一致 | `javascript:` 等 |

---

## 10. 错误码与排查

### 10.1 授权阶段

| error | 常见原因 |
|-------|----------|
| `unauthorized_client` | Client 未 enable |
| `invalid_request` | 缺 PKCE 或 method≠S256 |
| `invalid_client` | client_id 错误 |
| `invalid_scope` | scope 未开通 |
| `access_denied` | 用户拒绝 |

未登录 → 302 到 `{PARTNER_LOGIN}`，不是 JSON error。

### 10.2 Token 阶段

| error | 常见原因 |
|-------|----------|
| `invalid_grant` | code 过期/已用、verifier 不匹配、redirect_uri 不一致、refresh 已轮换 |
| `invalid_client` | secret 错误 |
| `unauthorized_client` | Client 已禁用 |

### 10.3 生产联调自检

- [ ] Client 已 `enabled`
- [ ] `redirect_uri` 与登记 **逐字** 一致
- [ ] authorize 带 PKCE S256
- [ ] token 带同会话 `code_verifier`
- [ ] Confidential 带正确 `client_secret`
- [ ] `state` 往返一致
- [ ] 跨域登录用 **form POST** `/oauth/web_login`，非 fetch 登录
- [ ] 贵方 origin 已加 CORS + `web_login` 白名单
- [ ] 云部署换 token 若 403 HTML → Cloudflare（§9.5）
- [ ] UserInfo 用 `sub` 关联账号
- [ ] refresh 成功后更新为新 refresh_token

---

## 11. 参考实现

### 11.1 标准 BFF：启动登录（Next.js 示意）

```typescript
// GET /api/auth/start
import { NextResponse } from 'next/server';
import { createPkce } from '@/lib/pkce';

export async function GET() {
  const { codeVerifier, codeChallenge, state } = createPkce();
  const res = NextResponse.redirect(buildAuthorizeUrl({ codeChallenge, state }));
  res.cookies.set('oauth_verifier', codeVerifier, { httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 600 });
  res.cookies.set('oauth_state', state, { httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 600 });
  return res;
}
```

### 11.2 标准 BFF：回调换 Token

```typescript
// GET /api/auth/callback
export async function GET(req: Request) {
  const url = new URL(req.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  const verifier = /* read cookie */;
  const expectedState = /* read cookie */;
  if (!code || state !== expectedState || !verifier) {
    return new Response('Invalid OAuth state', { status: 400 });
  }

  const tokenRes = await fetch(`${ISSUER}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: REDIRECT_URI,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      code_verifier: verifier
    })
  });
  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    // 若 err 含 "Just a moment" → 见 §9.5
    return new Response(`Token exchange failed: ${err.slice(0, 500)}`, { status: 400 });
  }
  const tokens = await tokenRes.json();

  const userRes = await fetch(`${ISSUER}/oauth/userinfo`, {
    headers: { Authorization: `Bearer ${tokens.access_token}` }
  });
  const user = await userRes.json();
  // 用 user.sub 建本地 session …
}
```

### 11.3 Cloudflare 场景：浏览器换 Token + complete

callback 返回 HTML，由浏览器 `fetch` AS `/oauth/token`，再 POST 贵方 BFF：

```javascript
// callback 页内（简化）
const tokenRes = await fetch(ISSUER + '/oauth/token', {
  method: 'POST',
  credentials: 'include',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({
    grant_type: 'authorization_code',
    code, redirect_uri, client_id, client_secret, code_verifier
  })
});
const tokens = await tokenRes.json();
await fetch('/api/auth/complete', {
  method: 'POST',
  credentials: 'include',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(tokens)
});
location.replace('/app');
```

完整可参考：`AIEnglish_Admin_Dashboard_Frontend/app/api/auth/aienglish/callback` + `complete`。

### 11.4 curl 手工换 Token

```bash
curl -sS -X POST "$ISSUER/oauth/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=authorization_code" \
  -d "code=$CODE" \
  -d "redirect_uri=$REDIRECT_URI" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "code_verifier=$CODE_VERIFIER"
```

---

## 12. 解绑与 Token 生命周期

### 12.1 演示解绑 `POST /oauth/revoke_binding`

吊销 **当前 access_token 对应用户 + Client** 的全部 grant/token，并清除 AS session（便于重新走 Consent）。

```http
POST {ISSUER}/oauth/revoke_binding
Authorization: Bearer {ACCESS_TOKEN}
```

成功：`{"success":true,"message":"OAuth binding revoked. You can authorize again."}`

> 此为 AIEnglish 扩展端点，非 RFC 7009。标准 `POST /oauth/revoke` 计划在 Phase 2。  
> 若从云机房调用被 Cloudflare 拦截，请浏览器带 Bearer 调用（同 §9.5）。

### 12.2 TTL（当前配置）

| 凭证 | TTL（约） |
|------|-----------|
| Authorization Code | 10 分钟，一次性 |
| Access Token | 1 小时 |
| Refresh Token | 服务端策略；**每次刷新轮换** |

---

## 13. Phase 2 OIDC 预告

上线后将提供 `id_token`（RS256）、Discovery、JWKS、标准 `/oauth/revoke`。对接方届时需校验 `iss` / `aud` / `exp` / `nonce` 与 JWKS 签名。

---

## 14. 与 AIEnglish 自有产品登录的关系

| 场景 | 凭证 |
|------|------|
| 用户直接使用 AIEnglish Web / App | Devise JWT |
| 第三方「AIEnglish 登录」 | OAuth access/refresh + UserInfo `sub` |

OAuth Token **不能**默认当作 AIEnglish 全站 API 通用 JWT。

---

## 15. 上线检查表（合作方）

- [ ] 已取得 `client_id` / `client_secret` / `{ISSUER}` / 已登记 `redirect_uri`
- [ ] Client **已启用**
- [ ] Authorization Code + PKCE S256 + `state` 校验
- [ ] 跨域登录：`POST /oauth/web_login`（form），origin 已白名单
- [ ] Token 交换：服务端优先；Cloudflare 403 时改 §4.3 或请运维放行
- [ ] UserInfo 取 `sub` 关联本地用户
- [ ] Refresh 轮换落库
- [ ] 浏览器调 AS 时已确认 CORS
- [ ] 日志脱敏；失败路径有用户提示
- [ ] （可选）Phase 2：`id_token` / Discovery / revoke

---

## 16. 支持与变更

- **开通 / 启用 / 改回调 / 轮换 Secret / CORS / web_login 白名单：** 联系 AIEnglish 管理员  
- **协议变更：** 以本文档版本号与管理员通知为准  
- **内部实现：** `oauth_idp_phase1_handoff_2026_08_26_zh.md`  
- **可运行演示：** `https://essay-admin.docai.net/login`（需对应 Client 与环境变量）

---

## 附录 A：Authorize URL 模板

```text
{ISSUER}/oauth/authorize
  ?response_type=code
  &client_id={CLIENT_ID}
  &redirect_uri={URL_ENCODED_REDIRECT_URI}
  &scope=openid%20profile%20email%20offline_access
  &state={STATE}
  &code_challenge={CODE_CHALLENGE}
  &code_challenge_method=S256
```

## 附录 B：申请开通信息模板

```text
应用名称：
环境：开发 / 预发 / 生产
redirect_uris（每行一个，精确）：
  -
  -
合作方站点 origin（CORS + web_login 白名单，每行一个）：
  - https://partner.example.com
  - http://localhost:3000
Client 类型：Confidential / Public
所需 scopes：openid profile email offline_access
联系人 / 邮箱：
隐私政策 URL（可选）：
预计上线日期：
是否部署在 Vercel 等云机房（便于评估 Cloudflare 策略）：
```

## 附录 C：常见失败对照

| 现象 | 优先检查 |
|------|----------|
| authorize 立刻 `unauthorized_client` | Client 未 enable |
| PKCE / `invalid_request` | challenge / method |
| 登录成功但 token `invalid_grant` | redirect_uri 不一致；code 重用；verifier 错误 |
| token 403 + HTML「Just a moment」 | Cloudflare 拦云机房 IP（§9.5） |
| 反复跳回登录页、authorize 仍匿名 | 跨域 fetch 登录未写 AS session → 改 web_login（§7.6） |
| callback 无 access_token cookie | 同上；或 Cloudflare；或 code 已用过 |
| UserInfo 401 | access_token 过期或已吊销 |
| refresh 全部失败 | 使用了已轮换的旧 refresh |

## 附录 D：端到端时序（跨域合作方）

```text
1. 用户 → 贵方「AIEnglish 登录」
2. 贵方后端 → 302 {ISSUER}/oauth/authorize?…&redirect_uri=贵方callback
3. AS 未登录 → 302 贵方/login?return_to=authorize_url
4. 用户 form POST {ISSUER}/oauth/web_login → AS session → 302 authorize
5. Consent → 302 贵方callback?code&state
6. 贵方换 token（服务端 §11.2 或浏览器 §11.3）
7. GET /oauth/userinfo → sub → 贵方 session
8. 用户进入贵方已登录态
```

---

*v1.1 变更摘要：修正 UserInfo 为 Phase 1 可用；补充跨域 web_login、Cloudflare/云机房换 token、浏览器换 token 模式、revoke_binding 与生产联调清单。*
