/// Run with `cd apps/backend && deno test --allow-read supabase/functions/events-refund-sweep/wiring.test.ts`.
///
/// Source guards over the sweep's handler, its schedule and its platform
/// config (decisions § 1839). The handler's behaviour is driven against a fake
/// client in handler.test.ts; what stays here is positional (gate order) and
/// what a fake cannot see (which transport index.ts injects, the SQL, the
/// config).

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./handler.ts', import.meta.url));
const INDEX = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
const SQL = await Deno.readTextFile(
  new URL('../../migrations/20270726000001_event_refund_reconciliation.sql', import.meta.url),
);
const CONFIG = await Deno.readTextFile(new URL('../../config.toml', import.meta.url));

Deno.test('gates in order: cron bearer, then Stripe, then the worklist, then refunds', () => {
  const at = {
    notConfigured: SRC.indexOf("{ error: 'cron_not_configured' }, { status: 503 }"),
    forbidden: SRC.indexOf("{ error: 'forbidden' }, { status: 403 }"),
    stripe: SRC.indexOf("{ error: 'stripe_not_configured' }, { status: 503 }"),
    read: SRC.indexOf(".rpc('event_orders_owed_refund'"),
    refund: SRC.indexOf('refundOrder(createRefund, service, order)'),
  };
  for (const [name, i] of Object.entries(at)) assert(i >= 0, `${name} not found in the handler`);
  assert(at.notConfigured < at.forbidden, 'an unconfigured secret answers 503 before any compare');
  assert(at.forbidden < at.stripe, 'the bearer is checked before anything about Stripe is revealed');
  assert(at.stripe < at.read, 'Stripe unset must refuse before a single row is read');
  assert(at.read < at.refund);
});

Deno.test('the rate limit is spent only on a wrong bearer, behind the compare', () => {
  const branch = SRC.indexOf("if (gate === 'mismatch') {");
  const limit = SRC.indexOf('checkRateLimit(');
  assert(branch >= 0 && limit > branch, 'checkRateLimit must sit inside the mismatch branch');
  assert(/'events-refund-sweep:anon',\s*60,\s*3600,\s*\{ failClosed: true \}/.test(SRC));
});

Deno.test('the sweep refunds through the shared refundOrder over the one transport', () => {
  assert(/const createRefund = deps\.transport\(stripeSecretKey\);/.test(SRC));
  assert(/transport: stripeRestRefundCreator,/.test(INDEX), 'index.ts must inject the tier\'s one transport');
  assert(/from '\.\.\/events-cancel\/refund\.ts'/.test(SRC));
  // Nothing of its own: no params, no key, no endpoint, no SDK.
  for (const own of ['buildRefundParams(', 'refundIdempotencyKey(', 'idempotencyKey', 'api.stripe.com', '_shared/stripe.ts']) {
    assert(
      !SRC.includes(own) && !INDEX.includes(own),
      `the sweep builds its own refund (${own}); go through refundOrder`,
    );
  }
});

Deno.test('one run is bounded by SWEEP_BATCH_LIMIT, and the SQL caps the worklist too', () => {
  assert(/\{\s*p_limit: SWEEP_BATCH_LIMIT,?\s*\}/.test(SRC), 'the worklist read must pass SWEEP_BATCH_LIMIT');
  assert(/limit greatest\(least\(coalesce\(p_limit, 0\), 100\), 0\)/.test(SQL), 'the SQL cap is gone');
});

Deno.test('the worklist is the owed-refund predicate, and never refund_failed', () => {
  const fn = SQL.slice(
    SQL.indexOf('create or replace function public.event_orders_owed_refund('),
    SQL.indexOf('revoke execute on function public.event_orders_owed_refund('),
  );
  assert(/o\.status in \('paid', 'partially_refunded'\)/.test(fn));
  assert(!fn.includes("'refund_failed'"), 'a failed refund is the payer-notified state (§ 825), not a retry');
  assert(/from public\.event_exceptions x/.test(fn) && /x\.instance_start = o\.instance_start/.test(fn));
  assert(/o\.refund_initiated_at is null/.test(fn));
  assert(/order by random\(\)/.test(fn), 'a refund Stripe always refuses must not starve the rest');
});

Deno.test('the schedule calls the sweep only when configured and only when something is owed', () => {
  assert(/select cron\.schedule\(\s*'event-refund-sweep',\s*'23 \* \* \* \*',\s*\$\$select public\.invoke_event_refund_sweep\(\)\$\$/.test(SQL));
  const fn = SQL.slice(SQL.indexOf('create or replace function public.invoke_event_refund_sweep('));
  const guard = fn.indexOf('if v_url is null or v_secret is null then');
  const owed = fn.indexOf('perform 1 from public.event_orders_owed_refund(1);');
  const post = fn.indexOf('net.http_post(');
  assert(guard >= 0 && owed > guard && post > owed, 'both guards must precede the POST');
  assert(fn.includes("'Authorization', 'Bearer ' || v_secret"));
  for (const name of ['event_refund_sweep_url', 'cron_secret']) {
    assert(fn.includes(`where name = '${name}'`), `the ${name} Vault secret is no longer read`);
  }
});

Deno.test('both routines reach no client role', () => {
  for (const fn of ['event_orders_owed_refund(integer)', 'invoke_event_refund_sweep()']) {
    assert(
      SQL.includes(`revoke execute on function public.${fn} from public, anon, authenticated;`),
      `${fn} must be withheld from every client role`,
    );
  }
});

Deno.test('config.toml turns the platform JWT gate off, so the cron bearer can reach the handler', () => {
  const section = CONFIG.split(/^\[/m).find((s) => s.startsWith('functions.events-refund-sweep]'));
  assert(section, 'no [functions.events-refund-sweep] section in config.toml');
  assertEquals(/^\s*verify_jwt\s*=\s*false\s*$/m.test(section), true);
});
