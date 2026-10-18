/// Cancel a paid in-person event registration, from either side
/// (club_events.md slices P2 + M8).
///
/// Two scopes, chosen by the body's `scope` field:
///
/// `self` (default) — the BUYER cancels their own order for an instance on the
/// event-detail page.
/// `occurrence` — an ORGANISER calls off one occurrence, which cancels it and
/// refunds every registrant of it in full, whatever the refund policy says (the
/// host cancelled; the buyers did not). This is `refund_orders_for_instance`
/// from the spec. A one-off event is its own single occurrence and is cancelled
/// the same way. A direct client insert into `event_exceptions` over an
/// occurrence that still holds money is refused by
/// `guard_paid_occurrence_cancel` (20270723000003), so this is the only way a
/// paid occurrence can be called off.
/// `series` — an ORGANISER ends a recurring event: `recurrence_until` moves to
/// now, so no later occurrence exists or can be bought (events-checkout refuses
/// an instant past it), every remaining occurrence that holds an order or an
/// RSVP is called off by name (so each is told, through `notify_event_cancel`),
/// and every one of their orders is refunded exactly as an occurrence cancel
/// refunds (decisions § 1868).
///
/// Either way this EF only INITIATES. The stripe-events-webhook — still the
/// SOLE, idempotent, service-role-only writer of event_orders.status —
/// performs the status transition + seat release when Stripe delivers the
/// resulting event:
///
///   pending order -> expire the Checkout Session at Stripe. Stripe fires
///     `checkout.session.expired` -> the webhook CAS's pending->canceled,
///     releasing the soft reservation (no charge was captured).
///   charged order (paid | partially_refunded) owed a refund -> create a Stripe
///     refund for the whole remaining balance, reversing the destination
///     transfer and pushing the application fee back to the host (see
///     buildRefundParams — both flags, or the platform pays for the
///     cancellation out of its own balance). Stripe fires `charge.refunded` ->
///     the webhook CAS's ->refunded, deletes the buyer's seat, and reverses the
///     reservation. We stamp event_orders.refund_initiated_at first so the UI
///     can show "refund in progress" during the async gap.
///   charged order, buyer cancel, NOT refund-eligible (inside the no-refund
///     window) -> 409 policy_no_refund; the buyer keeps the seat (we never
///     free a seat without refunding the money).
///
/// Every refund, from both scopes, goes through `refundOrder` over the one REST
/// transport (refund.ts, which the webhook and the reconciliation sweep share,
/// decisions § 1839) and is keyed `refundIdempotencyKey(order.id)`: a retried or doubled cancel, or a buyer
/// cancel followed by the host's, replays one refund instead of making two.
///
/// Validation gates (each fails closed):
///   - caller is signed in (JWT-gated),
///   - Stripe is configured (else 503, exactly like P1's checkout) — for an
///     occurrence cancel, checked BEFORE the occurrence is cancelled whenever
///     it holds any order, so a paid class is never called off with nobody
///     able to refund it,
///   - self: the caller owns a cancelable order for (event, instance);
///     occurrence: the caller organises the event's club.
///
/// Mirrors events-checkout's auth + rate-limit shape. SAQ A — no card data.
/// TEST MODE ONLY in P1/P2: STRIPE_SECRET_KEY must be an sk_test_ key.

import Stripe, {
  type AssertNoUnknownParamKeys,
  type UnknownParamKeys,
} from '../_shared/stripe.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database, DbClient } from '../_shared/database.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { selectEffectivePricing } from '../_shared/event_instance.ts';
import { isValidTimestamptz, isValidUuid } from '../_shared/input_validation.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { withCors } from '../_shared/cors.ts';
import {
  buildRefundParams,
  cancelAction,
  hostCancelAction,
  normalizeCancelReason,
  OCCURRENCE_CANCEL_STATUSES,
  type OrderRefundResult,
  parseCancelScope,
  resolveRefundEligibility,
  type RefundPolicy,
  SERIES_CANCEL_RSVP_STATUSES,
  seriesCancelCutoff,
  seriesCancelInstances,
  seriesEndUntil,
  summarizeOccurrenceRefunds,
} from './lib.ts';
import { refundOrder, stripeRestRefundCreator } from './refund.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';

/// Every key of the hand-shaped params must be one Stripe declares. This is
/// the only money-MOVING call in the tier and was the one call site without
/// the guard: what reaches Stripe is a function return, not a fresh object
/// literal (and, since § 1839, a form body encoded from it by the one REST
/// transport in refund.ts), so no excess-property check runs and a misspelled
/// `reverse_transfers` would compile and come back from Stripe as `Received
/// unknown parameter` — leaving the transfer un-reversed, which is exactly the
/// state this refund exists to stop being in. Nothing references the alias;
/// declaring it is the check.
type RefundParamsAreStripeParams = AssertNoUnknownParamKeys<
  UnknownParamKeys<ReturnType<typeof buildRefundParams>, Stripe.RefundCreateParams>
>;

interface CancelBody {
  event_id?: string;
  instance_start?: string;
  scope?: unknown;
  reason?: unknown;
}

Deno.serve(withCors(withSentry('events-cancel', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY') || null;

  const guarded = await readJsonWithLimit<CancelBody>(req, 4 * 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;
  const body = guarded.body ?? {};
  const scope = parseCancelScope(body.scope);
  if (!scope) {
    return Response.json({ error: 'invalid_scope' }, { status: 400 });
  }
  // The buyer path always needs Stripe. The occurrence path decides once it
  // knows whether the occurrence holds any money: a free class can be called
  // off with Stripe unset.
  if (scope === 'self' && !stripeSecretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  const eventId = typeof body.event_id === 'string' ? body.event_id : null;
  // A series cancel names no occurrence: it ends every one from now on.
  const instanceStart = scope === 'series'
    ? ''
    : typeof body.instance_start === 'string' ? body.instance_start : null;
  if (!eventId || instanceStart === null) {
    return Response.json({ error: 'missing_event_or_instance' }, { status: 400 });
  }
  // Both go straight into `.eq()` on typed columns below — an unchecked
  // value is a Postgres cast error surfacing as a 500, not a 400.
  if (!isValidUuid(eventId)) {
    return Response.json({ error: 'invalid_event_id' }, { status: 400 });
  }
  if (scope !== 'series' && !isValidTimestamptz(instanceStart)) {
    return Response.json({ error: 'invalid_instance_start' }, { status: 400 });
  }
  const reason = normalizeCancelReason(body.reason);
  if (reason === undefined) {
    return Response.json({ error: 'invalid_reason' }, { status: 400 });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }
  const userClient = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    publishableKey(),
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }

  const service = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    secretKey(),
  );
  const denied = await checkRateLimit(
    service,
    user.id,
    scope === 'self' ? 'events-cancel' : 'events-cancel-occurrence',
    20,
    3600,
    { failClosed: true },
  );
  if (denied) return denied;

  if (scope === 'series') {
    return await cancelSeries({
      userClient,
      service,
      userId: user.id,
      eventId,
      reason,
      stripeSecretKey,
    });
  }

  if (scope === 'occurrence') {
    return await cancelOccurrence({
      userClient,
      service,
      userId: user.id,
      eventId,
      instanceStart,
      reason,
      stripeSecretKey,
    });
  }

  // The buyer's most recent cancelable order for this instance. RLS would
  // also scope this to the caller, but we run it via the service role and
  // pin buyer_user_id explicitly so the lookup is unambiguous.
  const { data: order, error: orderErr } = await service
    .from('event_orders')
    .select('id, status, stripe_checkout_session_id, stripe_payment_intent_id, refund_initiated_at')
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .eq('buyer_user_id', user.id)
    // A partially-refunded order still holds a seat, so the buyer must still be
    // able to give it up; excluding it left a registration that could be
    // neither attended nor cancelled.
    .in('status', ['pending', 'paid', 'partially_refunded'])
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (orderErr) {
    console.error('order read failed (code):', orderErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  if (!order) {
    return Response.json({ error: 'no_cancelable_order' }, { status: 404 });
  }

  // Pricing for the refund policy. Per-instance override wins, else the
  // series default (instance_start is null). Read as the user (RLS lets the
  // buyer read pricing with the event).
  const { data: pricingRows, error: pricingErr } = await userClient
    .from('event_pricing')
    .select('instance_start, refund_policy')
    .eq('event_id', eventId);
  if (pricingErr) {
    console.error('pricing read failed (code):', pricingErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  const rows = (pricingRows ?? []) as Array<{ instance_start: string | null; refund_policy: string }>;
  const pricing = selectEffectivePricing(rows, instanceStart);
  const refundPolicy = (pricing?.refund_policy ?? 'no_refund') as RefundPolicy;

  const eligibility = resolveRefundEligibility(refundPolicy, Date.now(), instanceStart);
  const action = cancelAction(order.status as string, eligibility.eligible);

  const stripe = newStripe(stripeSecretKey!);

  if (action === 'release_reservation') {
    await expireReservation(stripe, order.stripe_checkout_session_id as string | null);
    return Response.json({ ok: true, action: 'reservation_released' });
  }

  if (action === 'policy_no_refund') {
    return Response.json({ error: 'policy_no_refund' }, { status: 409 });
  }

  if (action === 'noop') {
    // Terminal order (already refunded / canceled / failed) — idempotent.
    return Response.json({ ok: true, action: 'noop' });
  }

  const result = await refundOrder(stripeRestRefundCreator(stripeSecretKey!), service, order);
  if (result.outcome === 'failed') {
    return result.code === 'stripe_refund_failed'
      ? Response.json({ error: 'stripe_refund_failed' }, { status: 502 })
      : Response.json({ error: 'cancel_failed' }, { status: 500 });
  }

  // The refund exists at Stripe; charge.refunded will flip the order
  // ->refunded and release the seat. Report refund_initiated so the UI polls.
  return Response.json({ ok: true, action: 'refund_initiated', order_id: order.id });
})));

/// The organiser path: cancel the occurrence, then refund every registrant.
async function cancelOccurrence(args: {
  userClient: DbClient;
  service: DbClient;
  userId: string;
  eventId: string;
  instanceStart: string;
  reason: string | null;
  stripeSecretKey: string | null;
}): Promise<Response> {
  const { userClient, service, userId, eventId, instanceStart, reason, stripeSecretKey } = args;

  // Asked as the CALLER, so the answer is the same predicate the
  // event_exceptions insert policy evaluates for them.
  const { data: allowed, error: authzErr } = await userClient.rpc(
    'can_cancel_event_occurrence',
    { p_event_id: eventId },
  );
  if (authzErr) {
    console.error('organiser check failed (code):', authzErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  if (allowed !== true) {
    return Response.json({ error: 'not_event_organiser' }, { status: 403 });
  }

  const { data: orders, error: ordersErr } = await service
    .from('event_orders')
    .select('id, status, stripe_checkout_session_id, stripe_payment_intent_id')
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .in('status', [...OCCURRENCE_CANCEL_STATUSES])
    .order('created_at', { ascending: true });
  if (ordersErr) {
    console.error('occurrence orders read failed (code):', ordersErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  const planned = (orders ?? [])
    .map((order) => ({ order, action: hostCancelAction(order.status) }))
    .filter((p) => p.action !== 'noop');

  // Fail closed before anything changes: an occurrence holding money is not
  // called off unless the refunds can be issued in the same breath.
  if (planned.length > 0 && !stripeSecretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  // Record the cancel FIRST: events-checkout refuses a cancelled occurrence,
  // so no new order can start behind the refunds below. Idempotent — a retry,
  // or a second organiser, finds the row and leaves the original audit
  // (cancelled_by, reason, cancelled_at) alone. The service role is what lets
  // this past guard_paid_occurrence_cancel; the authority check above is what
  // the insert policy would otherwise have done. cancelled_by is the caller,
  // so notify_event_cancel attributes the fan-out to them.
  const { error: exceptionErr } = await service
    .from('event_exceptions')
    .upsert(
      {
        event_id: eventId,
        instance_start: instanceStart,
        cancelled_by: userId,
        reason,
      },
      { onConflict: 'event_id,instance_start', ignoreDuplicates: true },
    );
  if (exceptionErr) {
    console.error('occurrence cancel insert failed (code):', exceptionErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }

  const results = await settleOrders(planned, service, stripeSecretKey);

  // 200 even when a refund failed: the occurrence IS cancelled, and the body
  // says exactly which orders still hold money. `outcome: 'incomplete'` is the
  // host's signal to retry — the same request, which resumes from the failures
  // and replays the successes under their keys.
  return Response.json({
    ok: true,
    action: 'occurrence_cancelled',
    refunds: summarizeOccurrenceRefunds(results),
  });
}

type CancelableOrder = {
  id: string;
  status: string;
  stripe_checkout_session_id: string | null;
  stripe_payment_intent_id: string | null;
};

/// Release or refund each planned order of a host cancel. Sequential on
/// purpose: a class is tens of orders, and one at a time keeps a Stripe
/// rate-limit from turning into a burst of half-recorded failures. The caller
/// has already refused to start without a key when anything is planned.
async function settleOrders(
  planned: ReadonlyArray<{ order: CancelableOrder; action: ReturnType<typeof hostCancelAction> }>,
  service: DbClient,
  stripeSecretKey: string | null,
): Promise<OrderRefundResult[]> {
  const results: OrderRefundResult[] = [];
  if (planned.length === 0) return results;
  const stripe = newStripe(stripeSecretKey!);
  const createRefund = stripeRestRefundCreator(stripeSecretKey!);
  for (const { order, action } of planned) {
    if (action === 'release_reservation') {
      await expireReservation(stripe, order.stripe_checkout_session_id);
      results.push({ orderId: order.id, outcome: 'released' });
      continue;
    }
    results.push(await refundOrder(createRefund, service, order));
  }
  return results;
}

/// The organiser path for a whole recurring series: end it now, call off every
/// remaining occurrence someone signed up for, and refund all of their orders.
async function cancelSeries(args: {
  userClient: DbClient;
  service: DbClient;
  userId: string;
  eventId: string;
  reason: string | null;
  stripeSecretKey: string | null;
}): Promise<Response> {
  const { userClient, service, userId, eventId, reason, stripeSecretKey } = args;

  const { data: allowed, error: authzErr } = await userClient.rpc(
    'can_cancel_event_occurrence',
    { p_event_id: eventId },
  );
  if (authzErr) {
    console.error('organiser check failed (code):', authzErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  if (allowed !== true) {
    return Response.json({ error: 'not_event_organiser' }, { status: 403 });
  }

  const { data: event, error: eventErr } = await service
    .from('events')
    .select('recurrence_freq, recurrence_until')
    .eq('id', eventId)
    .maybeSingle();
  if (eventErr) {
    console.error('series event read failed (code):', eventErr?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  if (!event) {
    return Response.json({ error: 'event_not_found' }, { status: 404 });
  }
  if (!event.recurrence_freq) {
    return Response.json({ error: 'not_a_series' }, { status: 400 });
  }

  const cutoff = seriesCancelCutoff(event.recurrence_until, new Date().toISOString());
  const cutoffMs = Date.parse(cutoff);

  const readOrders = () =>
    service
      .from('event_orders')
      .select('id, instance_start, status, stripe_checkout_session_id, stripe_payment_intent_id')
      .eq('event_id', eventId)
      .gte('instance_start', cutoff)
      .in('status', [...OCCURRENCE_CANCEL_STATUSES])
      .order('created_at', { ascending: true });

  const first = await readOrders();
  if (first.error) {
    console.error('series orders read failed (code):', first.error?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  if (!stripeSecretKey && (first.data ?? []).some((o) => hostCancelAction(o.status) !== 'noop')) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  // End the series FIRST: events-checkout refuses an instant past
  // recurrence_until, so no order can start behind the cancels below.
  const until = seriesEndUntil(event.recurrence_until, cutoff);
  if (until !== null) {
    const { error: endErr } = await service
      .from('events')
      .update({ recurrence_until: until })
      .eq('id', eventId);
    if (endErr) {
      console.error('series end write failed (code):', endErr?.code ?? 'unknown');
      return Response.json({ error: 'cancel_failed' }, { status: 500 });
    }
  }

  // Call off by name every remaining occurrence that holds an order or an
  // RSVP. Read twice: a checkout that read the series before it ended can
  // still land its pending order after the first pass, and the second pass
  // catches it with its occurrence then cancelled behind it.
  let cancelledOccurrences = 0;
  for (let pass = 0; pass < 2; pass++) {
    const [orders, attendees, exceptions] = await Promise.all([
      readOrders(),
      service
        .from('event_attendees')
        .select('instance_start')
        .eq('event_id', eventId)
        .gte('instance_start', cutoff)
        .in('status', [...SERIES_CANCEL_RSVP_STATUSES]),
      service
        .from('event_exceptions')
        .select('instance_start')
        .eq('event_id', eventId)
        .gte('instance_start', cutoff),
    ]);
    if (orders.error || attendees.error || exceptions.error) {
      const code = (orders.error ?? attendees.error ?? exceptions.error)?.code ?? 'unknown';
      console.error('series occurrence read failed (code):', code);
      return Response.json({ error: 'cancel_failed' }, { status: 500 });
    }
    const instances = seriesCancelInstances(
      [...(orders.data ?? []), ...(attendees.data ?? [])],
      (exceptions.data ?? []).map((e) => e.instance_start),
      cutoffMs,
    );
    if (instances.length === 0) break;
    const { error: exceptionErr } = await service
      .from('event_exceptions')
      .upsert(
        instances.map((instance_start) => ({
          event_id: eventId,
          instance_start,
          cancelled_by: userId,
          reason,
        })),
        { onConflict: 'event_id,instance_start', ignoreDuplicates: true },
      );
    if (exceptionErr) {
      console.error('series cancel insert failed (code):', exceptionErr?.code ?? 'unknown');
      return Response.json({ error: 'cancel_failed' }, { status: 500 });
    }
    cancelledOccurrences += instances.length;
  }

  const final = await readOrders();
  if (final.error) {
    console.error('series orders re-read failed (code):', final.error?.code ?? 'unknown');
    return Response.json({ error: 'cancel_failed' }, { status: 500 });
  }
  const planned = (final.data ?? [])
    .map((order) => ({ order, action: hostCancelAction(order.status) }))
    .filter((p) => p.action !== 'noop');
  if (planned.length > 0 && !stripeSecretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }
  const results = await settleOrders(planned, service, stripeSecretKey);

  return Response.json({
    ok: true,
    action: 'series_cancelled',
    cancelled_occurrences: cancelledOccurrences,
    refunds: summarizeOccurrenceRefunds(results),
  });
}

/// Expire a pending order's Checkout Session; the resulting
/// checkout.session.expired webhook CAS's it ->canceled. With no session id
/// (an order that never reached Stripe) there is nothing to expire — the soft
/// reservation lapses on its own reserved_until. An expire that throws is an
/// already-expired / just-completed session; the webhook reconciles the true
/// state, and a session that completed is a paid order the next run of an
/// occurrence cancel refunds.
async function expireReservation(stripe: Stripe, sessionId: string | null): Promise<void> {
  if (!sessionId) return;
  try {
    await stripe.checkout.sessions.expire(sessionId);
  } catch (e) {
    console.error('checkout session expire failed:', e instanceof Error ? e.message : 'unknown');
  }
}

function newStripe(key: string): Stripe {
  return new Stripe(key, { httpClient: Stripe.createFetchHttpClient() });
}
