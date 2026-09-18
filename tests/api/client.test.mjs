import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { TiarentalApiError, TiarentalClient } from '../../src/api/v1/client.js';

const key = 'tr_test_' + 'a'.repeat(43);

test('client scopes every call through the bearer key and encodes query values', async () => {
  let received;
  const client = new TiarentalClient({ apiKey: key, fetchImpl: async (url, init) => {
    received = { url: String(url), init };
    return new Response(JSON.stringify({ data: [] }), { status: 200, headers: { 'content-type': 'application/json' } });
  }});
  await client.cars({ pickup_location: 'Tirana Airport', limit: 10 });
  assert.equal(received.init.headers.Authorization, `Bearer ${key}`);
  assert.match(received.url, /pickup_location=Tirana\+Airport/);
  assert.match(received.url, /limit=10/);
});

test('client exposes standardized API errors and request IDs', async () => {
  const client = new TiarentalClient({ apiKey: key, fetchImpl: async () => new Response(JSON.stringify({ error: { code: 'CAR_NOT_AVAILABLE', message: 'Unavailable', request_id: 'req_12345678' } }), { status: 409 }) });
  await assert.rejects(client.availability({}), error => error instanceof TiarentalApiError && error.code === 'CAR_NOT_AVAILABLE' && error.status === 409 && error.requestId === 'req_12345678');
});

test('OpenAPI declares every v1 operation and bearer security', async () => {
  const spec = await readFile(new URL('../../openapi/openapi.yaml', import.meta.url), 'utf8');
  for (const path of ['/me:', '/cars:', '/cars/{car_id}:', '/availability:', '/pricing/quote:', '/bookings:', '/bookings/{booking_id}:', '/bookings/{booking_id}/cancel:', '/bookings/{booking_id}/modify:', '/availability/blocks:', '/availability/blocks/{block_id}:', '/webhooks:', '/webhooks/{webhook_id}:']) assert.ok(spec.includes(`  ${path}`), path);
  assert.match(spec, /PartnerKey:\n\s+type: http\n\s+scheme: bearer/);
});
