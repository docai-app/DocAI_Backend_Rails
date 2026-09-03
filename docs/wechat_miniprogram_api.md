# General User — 微信小程序登录与绑定 API 补充说明

**文档版本**：2026-08-20
**后端项目**：`AI English Backend`  
**基础路径**：`/api/v1`（JSON，与现有 General User API 一致）

---

## 1. 概述

在保留 **邮箱 + 密码** 登录（`POST /general_users/sign_in`）的前提下，增加：

1. **绑定**：用户已在小程序 WebView 内用邮箱密码登录并取得 JWT 后，将 `wx.login()` 得到的 `code` 提交给后端，换取并保存 **openid** 等到 `general_users.meta.wechat_miniprogram`。
2. **小程序登录**：仅携带 `code` 调用登录接口，后端用 openid 找到已绑定用户并签发 **与普通登录相同的 Devise JWT**。
3. **取消绑定**：已登录用户提交新的 `wx.login()` code；后端确认 AppID 与 openid 均和当前账号绑定一致后，才删除绑定。

**注意**：微信 `code` 为一次性短时凭证；持久保存的是 **openid**（及可选 unionid 等），不是 code。

---

## 2. 环境变量（服务端）

| 变量 | 说明 |
|------|------|
| `WECHAT_MINIPROGRAM_APP_ID` | 小程序 AppID |
| `WECHAT_MINIPROGRAM_APP_SECRET` | 小程序 AppSecret 

---

## 3. 认证与 JWT

- **绑定**、**查询绑定状态**、**取消绑定**：请求头需携带
  `Authorization: Bearer <access_token>`  
  与现有需登录接口相同。
- **小程序登录**：无需事先登录；成功后服务端通过 **Devise-JWT** 在 **响应头** 返回令牌（与 `school_portal_api_test`、邮箱登录一致）：
  - 读取：`response.headers['Authorization']`  
  - 一般为 `Bearer <jwt>`  
- CORS 已配置 `expose: ['Authorization']`，浏览器 / WebView 可读取该头。

JWT 有效期等与 `config/initializers/devise.rb` 中 `jwt.expiration_time` 一致（当前为 14 天）。

---

## 4. 接口列表

### 4.1 绑定微信（需登录）

**请求**

```http
POST /api/v1/general_users/wechat_miniprogram/bind
Content-Type: application/json
Authorization: Bearer <jwt>
```

**Body**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string | 是 | `wx.login` 返回的 `code` |
| `nickname` | string | 否 | 可选展示名 |
| `avatar_url` | string | 否 | 可选头像 URL |

**成功 `200`**

```json
{
  "success": true,
  "binding": {
    "wechat_app_id": "...",
    "openid": "...",
    "unionid": "...",
    "nickname": "...",
    "avatar_url": "...",
    "bound_at": "2026-05-11T12:00:00Z",
    "last_login_at": null
  }
}
```

**失败（节选）**

| HTTP | `error_code` | 说明 |
|------|----------------|------|
| 401 | `WECHAT_CODE_INVALID` | code 无效或过期、微信返回错误 |
| 409 | `WECHAT_ALREADY_BOUND` | 当前账号已绑定 **其它** openid，不支持换绑 |
| 409 | `WECHAT_OPENID_CONFLICT` | 该微信已绑定 **其它** 用户 |
| 503 | `WECHAT_CONFIG_ERROR` | 未配置 AppID / Secret |

同一微信重复绑定同一账号：幂等成功，并可选更新 `nickname` / `avatar_url`。

---

### 4.2 微信小程序登录（无需登录）

**请求**

```http
POST /api/v1/general_users/wechat_miniprogram/login
Content-Type: application/json
```

**Body**

| 字段 | 类型 | 必填 |
|------|------|------|
| `code` | string | 是 |

**成功 `200`**

- Body：

```json
{
  "success": true,
  "message": "Logged in successfully."
}
```

- **Header**：`Authorization: Bearer <jwt>`（与邮箱登录一致，用于后续 `Authorization` 请求）。

**失败（节选）**

| HTTP | `error_code` | 说明 |
|------|----------------|------|
| 401 | `WECHAT_NOT_BOUND` | 该微信尚未与任一账号绑定 |
| 401 | `WECHAT_CODE_INVALID` | code 无效或微信报错 |
| 403 | `ACCOUNT_INACTIVE` | 账号被冻结等，`active_for_authentication?` 为 false |
| 503 | `WECHAT_CONFIG_ERROR` | 服务端未配置微信参数 |
| 502 | `WECHAT_UPSTREAM_ERROR` | 请求微信接口失败 |

登录成功后会更新 `meta.wechat_miniprogram.last_login_at`。

---

### 4.3 查询绑定状态（需登录）

**请求**

```http
GET /api/v1/general_users/wechat_miniprogram/binding
Authorization: Bearer <jwt>
```

**成功 `200` — 已绑定**

```json
{
  "success": true,
  "bound": true,
  "binding": {
    "wechat_app_id": "...",
    "openid": "...",
    "unionid": "...",
    "nickname": "...",
    "avatar_url": "...",
    "bound_at": "...",
    "last_login_at": "..."
  }
}
```

**成功 `200` — 未绑定**

```json
{
  "success": true,
  "bound": false,
  "binding": null
}
```

---

### 4.4 取消微信绑定（需登录及新的微信 code）

**请求**

```http
DELETE /api/v1/general_users/wechat_miniprogram/binding
Content-Type: application/json
Authorization: Bearer <jwt>
```

```json
{ "code": "wx.login 返回的新 code" }
```

**成功 `200`**

```json
{
  "success": true,
  "bound": false,
  "binding": null
}
```

后端会通过微信 `jscode2session` 验证新 code。只有 AppID 与 openid 均和当前账号原绑定完全一致时才会删除 `meta.wechat_miniprogram`。其它用户资料和当前 JWT 均会保留。

| HTTP | `error_code` | 说明 |
|------|------|------|
| 400 | `WECHAT_CODE_REQUIRED` | 缺少新的 code |
| 401 | `WECHAT_CODE_INVALID` | code 无效、过期或微信没有返回 openid |
| 403 | `WECHAT_IDENTITY_MISMATCH` | 当前微信与账号已绑定微信不一致 |
| 503 | `WECHAT_CONFIG_ERROR` | 未配置 AppID / Secret |
| 502 | `WECHAT_UPSTREAM_ERROR` | 请求微信接口失败 |

---

## 5. 小程序端推荐流程

### 5.1 首次：邮箱登录 → 绑定

1. WebView 内提交邮箱密码 → `POST /general_users/sign_in` → 从响应头取 JWT。  
2. 原生调用 `wx.login()` → 将 `code` 发到 **`/wechat_miniprogram/bind`**（Header 带 JWT）。  
3. 之后可用 **`/wechat_miniprogram/login`** 快速登录。

### 5.2 再次打开：仅小程序登录

1. `wx.login()` → `POST /api/v1/general_users/wechat_miniprogram/login`，Body `{ "code": "..." }`。  
2. 从响应头读取 `Authorization`，写入 WebView 存储或注入后续请求。

### 5.3 取消绑定

1. 用户在 Profile 主动确认取消绑定。
2. 小程序重新调用 `wx.login()`，立即把新的 code 与当前 JWT 发到 DELETE 接口。
3. 成功后更新本地绑定状态；当前登录继续有效，下次需用邮箱密码登录并可重新绑定。

---

## 6. 错误响应格式

统一示例：

```json
{
  "success": false,
  "error": "Human readable message",
  "error_code": "WECHAT_NOT_BOUND"
}
```

---

## 7. 业务约束（与实现一致）

- **不支持换绑**：若账号已有 openid，再用另一微信号绑定会返回 `WECHAT_ALREADY_BOUND`。  
- **允许安全取消绑定**：必须同时持有当前 JWT 及与原绑定一致的新微信 code；取消后可重新绑定。
- **不提供手机号一键登录**（本期）。  
- 不在 `meta` 中长期保存 `session_key`、`code`。

---

**文档结束**
