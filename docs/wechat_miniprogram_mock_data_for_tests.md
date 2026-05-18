# 微信小程序相关功能 — Mock 数据与单元测试说明

**文档版本**：2026-05-11  
**用途**：尚无真实小程序 / 无法调用微信接口时，用于本地单元测试、接口联调与 Postman 示例；**不得用于生产伪造身份**。  
**关联实现**：`WechatMiniprogram::AuthService`、`HasWechatMiniprogramBinding`、`Api::V1::WechatMiniprogramController`。

---

## 1. 思路说明

微信 **`jscode2session`** 必须在服务端用 **AppSecret** 调用；没有真小程序时，请在测试中 **Stub / Mock** `WechatMiniprogram::AuthService.jscode2session`，让它返回下文提供的 **Mock JSON**，从而不走外网。

不建议在生产环境用「假 openid」绕过校验；本文数据仅用于 **test / 开发自测**。

---

## 2. 测试环境变量（示例）

在运行测试或本地 mock 前可设置（值任意，只要非空即可通过 `AuthService` 的配置检查；真实请求会被 stub 掉）：

```bash
export WECHAT_MINIPROGRAM_APP_ID="wx_mock_appid_0001"
export WECHAT_MINIPROGRAM_APP_SECRET="mock_secret_do_not_commit"
```

若编写自动化测试，通常在 `test_helper.rb` / `rails_helper` 或具体用例里 `ClimateControl.modify` / `stub_const ENV` 等方式注入，**不要把真实 Secret 写进仓库**。

---

## 3. 微信 `jscode2session` 响应 Mock（JSON）

以下为微信文档形态的 **HTTP 200 + Body JSON**；成功时通常 **不含** `errcode`，或部分文档写作 `errcode: 0`。当前实现：`errcode` 存在且 **≠ 0** 时视为失败。

### 3.1 成功（含 openid，可选 unionid）

```json
{
  "openid": "oMOCK-xxxxxxxxxxxxxxxxxxxxx01",
  "session_key": "MOCK_SESSION_KEY_DO_NOT_PERSIST",
  "unionid": "oMOCK-UNION-xxxxxxxxxxxx01"
}
```

无开放平台绑定时可能没有 `unionid`：

```json
{
  "openid": "oMOCK-xxxxxxxxxxxxxxxxxxxxx02",
  "session_key": "MOCK_SESSION_KEY_DO_NOT_PERSIST"
}
```

### 3.2 失败：code 无效 / 过期（常见 errcode 40029）

```json
{
  "errcode": 40029,
  "errmsg": "invalid code"
}
```

### 3.3 失败：code 已被使用（常见 40163）

```json
{
  "errcode": 40163,
  "errmsg": "code been used"
}
```

### 3.4 失败：其它业务错误（示例）

```json
{
  "errcode": 40013,
  "errmsg": "invalid appid"
}
```

---

## 4. Ruby 中单测 Stub 示例（推荐）

在测试里替换真实 HTTP，直接返回 **解析后的 Hash**（注意 **字符串键**，与 `JSON.parse` 一致）：

### 4.1 Minitest（`stub`）

```ruby
WechatMiniprogram::AuthService.stub :jscode2session, ->(_code) {
  {
    'openid' => 'oMOCK-xxxxxxxxxxxxxxxxxxxxx01',
    'session_key' => 'MOCK_SESSION_KEY',
    'unionid' => 'oMOCK-UNION-xxxxxxxxxxxx01'
  }
} do
  # 调用 bind / login 控制器或 GeneralUser#bind_with_wechat_code!
end
```

### 4.2 RSpec（`allow ... to receive`）

```ruby
allow(WechatMiniprogram::AuthService).to receive(:jscode2session).and_return(
  {
    'openid' => 'oMOCK-xxxxxxxxxxxxxxxxxxxxx01',
    'session_key' => 'MOCK_SESSION_KEY',
    'unionid' => 'oMOCK-UNION-xxxxxxxxxxxx01'
  }
)
```

### 4.3 按「模拟 code」分支（可选）

便于一条用例测成功、一条测失败：

```ruby
allow(WechatMiniprogram::AuthService).to receive(:jscode2session) do |code|
  case code
  when 'MOCK_CODE_OK'
    { 'openid' => 'oMOCK-user-a', 'session_key' => 'sk' }
  when 'MOCK_CODE_WECHAT_ERR'
    raise WechatMiniprogram::AuthService::WechatError, 'invalid code'
  else
    raise WechatMiniprogram::AuthService::WechatError, 'unexpected'
  end
end
```

---

## 5. 绑定成功后 `general_users.meta` 示例

对应实现中的键 `meta["wechat_miniprogram"]`：

```json
{
  "wechat_app_id": "wx_mock_appid_0001",
  "openid": "oMOCK-xxxxxxxxxxxxxxxxxxxxx01",
  "unionid": "oMOCK-UNION-xxxxxxxxxxxx01",
  "nickname": "Mock 用户",
  "avatar_url": "https://example.com/mock-avatar.png",
  "bound_at": "2026-05-11T08:00:00Z",
  "last_login_at": "2026-05-11T08:05:00Z"
}
```

说明：`session_key` **不应**写入 `meta`（本文档亦不存储）。

---

## 6. API 层 Mock 请求 / 响应示例（Postman / curl）

以下 Host 请替换为你的本地地址，如 `http://localhost:3000`。JWT 请替换为真实邮箱登录后的 Bearer。

### 6.1 绑定 `POST /api/v1/general_users/wechat_miniprogram/bind`

**Request**

```http
POST /api/v1/general_users/wechat_miniprogram/bind
Content-Type: application/json
Authorization: Bearer <JWT>
```

```json
{
  "code": "MOCK_CODE_OK",
  "nickname": "Mock 用户",
  "avatar_url": "https://example.com/mock-avatar.png"
}
```

**Response 200（业务成功）**

```json
{
  "success": true,
  "binding": {
    "wechat_app_id": "wx_mock_appid_0001",
    "openid": "oMOCK-xxxxxxxxxxxxxxxxxxxxx01",
    "unionid": "oMOCK-UNION-xxxxxxxxxxxx01",
    "nickname": "Mock 用户",
    "avatar_url": "https://example.com/mock-avatar.png",
    "bound_at": "2026-05-11T08:00:00Z",
    "last_login_at": null
  }
}
```

### 6.2 小程序登录 `POST /api/v1/general_users/wechat_miniprogram/login`

**Request**

```json
{
  "code": "MOCK_CODE_OK"
}
```

**Response 200**

- Body 与现有会话接口对齐，例如：

```json
{
  "success": true,
  "message": "Logged in successfully."
}
```

- Header：`Authorization: Bearer <jwt>`（Devise-JWT 下发）。

**未绑定示例（401）**

```json
{
  "success": false,
  "error": "WeChat is not linked to an account. Sign in with email and bind first.",
  "error_code": "WECHAT_NOT_BOUND"
}
```

### 6.3 查询绑定 `GET /api/v1/general_users/wechat_miniprogram/binding`

**Response 200（已绑定）**

```json
{
  "success": true,
  "bound": true,
  "binding": {
    "wechat_app_id": "wx_mock_appid_0001",
    "openid": "oMOCK-xxxxxxxxxxxxxxxxxxxxx01",
    "unionid": "oMOCK-UNION-xxxxxxxxxxxx01",
    "nickname": "Mock 用户",
    "avatar_url": "https://example.com/mock-avatar.png",
    "bound_at": "2026-05-11T08:00:00Z",
    "last_login_at": "2026-05-11T08:05:00Z"
  }
}
```

---

## 7. 建议覆盖的测试场景清单

| 场景 | Mock `jscode2session` 行为 | 预期 |
|------|---------------------------|------|
| 绑定成功 | 返回有效 `openid` | 200，`meta` 写入 |
| 同一用户再次绑定同一 openid | 同上 | 200，幂等 |
| 已绑定用户换另一个 openid | 第一次绑定后换 openid | 409，`WECHAT_ALREADY_BOUND` |
| openid 已被其它账号占用 | 固定 openid，另一用户已写入 meta | 409，`WECHAT_OPENID_CONFLICT` |
| 微信返回 errcode | `raise WechatError` 或返回含 errcode 的 JSON（由 Service 转异常） | 401，`WECHAT_CODE_INVALID` |
| 未绑定调用 login | 返回有效 openid 但库中无绑定 | 401，`WECHAT_NOT_BOUND` |
| 未配置 ENV | `app_id` / `secret` 为空 | 503，`WECHAT_CONFIG_ERROR` |

---

## 8. 固定 Mock 标识符速查（便于多人协作）

| 标识 | 含义 |
|------|------|
| `MOCK_CODE_OK` | 建议在 stub 内映射为成功 JSON |
| `MOCK_CODE_EXPIRED` | 映射为 WechatError 或 errcode 40029 |
| `oMOCK-xxxxxxxxxxxxxxxxxxxxx01` | 测试用户 A 的 openid |
| `oMOCK-xxxxxxxxxxxxxxxxxxxxx02` | 测试用户 B 的 openid（冲突场景） |
| `wx_mock_appid_0001` | 与测试 ENV 中 APP_ID 一致 |

---

**文档结束**。若后续在仓库中新增正式 `test/integration/wechat_miniprogram_controller_test.rb`，可直接引用本文 Mock 与 Stub 写法。
