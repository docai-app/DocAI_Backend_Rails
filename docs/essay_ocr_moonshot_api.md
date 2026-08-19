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
IP address.

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

## WeChat domain

The Mini Program calls the existing `https://docai.m2mda.com` request domain.
Moonshot is called server-to-server, so `https://api.moonshot.cn` must not be
added to the WeChat legal-domain list.
