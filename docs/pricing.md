# Pricing

`GET /pricing/quote` executes the current TIARENTAL `vehicle_quote` logic. It reuses seasonal/duration pricing, locations, cross-border rules, commission/prepayment and the car's current terms.

Always quote immediately before booking. Never calculate a final price from `base_daily_price` in WordPress. The booking transaction calculates the quote again and stores price/vehicle/cancellation snapshots.

Amounts are numeric EUR values in v1. A modified Partner API booking preserves its original financial snapshot; date changes do not silently rewrite the customer's agreed total.
