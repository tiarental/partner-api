# Availability

TIARENTAL is the source of truth. `GET /availability` reads one unified server-only view containing active bookings plus manual, external-booking and hold blocks.

Create a block with `POST /availability/blocks` and a unique `Idempotency-Key`. Use `manual_block` for maintenance/unavailability and `external_booking` for a direct/offline reservation. Delete only a block created by the same partner application.

PostgreSQL advisory transaction locks, booking exclusion protection and cross-table conflict triggers serialize writes for one car. Periods use half-open ranges `[start_at,end_at)`, so a return at 10:00 can be followed by a pickup at 10:00 without overlap.
