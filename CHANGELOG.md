# Changelog

## Git/DNS packaging v2 — 2026-09-18

- Added Albanian guide for updating existing Git repositories and connecting `api.tiarental.com` to the main Vercel project.
- No API endpoint, database migration, WordPress plugin, or runtime change; the API contract remains v1.

## 1.0.0 — 2026-09-18

- Initial versioned Partner API contract at `https://api.tiarental.com/v1`.
- Vendor-scoped API key authentication with reveal-once keys, hashing, revocation and rate limits.
- Cars, availability, quotes, request/instant bookings, modification, cancellation and manual blocks.
- Signed, retryable, idempotent webhooks and request idempotency.
- WordPress booking/search, manual blocks, cancellation, sync health and webhook integration.
