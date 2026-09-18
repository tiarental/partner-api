=== TIARENTAL Booking ===
Contributors: tiarental
Tags: car rental, booking, availability, webhook, vendor
Requires at least: 6.4
Requires PHP: 8.1
Stable tag: 1.0.0
License: GPLv2 or later

Connect a vendor WordPress site to TIARENTAL through the vendor-scoped Partner API. The plugin never connects directly to Supabase.

== Installation ==
1. Upload the tiarental-booking folder to /wp-content/plugins/ or upload its ZIP in Plugins > Add New.
2. Activate TIARENTAL Booking.
3. In the TIARENTAL Vendor Dashboard, open Integrations and create a WordPress API key.
4. Open TIARENTAL in WordPress, select the matching environment, paste the key, and save.
5. Click Test connection, Sync now, then Connect webhook.
6. Add shortcode [tiarental_booking] to the booking page.

== Security ==
The Partner API key and webhook secret are encrypted at rest using WordPress salts. Rotate salts only when you are ready to reconnect the plugin. Webhook payloads use HMAC-SHA256 signatures and a five-minute replay window.

== Changelog ==
= 1.0.0 =
* Initial booking search, booking creation, manual blocks, cancellations, synchronization health and signed webhook support.
