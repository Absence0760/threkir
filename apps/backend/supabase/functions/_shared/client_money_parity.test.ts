/// The event page decides what to show a buyer — the fee, a Register button,
/// whether a cancel refunds — with `apps/web/src/lib/social/paid_registration.ts`,
/// and the Edge Functions decide what actually happens with
/// `events-checkout/lib.ts` and `events-cancel/lib.ts`. Neither imports the
/// other, so nothing kept them agreeing: a page that offers a refund the
/// server then refuses has told the buyer something false about their money.
/// These run both halves over the same grid.
///
/// The web module is loaded by a computed specifier so `deno check` does not
/// walk into the SvelteKit tree (its `$lib/...` type import has no meaning
/// here); with `--no-check` that type-only import is erased.
///
/// Run with:
///   cd apps/backend && deno test --no-check --allow-read supabase/functions/_shared/client_money_parity.test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  capacityDecision,
  computeApplicationFeeCents,
  isSalesWindowOpen,
} from '../events-checkout/lib.ts';
import { resolveRefundEligibility } from '../events-cancel/lib.ts';

type WebModule = {
  applicationFeeCents(amountCents: number, bps: number): number;
  resolveRefundEligibility(
    policy: string,
    now: Date,
    startIso: string,
  ): { eligible: boolean; fullRefund: boolean };
  registrationOpen(
    now: Date,
    startIso: string,
    offsetMinutes: number,
    capacity: number | null,
    goingCount: number,
    viewerHasPaidOrder: boolean,
  ): string;
};

const WEB_SPEC = new URL('../../../../web/src/lib/social/paid_registration.ts', import.meta.url).href;
const web = (await import(WEB_SPEC)) as WebModule;

const START = '2026-07-01T18:00:00.000Z';
const START_MS = Date.parse(START);

Deno.test('the fee the page shows is the fee the checkout charges', () => {
  const amounts = [0, 1, 99, 100, 1999, 2500, 10_000, 123_457, -500, 12.5, NaN, Infinity];
  const rates = [0, 1, 250, 500, 999, 10_000, 15_000, -100, NaN];
  for (const a of amounts) {
    for (const bps of rates) {
      assertEquals(
        web.applicationFeeCents(a, bps),
        computeApplicationFeeCents(a, bps),
        `amount=${a} bps=${bps}`,
      );
    }
  }
});

Deno.test('the refund the page promises is the refund the cancel issues', () => {
  const day = 24 * 60 * 60 * 1000;
  const offsets = [-2 * day, -day - 1, -day, -day + 1, -60_000, -1, 0, 1, day];
  for (const policy of ['no_refund', 'full_until_start', 'full_until_24h', 'something_new']) {
    for (const off of offsets) {
      const nowMs = START_MS + off;
      assertEquals(
        web.resolveRefundEligibility(policy, new Date(nowMs), START),
        resolveRefundEligibility(policy as never, nowMs, START),
        `${policy} at start${off >= 0 ? '+' : ''}${off}ms`,
      );
    }
    assertEquals(
      web.resolveRefundEligibility(policy, new Date(START_MS - 2 * day), 'not a date'),
      resolveRefundEligibility(policy as never, START_MS - 2 * day, 'not a date'),
      `${policy} with an unparseable start`,
    );
  }
});

/// What the server would answer to a Register press, in the page's words.
function serverVerdict(
  nowMs: number,
  startIso: string,
  offsetMinutes: number,
  capacity: number | null,
  going: number,
): 'open' | 'sales_closed' | 'sold_out' {
  if (capacityDecision(going, 0, capacity) === 'full') return 'sold_out';
  if (!isSalesWindowOpen(Date.parse(startIso), offsetMinutes, nowMs)) return 'sales_closed';
  return 'open';
}

Deno.test('the page offers Register exactly when the checkout would take the order', () => {
  const capacities: Array<number | null> = [null, 0, 1, 10];
  const goings = [0, 1, 9, 10, 11];
  const nows = [START_MS - 3_600_000, START_MS - 30 * 60_000 - 1, START_MS - 30 * 60_000, START_MS - 1, START_MS];
  for (const capacity of capacities) {
    for (const going of goings) {
      for (const offset of [0, 30]) {
        for (const nowMs of nows) {
          const page = web.registrationOpen(new Date(nowMs), START, offset, capacity, going, false);
          const server = serverVerdict(nowMs, START, offset, capacity, going);
          assertEquals(
            page === 'open',
            server === 'open',
            `capacity=${capacity} going=${going} offset=${offset} now=start${nowMs - START_MS}ms: page ${page}, server ${server}`,
          );
        }
      }
    }
  }
});

Deno.test('a capacity of 0 is zero seats on the page, as it is in checkout and the capacity trigger', () => {
  // `enforce_event_capacity` (20261018_001) only skips a NULL capacity, and
  // `capacityDecision` only treats null as unlimited: 0 seats is full.
  const now = new Date(START_MS - 3_600_000);
  assertEquals(capacityDecision(0, 0, 0), 'full');
  assertEquals(web.registrationOpen(now, START, 0, 0, 0, false), 'sold_out');
  assertEquals(web.registrationOpen(now, START, 0, null, 999, false), 'open', 'null is still unlimited');
});

Deno.test('an occurrence with no readable start is not offered for sale, because checkout refuses it', () => {
  const nowMs = START_MS - 3_600_000;
  assertEquals(isSalesWindowOpen(Date.parse('not a date'), 0, nowMs), false);
  assertEquals(web.registrationOpen(new Date(nowMs), 'not a date', 0, null, 0, false), 'sales_closed');
});
