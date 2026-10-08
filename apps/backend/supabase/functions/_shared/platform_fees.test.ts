/// Run with `cd apps/backend && deno test --allow-read supabase/functions/_shared/platform_fees.test.ts`.

import { assert, assertStrictEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parsePlatformFeeBps } from './platform_fees.ts';

const ROW = { event_fee_bps: 500, donation_fee_bps: 0 };

Deno.test('parsePlatformFeeBps reads the rate for each kind', () => {
  assertStrictEquals(parsePlatformFeeBps(ROW, 'event'), 500);
  assertStrictEquals(parsePlatformFeeBps(ROW, 'donation'), 0);
});

Deno.test('parsePlatformFeeBps refuses a rate it cannot charge', () => {
  // 0 is a real rate and must survive; everything here is not one.
  assertStrictEquals(parsePlatformFeeBps(null, 'event'), null);
  for (const bad of [-1, 10001, 2.5, NaN, Infinity, '500', null, undefined]) {
    assertStrictEquals(
      parsePlatformFeeBps({ event_fee_bps: bad, donation_fee_bps: 0 }, 'event'),
      null,
      `event_fee_bps ${String(bad)}`,
    );
  }
});

Deno.test('both checkouts take the rate from platform_fees, not from a host-written row', async () => {
  for (const fn of ['events-checkout', 'donations-checkout']) {
    const src = await Deno.readTextFile(new URL(`../${fn}/index.ts`, import.meta.url));
    assert(src.includes('readPlatformFeeBps(service,'), `${fn} must read the rate through readPlatformFeeBps`);
    assert(!src.includes('platform_fee_bps'), `${fn} must not read a platform_fee_bps column`);
    assert(
      src.includes("error: 'platform_fee_not_configured'"),
      `${fn} must refuse the checkout when the rate cannot be read`,
    );
  }
});
