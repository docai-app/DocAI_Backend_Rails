# OAuth IdP Phase 1 落地说明

> 对应设计文档：`docs/oauth_oidc_identity_provider_design_2026_08_26_zh.md`  
> 状态：代码已合入仓库；需本地完成 `bundle install` + `db:migrate` 后验收。

## 已实现

| 项 | 说明 |
|----|------|
| Doorkeeper | Gemfile `doorkeeper ~> 5.7`；initializer + 自定义 Authorizations/Tokens |
| 表结构 | `oauth_applications`（含 `enabled`/`trusted`/品牌字段）、`oauth_access_grants`、`oauth_access_tokens`（含 `previous_refresh_token`）、`oauth_audit_logs` |
| Subject | 仅 `GeneralUser`（`resource_owner_id` 为 UUID FK） |
| PKCE | `force_pkce` + AuthorizationsController 强制 **全 Client S256** |
| Refresh | `use_refresh_token` + `previous_refresh_token` 列（轮换） |
| Token 存储 | `hash_token_secrets` / `hash_application_secrets` |
| Client 门禁 | `enabled=false` 不可 authorize / grant；Admin enable/disable |
| Admin API | `/api/admin/v1/oauth/clients` CRUD + rotate_secret / enable / disable |
| AS Session | 登录成功写 `session[:oauth_general_user_id]`；`POST /oauth/session` 用 Devise JWT 建 session |
| return_to | 仅允许本站 `/oauth/authorize` |
| Apartment | OAuth 相关 model 排除在 public schema |

## 本地启动

```bash
cd DocAI_Backend_Rails
bundle install
# 确保 .env 含 AIENGLISH_WEB_ORIGIN / OAUTH_ISSUER_HOST
bin/rails db:migrate
bin/rails test test/integration/oauth_phase1_test.rb
```

## 关键端点

### Admin Client

```http
POST /api/admin/v1/oauth/clients
Content-Type: application/json

{
  "client": {
    "name": "Partner Demo",
    "confidential": true,
    "enabled": false,
    "scopes": "openid profile email offline_access",
    "redirect_uris": ["https://partner.example.com/oauth/callback"]
  }
}
```

响应含一次性 `client_secret`。然后：

```http
POST /api/admin/v1/oauth/clients/:id/enable
```

### 授权码流程（浏览器）

1. 用户登录（`POST /general_users/sign_in`，需携带 cookie）或  
   `POST /oauth/session` + `Authorization: Bearer <devise-jwt>`（`credentials: include`）
2. 浏览器打开：

```text
GET /oauth/authorize
  ?response_type=code
  &client_id=...
  &redirect_uri=https://partner.example.com/oauth/callback
  &scope=openid%20profile%20email%20offline_access
  &state=xyz
  &code_challenge=...
  &code_challenge_method=S256
```

3. Consent 同意后 redirect 回 Client（带 `code`）
4. Client 后端：

```http
POST /oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code=...
&redirect_uri=...
&client_id=...
&client_secret=...
&code_verifier=...
```

## 前端衔接（essay-checker）

登录成功后若 `return_to` 指向 `/oauth/authorize`：

1. 用 JWT 调 `POST /oauth/session?return_to=...`（`credentials: 'include'`）
2. `window.location = return_to`（API 域名上的 authorize）

未登录访问 authorize → 302 到 `{AIENGLISH_WEB_ORIGIN}/login?return_to=...`

## Phase 1 未包含（留给后续 Phase）

- OpenID Connect `id_token` / JWKS / Discovery（Phase 2）
- 用户「已授权应用」管理页与 revoke API 产品化（Phase 3）
- 定制 Consent 视觉（可用 Doorkeeper 默认视图先跑通）

## 验收清单

- [ ] `bundle install` 成功
- [ ] `db:migrate` 成功
- [ ] Admin 创建 Client，secret 只出现一次
- [ ] 未 enable 的 Client authorize 返回 `unauthorized_client`
- [ ] 缺少 PKCE 被拒绝
- [ ] enable 后完整 code → token 成功；code 重放失败
- [ ] refresh_token 可换新 access_token
