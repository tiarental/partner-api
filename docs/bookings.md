# Bookings

`POST /bookings` supports `booking_mode=request` and `booking_mode=instant`. A request enters `awaiting_supplier`. Instant becomes `confirmed` only when the current car configuration permits instant confirmation; otherwise it safely falls back to supplier approval.

Creation is atomic: the server validates vendor ownership, car state, driver rules, locations, cross-border rules, quote and availability inside the existing database transaction boundary. A simultaneous conflicting write returns `CAR_NOT_AVAILABLE`.

GET is vendor-scoped. Modify/cancel is more restrictive: the booking must have been created by the same partner application. Cancellation of a TIARENTAL-paid booking is rejected so the established refund workflow remains authoritative.

Every create/modify/cancel call requires `Idempotency-Key`. Replaying identical method/path/body/key returns the stored response; changing the body with the same key returns `IDEMPOTENCY_CONFLICT`.
