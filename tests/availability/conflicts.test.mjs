import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('migration protects block-block and booking-block overlap at PostgreSQL level', async () => {
  const sql = await readFile(new URL('../../supabase/migrations/20260918165924_v13_16_0_partner_api_booking_transfer.sql', import.meta.url), 'utf8');
  assert.match(sql, /reject_overlapping_availability_block/);
  assert.match(sql, /availability_block_conflict/);
  assert.match(sql, /partner_availability_windows/);
  assert.match(sql, /trg_availability_blocks_no_overlap/);
  assert.match(sql, /trg_partner_block_webhooks/);
});

test('new partner tables deny anonymous and authenticated roles', async () => {
  const sql = await readFile(new URL('../../supabase/migrations/20260918165924_v13_16_0_partner_api_booking_transfer.sql', import.meta.url), 'utf8');
  assert.match(sql, /enable row level security/g);
  assert.match(sql, /from public, anon, authenticated/);
  assert.match(sql, /to service_role/);
});
