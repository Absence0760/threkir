/// Run with `cd apps/backend && deno test --allow-read supabase/functions/events-cancel/wiring.test.ts`.
///
/// Source-grep guards in the `events-checkout/wiring.test.ts` idiom. This is
/// the one call in the tier that moves money OUT, and the half `lib.test.ts`
/// cannot see is which shape actually reaches Stripe: a hand-rolled literal at
/// the call site satisfies neither the params guard nor the lib test, and that
/// is precisely how the transfer went un-reversed for as long as it did
/// (decisions § 769). Exercising the handler itself needs a live Supabase plus
/// operator `sk_test_` keys.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { OCCURRENCE_CANCEL_STATUSES } from './lib.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
const REFUND = await Deno.readTextFile(new URL('./refund.ts', import.meta.url));
const GUARD_SQL = await Deno.readTextFile(
  new URL('../../migrations/20270723000003_host_cancel_refunds.sql', import.meta.url),
);

/// Every non-test source under supabase/functions, keyed `<dir>/<file>`.
async function functionSources(): Promise<Record<string, string>> {
  const root = new URL('../', import.meta.url);
  const out: Record<string, string> = {};
  for await (const dir of Deno.readDir(root)) {
    if (!dir.isDirectory) continue;
    for await (const file of Deno.readDir(new URL(`${dir.name}/`, root))) {
      if (!file.isFile || !file.name.endsWith('.ts') || file.name.endsWith('.test.ts')) continue;
      out[`${dir.name}/${file.name}`] = await Deno.readTextFile(
        new URL(`${dir.name}/${file.name}`, root),
      );
    }
  }
  return out;
}

/// The body of the occurrence handler, so an ordering assertion cannot be
/// satisfied by the buyer path's code further down the file.
function occurrenceBody(): string {
  const start = SRC.indexOf('async function cancelOccurrence(');
  assert(start >= 0, 'cancelOccurrence is gone — has the host cancel path moved?');
  const end = SRC.indexOf('\n}\n', start);
  assert(end > start, 'cancelOccurrence has no closing brace at column 0');
  return SRC.slice(start, end);
}

Deno.test('the refund params come from buildRefundParams, not an inline literal', () => {
  const call = REFUND.match(/createRefund\(\s*([^\n,]+),/);
  assert(call, 'no createRefund call found in refundOrder — has the refund moved?');
  assert(
    call[1].trim() === 'buildRefundParams(paymentIntent)',
    'the refund body must be built by buildRefundParams, whose keys the ' +
      '`RefundParamsAreStripeParams` alias checks against the SDK and whose ' +
      `flags lib.test.ts pins. Got: ${call[1]}`,
  );
  // The one transport encodes the params it is handed, key for key; a literal
  // spread or an extra key there would bypass the builder as surely as an
  // inline object.
  assert(
    /body: refundFormBody\(params\),/.test(REFUND),
    'stripeRestRefundCreator must send the params it was handed, encoded by refundFormBody',
  );
});

Deno.test('the params guard alias is still declared against the SDK', () => {
  // Assignability alone does not check a function return's keys — no
  // excess-property check runs on one. Declaring the alias IS the check, so
  // nothing references it and a tidy-up is free to delete it.
  assert(
    /UnknownParamKeys<\s*ReturnType<typeof buildRefundParams>,\s*Stripe\.RefundCreateParams\s*>/
      .test(SRC),
    'the RefundCreateParams excess-property guard is gone. Without it a ' +
      'misspelled `reverse_transfers` compiles and Stripe answers `Received ' +
      'unknown parameter` — leaving the transfer un-reversed at request time.',
  );
});

Deno.test('the refund stamp is guarded on the status read, not a hardcoded paid', () => {
  // A refundable order may be `partially_refunded`. Matching only 'paid'
  // updates zero rows and reports no error, so the stamp silently never lands
  // and the "refund in progress" badge never shows.
  const stamps = REFUND.match(/refund_initiated_at:[^}]*\}\)[\s\S]{0,200}?\.eq\('status', ([^)]+)\)/g);
  assert(stamps && stamps.length === 2, `expected the stamp + its rollback, got ${stamps?.length}`);
  for (const stamp of stamps) {
    assert(
      /\.eq\('status', orderStatus\)/.test(stamp),
      `a refund_initiated_at write is still keyed on a literal status: ${stamp.slice(-60)}`,
    );
  }
});

Deno.test('every refund in the tier goes through ONE refundOrder over ONE transport', async () => {
  // A second place that builds the params or the key is a second place for
  // them to drift; the host path reaching Stripe by its own route is exactly
  // how § 769 shipped. A second TRANSPORT is the same hazard one layer down:
  // the SDK's `refunds.create` and the REST post shared one idempotency key,
  // Stripe refuses a key replayed with different parameters, and nothing ever
  // showed the two encodings were one request (decisions § 1839).
  const files = await functionSources();
  const count = (re: RegExp) =>
    Object.entries(files).flatMap(([path, src]) => (src.match(re) ?? []).map(() => path));
  assertEquals(count(/\brefunds\s*\.\s*create\s*\(/g), [], 'no SDK refund anywhere; use stripeRestRefundCreator');
  assertEquals([...new Set(count(/\/v1\/refunds/g))], ['events-cancel/refund.ts']);
  assertEquals(count(/api\.stripe\.com\/v1\/refunds/g), ['events-cancel/refund.ts']);
  assertEquals(count(/\): CreateRefund \{/g), ['events-cancel/refund.ts'], 'refund.ts holds the only CreateRefund');
  assertEquals(count(/buildRefundParams\(paymentIntent\)/g), ['events-cancel/refund.ts']);
  const helper = REFUND.indexOf('export async function refundOrder(');
  const call = REFUND.indexOf('createRefund(buildRefundParams(');
  const next = REFUND.indexOf('\nexport ', helper + 1);
  assert(helper >= 0 && call > helper && call < next, 'the refund must be created inside refundOrder');
  // Both cancel paths reach it, and so does the webhook's cancelled-occurrence arm.
  assert(/results\.push\(await refundOrder\(createRefund, service, order\)\)/.test(occurrenceBody()));
  assert(/const createRefund = stripeRestRefundCreator\(stripeSecretKey!\);/.test(occurrenceBody()));
  assert(
    /const result = await refundOrder\(stripeRestRefundCreator\(stripeSecretKey!\), service, order\)/
      .test(SRC),
  );
  assert(
    /refundOrder\(refunds\.transport\(stripeSecretKey\), service, order\)/
      .test(files['stripe-events-webhook/completed.ts']) &&
      /transport: stripeRestRefundCreator,/.test(files['stripe-events-webhook/index.ts']),
    'the webhook no longer refunds a cancelled occurrence through refundOrder over the one transport',
  );
  assert(
    /refundOrder\(createRefund, service, order\)/.test(files['events-refund-sweep/index.ts']) &&
      /const createRefund = stripeRestRefundCreator\(stripeSecretKey\);/
        .test(files['events-refund-sweep/index.ts']),
    'the reconciliation sweep no longer retries through refundOrder (decisions § 1839)',
  );
});

Deno.test('the refund idempotency key is the shared per-order key, nothing hand-built', async () => {
  const call = REFUND.match(/createRefund\(buildRefundParams\(paymentIntent\), ([^)]+\))\)/);
  assert(call, 'refundOrder no longer passes a key beside the params');
  assertEquals(call[1], 'refundIdempotencyKey(order.id)');
  // No transport may mint a key of its own.
  assertEquals([...SRC.matchAll(/idempotencyKey:\s*([^}\n]+)/g)].map((m) => m[1].trim()), []);
  assert(
    /'Idempotency-Key': idempotencyKey,/.test(REFUND),
    'the REST transport must send the key it was given',
  );
  const minted = Object.entries(await functionSources())
    .filter(([path, src]) => path !== 'events-cancel/lib.ts' && src.includes('event-order-refund:'))
    .map(([path]) => path);
  assertEquals(minted, [], 'only refundIdempotencyKey may spell the key');
});

Deno.test('occurrence cancel: authority, then the Stripe gate, then the cancel, then the refunds', () => {
  const body = occurrenceBody();
  const authz = body.indexOf(".rpc(\n    'can_cancel_event_occurrence'");
  const forbidden = body.indexOf("'not_event_organiser'");
  const gate = body.indexOf("{ error: 'stripe_not_configured' }");
  const cancel = body.indexOf(".from('event_exceptions')");
  const refunds = body.indexOf('await refundOrder(');
  for (const [name, at] of Object.entries({ authz, forbidden, gate, cancel, refunds })) {
    assert(at >= 0, `${name} not found in cancelOccurrence`);
  }
  // Authority before the service-role insert, or anyone could cancel anything.
  assert(authz < forbidden && forbidden < cancel, 'the organiser check must precede the cancel');
  // The Stripe gate before the cancel, or a paid class is called off with
  // nobody able to refund it.
  assert(gate < cancel, 'the stripe_not_configured gate must precede the cancel');
  // The cancel before the refunds, so checkout is closed behind them.
  assert(cancel < refunds, 'the occurrence must be cancelled before refunds start');
});

Deno.test('occurrence cancel selects exactly the statuses the DB guard refuses a client cancel over', () => {
  assert(
    /\.in\('status', \[\.\.\.OCCURRENCE_CANCEL_STATUSES\]\)/.test(occurrenceBody()),
    'the occurrence order read must use OCCURRENCE_CANCEL_STATUSES',
  );
  const sqlList = GUARD_SQL.match(/o\.status in \(([^)]*)\)/);
  assert(sqlList, 'guard_paid_occurrence_cancel no longer filters on o.status');
  const sqlStatuses = [...sqlList[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort();
  assertEquals(sqlStatuses, [...OCCURRENCE_CANCEL_STATUSES].sort());
});

Deno.test('an occurrence cancel with a failed refund is reported, not swallowed', () => {
  // The summary is the host's only signal that a registrant still holds money.
  assert(
    /refunds: summarizeOccurrenceRefunds\(results\)/.test(occurrenceBody()),
    'the occurrence response must carry the per-order refund summary',
  );
});
