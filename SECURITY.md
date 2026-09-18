# Security policy

Do not open a public issue containing an API key, webhook secret, database credential, customer data, or production request/response body. Report vulnerabilities privately to `security@tiarental.com` and include reproduction steps without live customer PII.

Partner keys must remain server-side. A browser, mobile bundle, public Git repository, WordPress HTML page, JavaScript source, log, analytics event or support screenshot must never contain a raw `tr_test_…` or `tr_live_…` key. WordPress talks to its own same-origin REST proxy, which calls the Partner API server-to-server.

Webhook consumers must verify `X-TIARENTAL-Signature`, reject timestamps older than five minutes, compare HMAC values in constant time and deduplicate `X-TIARENTAL-Event-Id` before applying an event.

Production secrets are intentionally absent from this repository. Rotate any credential immediately if it is accidentally disclosed.
