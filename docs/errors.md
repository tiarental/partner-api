# Errors

All errors use one envelope and include a support-safe request ID:

```json
{
  "error": {
    "code": "CAR_NOT_AVAILABLE",
    "message": "The selected vehicle is not available for these dates.",
    "request_id": "req_1234567890abcdef"
  }
}
```

| Code | Meaning |
|---|---|
| `UNAUTHORIZED` | Missing, invalid, expired or revoked key |
| `FORBIDDEN` | Valid key, disallowed application/resource operation |
| `INVALID_REQUEST` | Invalid JSON, fields or idempotency header |
| `CAR_NOT_FOUND` | Car absent or outside vendor scope |
| `CAR_NOT_AVAILABLE` | Atomic availability conflict |
| `BOOKING_NOT_FOUND` | Booking absent or outside vendor scope |
| `BOOKING_CONFLICT` | Current state/payment prevents operation |
| `INVALID_DATES` | Invalid, reversed, past or overlong period |
| `WEBHOOK_ERROR` | Invalid registration/destination |
| `RATE_LIMITED` | Retry after the response's `Retry-After` value |
| `IDEMPOTENCY_CONFLICT` | Key is processing or was reused with other content |
| `INTERNAL_ERROR` | Safe generic server failure; report request ID |
