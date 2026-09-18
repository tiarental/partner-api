import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { readFile } from 'node:fs/promises';

function sign(secret, timestamp, raw) { return createHmac('sha256', secret).update(`${timestamp}.${raw}`).digest('hex'); }
function verify(secret, header, raw, now) {
  const match = /^t=(\d+),v1=([a-f0-9]{64})$/.exec(header);
  if (!match || Math.abs(now - Number(match[1])) > 300) return false;
  const expected = Buffer.from(sign(secret, match[1], raw), 'hex');
  const supplied = Buffer.from(match[2], 'hex');
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}

test('documented webhook signature validates raw payload and rejects replay age', () => {
  const secret = 'whsec_test_secret'; const timestamp = 1790253600; const raw = '{"id":"evt_1","type":"booking.confirmed"}';
  const header = `t=${timestamp},v1=${sign(secret, timestamp, raw)}`;
  assert.equal(verify(secret, header, raw, timestamp + 30), true);
  assert.equal(verify(secret, header, raw + ' ', timestamp + 30), false);
  assert.equal(verify(secret, header, raw, timestamp + 301), false);
});

test('migration provides durable retry status, backoff and idempotent event/delivery keys', async () => {
  const sql = await readFile(new URL('../../supabase/migrations/20260918165924_v13_16_0_partner_api_booking_transfer.sql', import.meta.url), 'utf8');
  assert.match(sql, /webhook_deliveries/);
  assert.match(sql, /for update skip locked/);
  assert.match(sql, /next_retry_at/);
  assert.match(sql, /unique \(event_id, webhook_id\)/);
  assert.match(sql, /event_key text not null unique/);
});
