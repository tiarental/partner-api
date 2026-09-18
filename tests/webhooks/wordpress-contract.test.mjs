import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('WordPress verifies signatures, deduplicates events and never contains a Supabase service key', async () => {
  const php = await readFile(new URL('../../wordpress/tiarental-booking/includes/class-trb-rest.php', import.meta.url), 'utf8');
  const api = await readFile(new URL('../../wordpress/tiarental-booking/includes/class-trb-api.php', import.meta.url), 'utf8');
  assert.match(php, /hash_hmac\( 'sha256'/);
  assert.match(php, /hash_equals/);
  assert.match(php, /trb_event_/);
  assert.match(api, /Authorization.*Bearer/);
  assert.doesNotMatch(php + api, /SUPABASE_(?:SERVICE|SECRET)|service[_-]role/i);
});
