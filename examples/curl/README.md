# cURL examples

Set a test key in your shell, never in a committed file:

```bash
export TIARENTAL_API_KEY='tr_test_replace_me'
export TIARENTAL_API_URL='https://api.tiarental.com/v1'
```

Verify the connection and list cars:

```bash
curl --fail-with-body "$TIARENTAL_API_URL/me" \
  -H "Authorization: Bearer $TIARENTAL_API_KEY"

curl --get --fail-with-body "$TIARENTAL_API_URL/cars" \
  -H "Authorization: Bearer $TIARENTAL_API_KEY" \
  --data-urlencode 'pickup_at=2026-10-01T08:00:00Z' \
  --data-urlencode 'dropoff_at=2026-10-05T08:00:00Z' \
  --data-urlencode 'pickup_location=Tirana International Airport' \
  --data-urlencode 'dropoff_location=Tirana International Airport'
```

Create an idempotent booking:

```bash
curl --fail-with-body "$TIARENTAL_API_URL/bookings" \
  -H "Authorization: Bearer $TIARENTAL_API_KEY" \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: wp-order-914-attempt-1' \
  --data '{
    "car_id":"c98282d2-86b4-47b1-a3b1-e5f5cb3063f7",
    "pickup_at":"2026-10-01T08:00:00Z",
    "dropoff_at":"2026-10-05T08:00:00Z",
    "pickup_location":"Tirana International Airport",
    "dropoff_location":"Tirana International Airport",
    "booking_mode":"request",
    "customer":{"first_name":"Ada","last_name":"Kola","email":"ada@example.com","phone":"+355690000000","age":29,"driving_years":8}
  }'
```

Create an external booking block:

```bash
curl --fail-with-body "$TIARENTAL_API_URL/availability/blocks" \
  -H "Authorization: Bearer $TIARENTAL_API_KEY" \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: direct-customer-52' \
  --data '{"car_id":"c98282d2-86b4-47b1-a3b1-e5f5cb3063f7","start_at":"2026-10-10T08:00:00Z","end_at":"2026-10-15T08:00:00Z","type":"external_booking","external_reference":"direct-customer-52"}'
```
