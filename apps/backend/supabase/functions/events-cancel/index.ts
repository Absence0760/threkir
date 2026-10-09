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
/// from the spec. A direct client insert into `event_exceptions` over an
/// occurrence that still holds money is refused by
/// `guard_paid_occurrence_cancel` (20270723000003), so this is the only way a
/// paid occurrence can be called off.
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
/// Every refund, from both scopes, goes through `refundOrder` and is keyed
/// `refundIdempotencyKey(order.id)`: a retried or doubled cancel, or a buyer
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
import {
  buildRefundParams,
  cancelAction,
  hostCancelAction,
  isAlreadyRefundedError,
  normalizeCancelReason,
  OCCURRENCE_CANCEL_STATUSES,
  type OrderRefundResult,
  parseCancelScope,
  refundIdempotencyKey,
  resolveRefundEligibility,
  type RefundPolicy,
  summarizeOccurrenceRefunds,
} from './lib.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';

/// Every key of the hand-shaped params must be one Stripe declares. This is
/// the only money-MOVING call in the tier and was the one call site without
/// the guard: what is handed to `create` is a function return, not a fresh
/// object literal, so no excess-property check runs and a misspelled
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

interface RefundableOrder {
  id: string;
  status: string;
  stripe_payment_intent_id: string | null;
}

Deno.serve(withSentry('events-cancel', async (req: Request) => {
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
  const instanceStart = typeof body.instance_start === 'string' ? body.instance_start : null;
  if (!eventId || !instanceStart) {
    return Response.json({ error: 'missing_event_or_instance' }, { status: 400 });
  }
  // Both go straight into `.eq()` on typed columns below — an unchecked
  // value is a Postgres cast error surfacing as a 500, not a 400.
  if (!isValidUuid(eventId)) {
    return Response.json({ error: 'invalid_event_id' }, { status: 400 });
  }
  if (!isValidTimestamptz(instanceStart)) {
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
    scope === 'occurrence' ? 'events-cancel-occurrence' : 'events-cancel',
    20,
    3600,
    { failClosed: true },
  );
  if (denied) return denied;

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

  const result = await refundOrder(stripe, service, order);
  if (result.outcome === 'failed') {
    return result.code === 'stripe_refund_failed'
      ? Response.json({ error: 'stripe_refund_failed' }, { status: 502 })
      : Response.json({ error: 'cancel_failed' }, { status: 500 });
  }

  // The refund exists at Stripe; charge.refunded will flip the order
  // ->refunded and release the seat. Report refund_initiated so the UI polls.
  return Response.json({ ok: true, action: 'refund_initiated', order_id: order.id });
}));

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

  const results: OrderRefundResult[] = [];
  if (planned.length > 0) {
    const stripe = newStripe(stripeSecretKey!);
    // Sequential on purpose: a class is tens of orders, and one at a time keeps
    // a Stripe rate-limit from turning into a burst of half-recorded failures.
    for (const { order, action } of planned) {
      if (action === 'release_reservation') {
        await expireReservation(stripe, order.stripe_checkout_session_id);
        results.push({ orderId: order.id, outcome: 'released' });
        continue;
      }
      results.push(await refundOrder(stripe, service, order));
    }
  }

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

/// Refund one charged order through the one shape and the one key. Returns the
/// outcome instead of a Response so the occurrence cancel can fold many of
/// them; the buyer path maps it to its own status codes.
///
/// The `refund_initiated_at` stamp is written only when absent and rolled back
/// only when it is still the one this call wrote, so a failed retry cannot wipe
/// the "refund in progress" mark an earlier, successful refund left behind.
/// Both writes are guarded on the status we READ, not a hardcoded 'paid': a
/// refundable order may be 'partially_refunded', and matching only 'paid'
/// silently stamped nothing while reporting success.
async function refundOrder(
  stripe: Stripe,
  service: DbClient,
  order: RefundableOrder,
): Promise<OrderRefundResult> {
  const paymentIntent = order.stripe_payment_intent_id;
  if (!paymentIntent) {
    console.error('charged order missing payment_intent; cannot refund. order:', order.id);
    return { orderId: order.id, outcome: 'failed', code: 'missing_payment_intent' };
  }

  // NOT a status write — status stays where it is until the webhook confirms
  // (sole-writer invariant).
  const orderStatus = order.status;
  const stampedAt = new Date().toISOString();
  const { error: stampErr } = await service
    .from('event_orders')
    .update({ refund_initiated_at: stampedAt })
    .eq('id', order.id)
    .eq('status', orderStatus)
    .is('refund_initiated_at', null);
  if (stampErr) {
    console.error('refund stamp failed (code):', stampErr?.code ?? 'unknown', 'order:', order.id);
    return { orderId: order.id, outcome: 'failed', code: 'stamp_failed' };
  }

  try {
    await stripe.refunds.create(
      buildRefundParams(paymentIntent),
      { idempotencyKey: refundIdempotencyKey(order.id) },
    );
  } catch (e) {
    if (isAlreadyRefundedError(e)) {
      // The money is already on its way back; charge.refunded reconciles the
      // order. Keep the stamp — "refund in progress" is the truth.
      return { orderId: order.id, outcome: 'already_refunded' };
    }
    // Clear our optimistic stamp so the UI doesn't show "refund in progress"
    // forever, and report the failure (the order is untouched — status stays
    // charged, the seat is held, and a retry resumes here).
    await service
      .from('event_orders')
      .update({ refund_initiated_at: null })
      .eq('id', order.id)
      .eq('status', orderStatus)
      .eq('refund_initiated_at', stampedAt);
    console.error(
      'stripe refund create failed:',
      e instanceof Error ? e.message : 'unknown',
      'order:',
      order.id,
    );
    return { orderId: order.id, outcome: 'failed', code: 'stripe_refund_failed' };
  }
  return { orderId: order.id, outcome: 'initiated' };
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
