# Cars

`GET /cars` and `GET /cars/{car_id}` read the existing TIARENTAL vehicle records. No Partner API copy is created. Only active, approved cars owned by the authenticated vendor are returned.

Supplying `pickup_at` and `dropoff_at` to the list endpoint adds live availability and an authoritative quote. Both values are required together. Location IDs are preferred; a supported location name/slug can be resolved server-side.

Images are public vehicle-image URLs. Private plate, VIN and internal fleet data are never returned. `base_daily_price` is not a final rental total; use `/pricing/quote` for dates and locations.
