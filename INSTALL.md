# Installation and production test manual

## 1. Prerequisites

- main TIARENTAL v13.16.0 application on Node 24
- the Supabase project that actually belongs to that application
- Vercel project access and DNS control for `api.tiarental.com`
- WordPress 6.4+ with PHP 8.1+ and a public HTTPS URL
- a staging vendor, staging car and non-customer test contact details

Never use an unverified Supabase project. Take a database backup and verify the restore procedure before applying the forward migration.

## 2. Vercel secrets

Generate two independent high-entropy values and add them to Preview and Production as appropriate:

```text
PARTNER_API_KEY_PEPPER=<at least 32 random bytes>
PARTNER_WEBHOOK_ENCRYPTION_KEY=<at least 32 random bytes>
```

Do not prefix either variable with `NEXT_PUBLIC_`. Keep the existing `SUPABASE_SECRET_KEY`, `SECURITY_HASH_PEPPER`, `CRON_SECRET` and notification credentials server-side.

## 3. Database

Review and apply `supabase/migrations/20260918165924_v13_16_0_partner_api_booking_transfer.sql` only after confirming the existing `vehicles`, `bookings`, `companies`, `availability_blocks`, pricing, profile and authentication structures match the audit.

The migration is forward-only. It does not delete bookings or customer data. It adds partner tables/metadata, atomic booking functions, transfer history, block-overlap protection, idempotency and webhook delivery queues.

## 4. Application and domain

Deploy the main TIARENTAL application release matching the migration. Add `api.tiarental.com` as a domain on the same Vercel application; the v1 handlers are `/v1/*`. Verify:

```bash
curl -i https://api.tiarental.com/v1/me
```

The expected unauthenticated result is HTTP 401 with error code `UNAUTHORIZED` and an `X-Request-Id` header.

Configure a trusted scheduler to call the protected main-application maintenance endpoint at least every minute when prompt webhook retries are required. The included Vercel Hobby-compatible daily cron is a safety net, not a real-time retry schedule. The worker is idempotent and requires `Authorization: Bearer <CRON_SECRET>`.

## 5. Create a test integration

Sign in as the staging vendor, open **Integrations**, create a Test WordPress key and copy it immediately. Verify `/me`, `/cars`, a quote and availability. Revoke it once testing is complete.

## 6. WordPress

Create `tiarental-booking.zip` from `wordpress/tiarental-booking`, then in WordPress use **Plugins → Add New → Upload Plugin**. Activate it, open **TIARENTAL**, choose Test, paste the key and save. Run:

1. Test connection
2. Sync now
3. Connect webhook
4. Add `[tiarental_booking]` to a public page

The WordPress server must accept inbound HTTPS POST requests at `/wp-json/tiarental/v1/webhook`.

## 7. Required production tests

Use unique idempotency keys and inspect both systems after each test:

- TIARENTAL confirmed booking → signed WordPress webhook → local cache invalidated
- WordPress booking → TIARENTAL booking and availability window
- WordPress manual/external block → unavailable in TIARENTAL
- TIARENTAL cancellation → WordPress webhook
- WordPress cancellation → TIARENTAL, limited to bookings created by the same application
- two simultaneous bookings for the same car/period → exactly one succeeds
- booking overlapping a manual block → `CAR_NOT_AVAILABLE`
- repeated identical request/key → same result with no duplicate
- same key with different body → `IDEMPOTENCY_CONFLICT`
- failed webhook endpoint → delivery retries and is eventually delivered or marked dead
- revoked key → HTTP 401 immediately
- Vendor A key requesting Vendor B car/booking/block/webhook → not found or forbidden

Record request IDs, not customer PII, in the release evidence.

## 8. Rollback

If application smoke tests fail, roll back the Vercel deployment first and revoke newly created API keys. Do not run destructive SQL or drop new tables while webhook/booking writes may still be active. Database rollback requires a reviewed follow-up migration or restore decision; it is intentionally not automated here.
