# TIARENTAL Partner API

> **Git/DNS bundle v2:** repo publike ekziston. Për update dhe domain-in shiko [GIT-DNS-PUSH-V2.md](GIT-DNS-PUSH-V2.md). API mbetet `/v1`; backend ekzekutohet në projektin kryesor TIARENTAL në Vercel.

Public contract, SDK, examples, database migration and WordPress plugin for the vendor-scoped TIARENTAL Partner API.

Production base URL: `https://api.tiarental.com/v1`

TIARENTAL remains the single source of truth for cars, quotes, bookings and availability. The API is implemented inside the existing TIARENTAL Next.js/Vercel application so it reuses the current Supabase PostgreSQL schema and booking engine instead of creating a parallel system.

## What is included

- OpenAPI 3.1 contract for every v1 endpoint
- zero-dependency JavaScript client with TypeScript declarations
- WordPress plugin with car search, booking, manual blocks, cancellation, sync health and signed webhooks
- forward-only Supabase migration for partner applications, hashed keys, unified availability metadata, idempotency and webhook deliveries
- cURL, JavaScript and PHP examples
- contract/security tests

## Authentication

Create a WordPress application and reveal-once key in **Vendor Dashboard → Integrations**. Send the key only from a trusted server:

```http
Authorization: Bearer tr_test_<reveal-once-key>
```

Keys are scoped to one `vendor_id` and one `partner_app_id`. The server stores only an HMAC hash and prefix. WordPress never receives a Supabase service-role key.

## Quick check

```bash
curl --fail-with-body https://api.tiarental.com/v1/me \
  -H "Authorization: Bearer $TIARENTAL_API_KEY"
```

All create/modify/cancel operations require an `Idempotency-Key`. See [authentication](docs/authentication.md), [bookings](docs/bookings.md), [webhooks](docs/webhooks.md) and the complete [OpenAPI file](openapi/openapi.yaml).

## WordPress

Zip the folder `wordpress/tiarental-booking`, upload it in WordPress, then follow [the WordPress guide](docs/wordpress.md). Place `[tiarental_booking]` on the public booking page. API keys remain encrypted server-side; browser code calls only the site's same-origin WordPress REST proxy.

## Deployment order

1. Review the audit and migration against the current production schema.
2. Back up and test restore procedures.
3. Add `PARTNER_API_KEY_PEPPER` and `PARTNER_WEBHOOK_ENCRYPTION_KEY` to Vercel.
4. Apply only the reviewed forward migration to the matching Supabase project.
5. Deploy the matching main TIARENTAL application release.
6. Map `api.tiarental.com` to that Vercel application and verify HTTPS.
7. Run the smoke and concurrency tests in [INSTALL.md](INSTALL.md).
8. Create a test key, connect a staging WordPress site, then promote to live.

Do not apply the migration to a different Supabase project and do not publish `.env` files, service-role keys, database credentials, webhook secrets, Stripe secrets or customer PII.

## Local tests

```bash
npm test
```

These are deterministic contract tests. Production end-to-end tests require an explicitly authorized test vendor and current Supabase/Vercel deployment.

## Update the public Git repository

The repository already exists. Clone `https://github.com/tiarental/partner-api.git`, copy the files from the Git/DNS v2 bundle into the clone, review `git diff`, commit on a branch and open a pull request. See [GIT-DNS-PUSH-V2.md](GIT-DNS-PUSH-V2.md). Do not initialize a second repository or force-push over `main`.
