import test from 'node:test';
import assert from 'node:assert/strict';
import { TiarentalClient } from '../../src/api/v1/client.js';

test('booking client sends the stable idempotency key and JSON body', async () => {
  const calls = [];
  const client = new TiarentalClient({ apiKey: 'tr_test_' + 'b'.repeat(43), fetchImpl: async (url, init) => {
    calls.push({ url: String(url), init });
    return new Response(JSON.stringify({ data: { id: 'one', number: 'TIA-1' } }), { status: 201 });
  }});
  const request = { car_id: 'car', pickup_at: '2026-10-01T08:00:00Z', dropoff_at: '2026-10-05T08:00:00Z', customer: { first_name: 'A', last_name: 'B', email: 'a@example.com', phone: '+355690000000' } };
  await client.createBooking(request, 'same-logical-operation');
  await client.createBooking(request, 'same-logical-operation');
  assert.equal(calls.length, 2);
  assert.ok(calls.every(call => call.init.headers['Idempotency-Key'] === 'same-logical-operation'));
  assert.equal(calls[0].init.body, calls[1].init.body);
});

test('server contract requires database transaction guards and price-preserving transfer', async () => {
  const { readFile } = await import('node:fs/promises');
  const sql = await readFile(new URL('../../supabase/migrations/20260918165924_v13_16_0_partner_api_booking_transfer.sql', import.meta.url), 'utf8');
  assert.match(sql, /pg_advisory_xact_lock/);
  assert.match(sql, /partner_create_booking_secure/);
  assert.match(sql, /exclude using gist/);
  assert.match(sql, /admin_transfer_booking_secure/);
  assert.match(sql, /'price_preserved', true/);
  assert.doesNotMatch(sql, /update public\.bookings[\s\S]{0,400}set[\s\S]{0,300}total_price\s*=/i);
});
