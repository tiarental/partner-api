<?php
// Run from CLI: TIARENTAL_API_KEY=tr_test_... php booking.php
$base = getenv('TIARENTAL_API_URL') ?: 'https://api.tiarental.com/v1';
$key  = getenv('TIARENTAL_API_KEY');
if (!$key) { throw new RuntimeException('TIARENTAL_API_KEY is required'); }

$payload = [
    'car_id' => 'c98282d2-86b4-47b1-a3b1-e5f5cb3063f7',
    'pickup_at' => '2026-10-01T08:00:00Z',
    'dropoff_at' => '2026-10-05T08:00:00Z',
    'pickup_location' => 'Tirana International Airport',
    'dropoff_location' => 'Tirana International Airport',
    'booking_mode' => 'request',
    'customer' => [
        'first_name' => 'Ada', 'last_name' => 'Kola',
        'email' => 'ada@example.com', 'phone' => '+355690000000',
        'age' => 29, 'driving_years' => 8,
    ],
];
$curl = curl_init($base . '/bookings');
curl_setopt_array($curl, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => [
        'Authorization: Bearer ' . $key,
        'Content-Type: application/json',
        'Idempotency-Key: php-example-' . bin2hex(random_bytes(12)),
    ],
    CURLOPT_POSTFIELDS => json_encode($payload, JSON_THROW_ON_ERROR),
    CURLOPT_TIMEOUT => 15,
]);
$body = curl_exec($curl);
$status = curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
if ($body === false) { throw new RuntimeException(curl_error($curl)); }
curl_close($curl);
$decoded = json_decode($body, true, 512, JSON_THROW_ON_ERROR);
if ($status < 200 || $status >= 300) { throw new RuntimeException($decoded['error']['message'] ?? 'API error'); }
printf("Booking %s — %s\n", $decoded['data']['number'], $decoded['data']['status']);
