# AIEnglish OAuth 账号登录对接文档（第三方站点）

> 版本：v1.0  
> 日期：2026-08-26  
> 适用对象：希望使用 **AIEnglish 账号（GeneralUser）** 登录自家网站 / App 的合作方  
> 协议：OAuth 2.0 Authorization Code + PKCE（S256）  
> 身份主体：仅 AIEnglish `GeneralUser`（学生 / 教师等业务账号），不含管理后台 User  
> 相关内部文档：  
> - 设计：`docs/oauth_oidc_identity_provider_design_2026_08_26_zh.md`  
> - Phase 1 落地：`docs/oauth_idp_phase1_handoff_2026_08_26_zh.md`

---

## 1. 文档目的与能力边界

本文说明第三方如何把「使用 AIEnglish 账号登录」接到自己的网站。

### 1.1 当前已可用（Phase 1）

| 能力 | 说明 |
|------|------|
| Authorization Code | 浏览器交互式登录唯一支持方式 |
| PKCE S256 | **所有 Client 强制**（含 Confidential） |
| Access Token | **Opaque** 字符串，非 JWT |
| Refresh Token | 支持；**每次刷新都会轮换**（旧 refresh 立即失效） |
| Client 开通 | **仅 AIEnglish 管理员后台开通**，不可自助注册 |
| Client 门禁 | 必须 `enabled=true` 才能授权登录 |

### 1.2 即将提供（Phase 2，设计已锁定，对接时可先按约定预留）

| 能力 | 说明 |
|------|------|
| OpenID Connect `id_token` | JWT，RS256；申请 `openid` scope 后签发 |
| Discovery | `/.well-known/openid-configuration` |
| JWKS | `/oauth/jwks` |
| UserInfo | `GET /oauth/userinfo` |
| Token Revocation | `POST /oauth/revoke`（RFC 7009） |

> **对接建议：** Phase 1 先用「code → token → 自行在己方建会话」跑通；用户身份在 Phase 1 可通过后续 UserInfo / 约定字段接口获取。若贵方库强依赖 OIDC Discovery，请与我们确认 Phase 2 上线窗口后再上生产。

### 1.3 明确不支持

- Implicit Grant / Resource Owner Password Credentials
- 第三方自助注册 Client
- 用 OAuth Access Token 直接调用全部 AIEnglish 业务 API（除非另行开通带 scope 的 Resource API）
- 学校维度 Client 绑定（任意学校的 GeneralUser 均可登录已开通 Client）

---

## 2. 角色与术语

| 术语 | 含义 |
|------|------|
| **IdP / AS** | AIEnglish Authorization Server（`DocAI_Backend_Rails`） |
| **Client** | 贵方应用（由管理员登记的 OAuth Application） |
| **Resource Owner** | 持有 AIEnglish 账号的终端用户（`GeneralUser`） |
| **Issuer / API Base** | OAuth 端点所在主机，下文记为 `{ISSUER}` |
| **Login Web** | AIEnglish 前端登录站，下文记为 `{WEB}`（用户密码登录页） |
| **client_id** | 公开标识（可出现在浏览器 URL） |
| **client_secret** | 机密，**仅允许放在贵方服务端**；创建/轮换时只展示一次 |

### 环境占位符

| 占位符 | 说明 | 示例（以实际下发为准） |
|--------|------|------------------------|
| `{ISSUER}` | OAuth API 根地址（无尾斜杠） | `https://docai.m2mda.com` 或开发环境等价域名 |
| `{WEB}` | 用户登录前端 | `https://aienglish.example.com` |
| `{REDIRECT_URI}` | 贵方回调地址（须预先白名单精确登记） | `https://partner.example.com/oauth/callback` |

---

## 3. 开通流程（商务 / 运维）

第三方 **不能** 自行创建 Client，请按下列流程：

1. 向 AIEnglish 管理员提交申请，至少包含：
   - 应用名称（Consent 页展示）
   - 回调地址列表 `redirect_uris`（**精确匹配**，含 scheme / host / path / query）
   - 是否 Confidential（有安全后端 → 推荐 `true`）
   - 所需 scopes（见第 6 节）
   - 可选：官网、Logo、隐私政策、服务条款 URL
2. 管理员在 **Admin Dashboard → OAuth 应用** 创建 Client：
   - 默认多为 `enabled=false`
   - 创建响应中的 **`client_secret` 只出现一次**，请立即安全保存
3. 管理员复核后 **启用（enable）**
4. 将以下凭据安全交付给贵方：
   - `client_id`
   - `client_secret`（Confidential）
   - 已登记的 `redirect_uris`
   - 允许的 scopes
   - `{ISSUER}` / `{WEB}` 环境地址

**变更回调地址 / 轮换 Secret / 停用：** 均须管理员操作；停用后用户无法再完成授权，进行中的授权也会被拒绝。

---

## 4. 推荐架构

### 4.1 Confidential Client（强烈推荐：有后端的网站）

```text
用户浏览器                贵方前端                 贵方后端                  AIEnglish AS
    |                        |                        |                          |
    |-- 点击「AIEnglish登录」→|                        |                          |
    |                        |-- 向后端要 authorize URL →|                          |
    |                        |← state + PKCE 已写入会话 --|                          |
    |← 302 到 {ISSUER}/oauth/authorize ------------------------------------------→|
    |                        |                        |     未登录则跳 {WEB}/login |
    |                        |                        |     登录 + Consent         |
    |← 302 {REDIRECT_URI}?code&state ---------------------------------------------|
    |-- 打开回调页 --------→|                        |                          |
    |                        |-- 把 code+state 交后端 →|                          |
    |                        |                        |-- POST /oauth/token ----→|
    |                        |                        |← access/refresh --------|
    |                        |                        |-- 建立贵方登录会话         |
    |← 已登录会话 -----------|←------------------------|                          |
```

要点：

- **`client_secret` 与换 token 必须在贵方服务端完成**，禁止放到浏览器 / App 包内。
- **PKCE 仍强制**：即使有 secret，authorize 与 token 都必须带 challenge / verifier。

### 4.2 Public Client（纯 SPA / 移动端无安全后端）

- `confidential=false`，`token_endpoint_auth_method` 等效为 `none`
- **必须**完整实现 PKCE；token 交换不可带 secret（或 secret 为空）
- 仍建议用后端 BFF 代理换 token，降低 XSS 盗用风险

---

## 5. 端点一览

| 端点 | 方法 | Phase | 说明 |
|------|------|-------|------|
| `{ISSUER}/oauth/authorize` | GET | 1 | 授权入口（浏览器） |
| `{ISSUER}/oauth/token` | POST | 1 | 换取 / 刷新 Token |
| `{ISSUER}/oauth/session` | POST | 1 | （AIEnglish 自有前端用）JWT → AS Session，第三方通常不直接调用 |
| `{ISSUER}/oauth/userinfo` | GET | 1（最小实现）/ 2（完整 OIDC） | 用户信息（Bearer access_token） |
| `{ISSUER}/oauth/revoke` | POST | 2/3 | 吊销 token |
| `{ISSUER}/.well-known/openid-configuration` | GET | 2 | OIDC Discovery |
| `{ISSUER}/oauth/jwks` | GET | 2 | 验签公钥 |

Content-Type（token）：`application/x-www-form-urlencoded`

---

## 6. Scopes

| Scope | 是否常用 | 含义 | Phase 1 行为 | Phase 2 行为 |
|-------|----------|------|--------------|--------------|
| `openid` | 推荐 | OIDC | 可作为 scope 申请 | 签发 `id_token`，UserInfo 含 `sub` |
| `profile` | 推荐 | 昵称等资料 | 记入 granted scopes | UserInfo / id_token 释放 profile claims |
| `email` | 推荐 | 邮箱 | 同上 | 释放 `email` 等 |
| `offline_access` | 需要长期登录时 | 刷新令牌 | **申请后可获得 `refresh_token`** | 同左 |

示例：

```text
scope=openid profile email offline_access
```

> Client 注册时会配置「允许的最大 scope」。请求中超出部分会被拒绝或裁剪（以实现为准）；请只申请已开通的集合。

---

## 7. 完整授权码流程（Phase 1）

### 7.1 生成 PKCE 与 state（贵方后端）

1. 生成高熵随机串：
   - `code_verifier`：43–128 字符，`[A-Za-z0-9-._~]`
   - `state`：防 CSRF，绑定用户浏览器会话
2. 计算：

```text
code_challenge = BASE64URL( SHA256( ascii(code_verifier) ) )
code_challenge_method = S256
```

3. 将 `code_verifier`、`state`、（可选）`nonce` 存入 **贵方服务端 session**（或加密 cookie），**不要**只放 localStorage。

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
| `redirect_uri` | 是 | 必须与白名单 **完全一致** |
| `scope` | 是 | 空格分隔，URL 编码 |
| `state` | **强烈建议** | 回调必须原样校验 |
| `code_challenge` | **是** | PKCE |
| `code_challenge_method` | **是** | 仅允许 `S256`（`plain` 会被拒绝） |
| `nonce` | Phase 2 建议 | 写入 `id_token` 防重放 |

**用户侧行为（由 AIEnglish 完成，贵方无需实现）：**

1. 若用户未在 AS 登录 → 跳转 `{WEB}/login?return_to=<authorize URL>`
2. 用户输入 AIEnglish 账号密码登录
3. 登录成功后回到 `/oauth/authorize`，展示 Consent（受信 `trusted` Client 可能跳过）
4. 用户同意 → 302 回贵方：

```text
{REDIRECT_URI}?code={AUTHORIZATION_CODE}&state={STATE}
```

用户拒绝：

```text
{REDIRECT_URI}?error=access_denied&state={STATE}
```

### 7.3 回调处理（贵方后端）

1. 校验 `state` 与会话中一致，否则中止。
2. 用 `code` + 会话中的 `code_verifier` 换 token（**仅服务端**）：

```http
POST {ISSUER}/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code={AUTHORIZATION_CODE}
&redirect_uri={REDIRECT_URI}
&client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET}
&code_verifier={CODE_VERIFIER}
```

Public Client 省略 `client_secret`（或按开通约定不传）。

**成功响应示例（Phase 1）：**

```json
{
  "access_token": "……opaque……",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "……opaque……",
  "scope": "openid profile email offline_access"
}
```

| 字段 | 说明 |
|------|------|
| `access_token` | Opaque；调用受保护资源时 `Authorization: Bearer …` |
| `expires_in` | 秒；当前配置约 **3600（1 小时）** |
| `refresh_token` | 申请了 `offline_access` 且流程允许时返回 |
| `id_token` | **Phase 2** 才稳定提供 |

3. **授权码一次性**：换 token 成功后不可重放；TTL 约 **10 分钟**。
4. 在贵方系统创建 / 关联本地用户会话（见第 8 节）。
5. 清除会话中的 `code_verifier` / `state`。

### 7.4 刷新 Access Token

```http
POST {ISSUER}/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
&refresh_token={REFRESH_TOKEN}
&client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET}
```

**重要：Refresh Token Rotation**

- 每次成功刷新会返回 **新的** `refresh_token`
- **旧的 `refresh_token` 立即失效**，必须用新值覆盖存储
- 若检测到已作废的 refresh 被再次使用，可能吊销整条 token 族（防盗用）

### 7.5 使用 Access Token

Phase 1：主要用于证明「用户已授权贵方」；长期身份绑定建议：

- 等待 Phase 2 `userinfo` / `id_token.sub`，或  
- 与 AIEnglish 约定临时的用户信息接口（需单独开通）

Phase 2 起：

```http
GET {ISSUER}/oauth/userinfo
Authorization: Bearer {ACCESS_TOKEN}
```

预期 claims（按 scope 释放）示例：

```json
{
  "sub": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "email": "student@school.edu",
  "email_verified": false,
  "name": "Alice",
  "nickname": "Alice"
}
```

**`sub` 是稳定用户主键（GeneralUser UUID），请用 `sub` 做账号关联，不要仅用 email。**

---

## 8. 贵方账号关联建议

| 步骤 | 建议 |
|------|------|
| 首次登录 | 用 `sub` 查找本地用户；不存在则创建并绑定 `aienglish_sub` |
| Email | 可作展示 / 通知；**变更邮箱时仍以 `sub` 为准** |
| 会话 | 建立贵方自己的 Session / JWT；**不要**把 AIEnglish `access_token` 当贵方全站 session 无限期使用 |
| 续期 | 后台用 `refresh_token` 刷新；失败则引导重新授权 |
| 退出 | 清除贵方会话；Phase 2+ 可再调 `/oauth/revoke` |

---

## 9. 安全要求（必须遵守）

1. **HTTPS**：生产环境 authorize / redirect / token 全程 HTTPS。  
2. **`redirect_uri` 精确匹配**：多一个斜杠、http/https、query 差异都会失败。  
3. **校验 `state`**：防止 CSRF。  
4. **`client_secret` 仅服务端**：禁止进前端、移动端包、Git 仓库明文。  
5. **强制 PKCE S256**：缺参数或 `plain` → `invalid_request`。  
6. **Code 只在后端换 token**：且一次性使用。  
7. **Refresh 轮换**：落库必须更新；泄露后立即联系管理员 disable / rotate secret。  
8. **不要日志打印** `code` / `access_token` / `refresh_token` / `client_secret`。  
9. **Clock skew**：校验 `id_token`（Phase 2）时允许约 ±60 秒偏差。

### redirect_uri 规范

| 允许（示例） | 不允许 |
|--------------|--------|
| `https://app.example.com/oauth/callback` | 通配 `https://*.example.com/*` |
| 开发机可登记 `http://localhost:3000/...`（仅开发 Client） | `javascript:`、任意开放重定向 |
| path / query 与登记完全一致 | 生产使用未登记的临时回调 |

---

## 10. 错误码与排查

### 10.1 授权阶段（浏览器 / AS 页）

| error | 常见原因 | 处理 |
|-------|----------|------|
| `unauthorized_client` | Client 未启用 / 无权使用该 grant | 联系管理员 enable |
| `invalid_request` | 缺 PKCE、method≠S256、参数非法 | 检查 challenge 参数 |
| `invalid_client` | client_id 错误 | 核对下发凭据 |
| `invalid_scope` | 申请了未开通 scope | 缩小 scope |
| `access_denied` | 用户点拒绝 | 提示用户后结束 |
| `server_error` | AS 异常 | 重试并反馈时间戳 |

未登录会被 **302 到 AIEnglish 登录页**，不是 OAuth error JSON。

### 10.2 Token 阶段（JSON）

```json
{
  "error": "invalid_grant",
  "error_description": "…"
}
```

| error | 常见原因 |
|-------|----------|
| `invalid_grant` | code 过期/已用、PKCE verifier 不匹配、redirect_uri 不一致、refresh 无效或已被轮换 |
| `invalid_client` | secret 错误 / 客户端认证失败 |
| `unauthorized_client` | Client 已禁用 |
| `invalid_request` | 缺必填字段 |

### 10.3 自检清单

- [ ] Client 已 `enabled`
- [ ] `redirect_uri` 与登记字符串完全一致（含编码前后）
- [ ] authorize 带 `code_challenge` + `code_challenge_method=S256`
- [ ] token 带同一会话的 `code_verifier`
- [ ] Confidential 请求带正确 `client_secret`
- [ ] `state` 往返一致
- [ ] 服务器时钟大致准确
- [ ] 刷新后使用了 **新的** refresh_token

---

## 11. 示例：Next.js / Node BFF（Confidential）

### 11.1 启动登录

```typescript
// app/api/auth/aienglish/start/route.ts（示意）
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { createPkce } from '@/lib/pkce';

const ISSUER = process.env.AIENGLISH_ISSUER!;
const CLIENT_ID = process.env.AIENGLISH_CLIENT_ID!;
const REDIRECT_URI = process.env.AIENGLISH_REDIRECT_URI!;

export async function GET() {
  const { codeVerifier, codeChallenge, state } = createPkce();
  const jar = await cookies();
  jar.set('ae_oauth_verifier', codeVerifier, { httpOnly: true, secure: true, sameSite: 'lax', path: '/' });
  jar.set('ae_oauth_state', state, { httpOnly: true, secure: true, sameSite: 'lax', path: '/' });

  const url = new URL(`${ISSUER}/oauth/authorize`);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('client_id', CLIENT_ID);
  url.searchParams.set('redirect_uri', REDIRECT_URI);
  url.searchParams.set('scope', 'openid profile email offline_access');
  url.searchParams.set('state', state);
  url.searchParams.set('code_challenge', codeChallenge);
  url.searchParams.set('code_challenge_method', 'S256');

  redirect(url.toString());
}
```

### 11.2 回调换 Token

```typescript
// app/api/auth/aienglish/callback/route.ts（示意）
export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const code = searchParams.get('code');
  const state = searchParams.get('state');
  const jar = await cookies();
  const expectedState = jar.get('ae_oauth_state')?.value;
  const verifier = jar.get('ae_oauth_verifier')?.value;

  if (!code || !state || state !== expectedState || !verifier) {
    return new Response('Invalid OAuth state', { status: 400 });
  }

  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri: process.env.AIENGLISH_REDIRECT_URI!,
    client_id: process.env.AIENGLISH_CLIENT_ID!,
    client_secret: process.env.AIENGLISH_CLIENT_SECRET!,
    code_verifier: verifier
  });

  const tokenRes = await fetch(`${process.env.AIENGLISH_ISSUER}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    return new Response(`Token exchange failed: ${err}`, { status: 400 });
  }

  const tokens = await tokenRes.json();
  // TODO: 持久化 refresh_token（加密）、用 Phase2 userinfo.sub 建本地用户、写贵方 session
  jar.delete('ae_oauth_verifier');
  jar.delete('ae_oauth_state');

  return Response.redirect(new URL('/app', req.url));
}
```

### 11.3 curl 手工联调（已有 code 时）

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

## 12. Token 生命周期（当前配置）

| 凭证 | TTL（约） | 备注 |
|------|-----------|------|
| Authorization Code | 10 分钟 | 一次性 |
| Access Token | 1 小时 | Opaque |
| Refresh Token | 由服务端策略决定 | **每次使用轮换** |

Access Token 过期后：

1. 用最新 `refresh_token` 换新 access（及新 refresh）  
2. 若 refresh 失败 → 引导用户重新走 `/oauth/authorize`

---

## 13. Phase 2 OIDC 预告（对接方可提前设计）

上线后建议校验 `id_token`：

| Claim | 校验 |
|-------|------|
| `iss` | 等于约定 Issuer |
| `aud` | 包含贵方 `client_id` |
| `exp` / `iat` | 未过期；允许少量时钟偏差 |
| `nonce` | 与 authorize 时一致 |
| 签名 | RS256；公钥来自 JWKS；关注 `kid` |

`id_token` **claims 示例（示意）：**

```json
{
  "iss": "https://docai.m2mda.com",
  "sub": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "aud": "your_client_id",
  "exp": 1770000000,
  "iat": 1769996400,
  "nonce": "n-0S6_WzA2Mj",
  "email": "student@school.edu",
  "nickname": "Alice"
}
```

Discovery（Phase 2）预期字段包括：`authorization_endpoint`、`token_endpoint`、`userinfo_endpoint`、`jwks_uri`、`scopes_supported`、`code_challenge_methods_supported: ["S256"]` 等。

---

## 14. 与 AIEnglish 自有产品登录的关系

| 场景 | 凭证 |
|------|------|
| 用户直接使用 AIEnglish Web / App | Devise JWT（产品 API） |
| 用户通过第三方「AIEnglish 登录」 | OAuth Access / Refresh（及未来 id_token） |

二者 **隔离**：第三方拿到的 OAuth Token **不能**当作 AIEnglish 全站 API 的通用 JWT，除非另行签约开通 Resource API scopes。

---

## 15. 上线检查表（合作方）

- [ ] 已从管理员取得 `client_id` / `client_secret` / 环境 `{ISSUER}`
- [ ] 生产 `redirect_uri` 已登记且 Client **已启用**
- [ ] 实现 Authorization Code + **强制 PKCE S256**
- [ ] `state` 校验
- [ ] Token 交换仅在服务端
- [ ] 安全存储并轮换更新 `refresh_token`
- [ ] 本地用户以未来的 `sub`（或约定用户标识）关联
- [ ] 日志脱敏
- [ ] 失败路径：用户取消、code 过期、Client 被禁用均有提示
- [ ] （Phase 2）`id_token` / UserInfo / revoke 已接入

---

## 16. 支持与变更

- **开通 / 启用 / 改回调 / 轮换 Secret**：联系 AIEnglish 管理员  
- **协议或端点变更**：以本仓库文档版本号与管理员通知为准  
- **内部实现问题**：参见 `oauth_idp_phase1_handoff_2026_08_26_zh.md`

---

## 附录 A：Authorize URL 拼装模板

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

请发送给管理员：

```text
应用名称：
环境：开发 / 预发 / 生产
redirect_uris（每行一个，精确）：
  -
  -
Client 类型：Confidential / Public
所需 scopes：openid profile email offline_access
联系人 / 邮箱：
隐私政策 URL（可选）：
服务条款 URL（可选）：
Logo URL（可选）：
预计上线日期：
```

## 附录 C：常见失败对照

| 现象 | 优先检查 |
|------|----------|
| 打开 authorize 立刻报 `unauthorized_client` | Client 未 enable |
| 报 PKCE / `invalid_request` | 是否漏传 challenge 或 method 写成 plain |
| 登录成功但换 token `invalid_grant` | redirect_uri 是否与 authorize 时完全一致；verifier 是否同一会话 |
| 刷新突然全部失败 | 是否仍在使用已被轮换的旧 refresh；是否 Client 被 disable |
| 回调没有 code | 用户拒绝、或 redirect 未登记导致停在 AS 错误页 |

---

*文档结束。如需 Demo Client 或沙箱环境，请在开通申请中注明。*
