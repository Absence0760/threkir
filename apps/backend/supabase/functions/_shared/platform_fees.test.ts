/// Run with `cd apps/backend && deno test --allow-read supabase/functions/_shared/platform_fees.test.ts`.

import { assert, assertEquals, assertStrictEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parsePlatformFeeBps, readPlatformFeeBps } from './platform_fees.ts';
import type { DbClient } from './database.ts';

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

Deno.test('parsePlatformFeeBps accepts both ends of the range', () => {
  for (const kind of ['event', 'donation'] as const) {
    assertStrictEquals(parsePlatformFeeBps({ event_fee_bps: 0, donation_fee_bps: 0 }, kind), 0);
    assertStrictEquals(parsePlatformFeeBps({ event_fee_bps: 10000, donation_fee_bps: 10000 }, kind), 10000);
  }
});

Deno.test('parsePlatformFeeBps reads each kind from its own column only', () => {
  // A broken donation rate must refuse donations without taking event sales
  // down with it, and the reverse.
  const brokenDonation = { event_fee_bps: 500, donation_fee_bps: -1 };
  assertStrictEquals(parsePlatformFeeBps(brokenDonation, 'event'), 500);
  assertStrictEquals(parsePlatformFeeBps(brokenDonation, 'donation'), null);
  const brokenEvent = { event_fee_bps: null, donation_fee_bps: 250 };
  assertStrictEquals(parsePlatformFeeBps(brokenEvent, 'event'), null);
  assertStrictEquals(parsePlatformFeeBps(brokenEvent, 'donation'), 250);
});

function feeClient(result: { data: unknown; error: unknown }) {
  const calls: Array<[string, ...unknown[]]> = [];
  const chain = {
    select(cols: string) {
      calls.push(['select', cols]);
      return chain;
    },
    eq(col: string, v: unknown) {
      calls.push(['eq', col, v]);
      return chain;
    },
    maybeSingle() {
      calls.push(['maybeSingle']);
      return Promise.resolve(result);
    },
  };
  const client = {
    from(table: string) {
      calls.push(['from', table]);
      return chain;
    },
  } as unknown as DbClient;
  return { client, calls };
}

Deno.test('readPlatformFeeBps reads the singleton platform_fees row', async () => {
  const { client, calls } = feeClient({ data: { event_fee_bps: 500, donation_fee_bps: 300 }, error: null });
  assertStrictEquals(await readPlatformFeeBps(client, 'donation'), 300);
  assertEquals(calls, [
    ['from', 'platform_fees'],
    ['select', 'event_fee_bps, donation_fee_bps'],
    ['eq', 'id', true],
    ['maybeSingle'],
  ]);
});

Deno.test('readPlatformFeeBps is null on a read error or a missing row, never 0', async () => {
  const origError = console.error;
  console.error = () => {};
  try {
    const failed = feeClient({ data: { event_fee_bps: 500, donation_fee_bps: 0 }, error: { code: '42501' } });
    assertStrictEquals(await readPlatformFeeBps(failed.client, 'event'), null, 'an error wins over any data');
    const missing = feeClient({ data: null, error: null });
    assertStrictEquals(await readPlatformFeeBps(missing.client, 'event'), null);
  } finally {
    console.error = origError;
  }
});
