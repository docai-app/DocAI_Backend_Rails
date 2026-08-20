# Essay OCR — Moonshot/Kimi API

The WeChat Mini Program must never contain `MOONSHOT_API_KEY`. Authenticated
clients send compressed essay images to the existing AI English API host, and
Rails forwards them to Kimi without persisting the image bytes.

## Endpoint

```http
POST /api/v1/essay_ocr
Authorization: Bearer <general-user-jwt>
Content-Type: application/json
```

```json
{
  "images": [
    {
      "name": "essay-1.jpg",
      "type": "image/jpeg",
      "dataUrl": "data:image/jpeg;base64,..."
    }
  ]
}
```

Success returns `{ "success": true, "provider": "kimi", "model":
"kimi-k2.6", "text": "..." }`. The endpoint accepts at most nine JPEG, PNG,
or WebP images, up to 4 MiB per image and 14 MiB total decoded content. The
request itself is capped at 20 MiB and rate-limited by authenticated user and
IP address. The authenticated General User must also have `essay` in
`meta.aienglish_features_list`; otherwise the endpoint returns
`403 ESSAY_OCR_FORBIDDEN`.

## Production environment

```text
MOONSHOT_API_KEY=<server-only secret>
MOONSHOT_BASE_URL=https://api.moonshot.cn/v1
MOONSHOT_MODEL=kimi-k2.6
ESSAY_OCR_RATE_LIMIT_WINDOW_SECONDS=600
ESSAY_OCR_RATE_LIMIT_PER_USER=30
ESSAY_OCR_RATE_LIMIT_PER_IP=90
```

Only the first three variables are required. Never put them in the Mini Program
or a Git-tracked file.

The service explicitly sends `thinking: { type: "disabled" }` so OCR uses
Kimi K2.6 instant/non-thinking mode. Do not configure or add `temperature` to
the request: Kimi manages it as `0.6` in non-thinking mode, and rejects other
explicit values.

`REDIS_URL` must point to the production Redis instance used for request rate
limiting. The API fails closed with `503 ESSAY_OCR_RATE_LIMIT_UNAVAILABLE` when
Redis cannot be reached, so an OCR deployment must include a Redis health
check.

## Deployment checklist

1. Start from the latest production branch and cherry-pick the dedicated OCR
   commit(s); do not deploy a dirty local working tree.
2. Configure `MOONSHOT_API_KEY`, the matching `.cn` or `.ai` base URL, the model,
   and `REDIS_URL` in the server secret/environment manager.
3. Confirm the reverse proxy accepts a JSON request body of at least 20 MiB and
   that the Rails host can reach the Moonshot endpoint over HTTPS.
4. Run `scripts/verify_essay_ocr_backend.sh` with the test database configured;
   it runs the OCR request/service/rate-limiter tests, RuboCop, and Zeitwerk.
5. After deployment, send one real compressed essay image with a General User
   JWT and confirm the returned `provider`, `model`, `text`, and `request_id`.

## WeChat domain

The Mini Program calls the existing `https://docai.m2mda.com` request domain.
Moonshot is called server-to-server, so `https://api.moonshot.cn` must not be
added to the WeChat legal-domain list.
