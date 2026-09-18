# Authentication

Every request uses a reveal-once `tr_test_…` or `tr_live_…` key in `Authorization: Bearer`. The key belongs to exactly one vendor/application/environment. Test keys cannot authenticate as live applications and a key cannot see another vendor's cars, bookings, blocks or webhooks.

The API stores `key_prefix`, an HMAC-SHA256 `key_hash`, status, creation/last-use/expiry/revocation timestamps—never the plaintext key. Revoke or regenerate from Vendor Dashboard → Integrations. Regeneration immediately revokes active keys for that application.

Read requests are limited to 180/minute and writes to 60/minute per key and source IP. A limit response is HTTP 429 with `Retry-After`. Treat keys like passwords: server-side only, no browser bundles, repositories, analytics or logs.

Mutating booking/block operations require `Idempotency-Key` (8–200 safe characters). Keep one key for all retries of the same logical operation.
