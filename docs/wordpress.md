# WordPress integration

The plugin communicates only through Partner API. It never embeds a Supabase service-role credential or calls Supabase directly.

After activation, open **TIARENTAL** in WordPress, enter the environment/API URL/key, then run Test connection, Sync now and Connect webhook. The API key and webhook secret are encrypted with a key derived from WordPress auth salts and stored as non-autoloaded options.

Add `[tiarental_booking]` to a page. The browser calls a same-origin WordPress REST proxy; the server adds the Partner key. Search uses live dates/locations. Booking submission uses a stable idempotency key and a honeypot plus source-IP rate limit.

The admin screen provides sync health, current car count, signed-webhook status, manual/external blocks and cancellation for bookings created by that WordPress application. Cached car data is only a display cache; TIARENTAL remains authoritative.

Changing WordPress salts invalidates locally encrypted secrets. Reconnect the key/webhook afterward. “Disconnect locally” does not revoke the remote key; revoke it from the TIARENTAL Vendor Dashboard too.
