# Webhooks

Register a public HTTPS port-443 URL with `POST /webhooks`. Private/local addresses, redirects and unsafe DNS destinations are rejected. Delivery validates every resolved address and pins the approved address for the TLS request to prevent DNS rebinding. The response reveals a `whsec_…` signing secret once.

Each delivery includes:

```text
X-TIARENTAL-Event
X-TIARENTAL-Event-Id
X-TIARENTAL-Delivery-Id
X-TIARENTAL-Signature: t=<unix-seconds>,v1=<hex-hmac>
```

Calculate `HMAC-SHA256(secret, timestamp + "." + raw_request_body)`, compare in constant time, reject timestamps older than five minutes, then deduplicate the event ID before changing local state. Return any 2xx response only after durable acceptance.

Events: `booking.created`, `booking.confirmed`, `booking.rejected`, `booking.cancelled`, `booking.modified`, `availability.blocked`, `availability.unblocked`, `car.updated`, `price.updated`.

Failed delivery uses exponential backoff, stores response/error evidence, reclaims stuck attempts and eventually marks the delivery dead. Repeated delivery must never create a second booking.

Run the protected TIARENTAL maintenance worker at least every minute for prompt retries. A daily cron can recover work eventually, but is not suitable for near-real-time WordPress synchronization.
