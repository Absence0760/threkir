/// The seat confirm arm of `stripe-events-webhook`:
/// `checkout.session.completed` and `checkout.session.async_payment_succeeded`
/// for an event order (club_events.md slice P1; decisions § 1833, § 1839).
///
/// Its own module so a deno test can drive every branch against a fake
/// database client and a fake refund transport: the settlement gate, the
/// `pending -> paid` CAS, the cancelled-occurrence reads on both sides of it,
/// the refund that branch issues, the capacity recheck and the seat. index.ts
/// passes the real Stripe key and `stripeRestRefundCreator`; nothing here reads
/// the environment or reaches the network.
///
/// Keep this file free of a value import of Stripe, for the reason
/// events-cancel/refund.ts gives: the webhook bundles it.

import type { DbClient } from '../_shared/database.ts';
import { capacityDecision } from '../events-checkout/lib.ts';
import {
  type CreateRefund,
  type RefundableOrder,
  refundOrder,
} from '../events-cancel/refund.ts';
import {
  attendeeRowFromSession,
  type CheckoutSession,
  isPaymentSettled,
  orderStatusTransition,
} from './lib.ts';

/// How a paid order on a cancelled occurrence is refunded: the Stripe key
/// (null when unset, which leaves the refund owed) and the transport built
/// from it.
export interface CancelledOccurrenceRefunds {
  stripeSecretKey: string | null;
  transport: (stripeSecretKey: string) => CreateRefund;
}

export async function handleCompleted(
  service: DbClient,
  session: CheckoutSession,
  eventType: string,
  refunds: CancelledOccurrenceRefunds,
): Promise<Response> {
  if (!isPaymentSettled(session.paymentStatus)) {
    // `checkout.session.completed` is not a payment. For a delayed-
    // notification method the money is still in flight and the outcome lands
    // days later as async_payment_succeeded / _failed. Seating here gives a
    // place away for money that may never arrive — and once seated there is
    // no event that takes it back, because the failure arm below transitions
    // out of `pending`, not out of `paid`.
    console.error(
      'checkout session completed unpaid; awaiting async outcome. payment_status:',
      session.paymentStatus ?? 'absent',
    );
    return Response.json({ ok: true, skipped: 'payment_not_settled' });
  }

  const attendee = attendeeRowFromSession(session);
  if (!attendee) {
    // No metadata to seat against — record + 200 so Stripe stops
    // retrying; logged for reconciliation.
    console.error('checkout.session.completed missing metadata');
    return Response.json({ ok: true, skipped: 'missing_metadata' });
  }

  // Resolve the order and CAS its status. Only pending->paid transitions.
  const { data: order, error: orderErr } = await service
    .from('event_orders')
    .select('id, status, event_id, instance_start, buyer_user_id, stripe_payment_intent_id')
    .eq('id', attendee.order_id)
    .maybeSingle();
  if (orderErr) {
    console.error('order read failed (code):', orderErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'order_read_failed' }, { status: 500 });
  }
  if (!order) {
    console.error('checkout.session.completed for unknown order');
    return Response.json({ ok: true, skipped: 'unknown_order' });
  }

  const next = orderStatusTransition(order.status, eventType);
  if (next === null) {
    // Already paid / terminal — idempotent no-op.
    return Response.json({ ok: true, skipped: 'no_transition' });
  }

  // A host can call the occurrence off while this buyer is still on Stripe's
  // page: the cancel closes checkout and expires every session it can see, but
  // a payment already in flight completes anyway. Read it before any write so
  // a failed read retries cleanly.
  const { data: cancelled, error: cancelledErr } = await service
    .from('event_exceptions')
    .select('event_id')
    .eq('event_id', order.event_id)
    .eq('instance_start', order.instance_start)
    .maybeSingle();
  if (cancelledErr) {
    console.error('occurrence cancel read failed (code):', cancelledErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'occurrence_read_failed' }, { status: 500 });
  }

  const paymentIntent = session.paymentIntentId;

  // Mark the order paid (compound match on status='pending' makes the
  // UPDATE itself a CAS — a concurrent webhook can't both flip it).
  const { data: updated, error: updErr } = await service
    .from('event_orders')
    .update({
      status: 'paid',
      paid_at: new Date().toISOString(),
      stripe_payment_intent_id: paymentIntent,
    })
    .eq('id', order.id)
    .eq('status', 'pending')
    .select('id, status')
    .maybeSingle();
  if (updErr) {
    console.error('order paid update failed (code):', updErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'order_update_failed' }, { status: 500 });
  }
  if (!updated) {
    // Lost the CAS race to a concurrent delivery — that one seated it.
    return Response.json({ ok: true, skipped: 'cas_lost' });
  }

  // Ask again now that the order is `paid`. A host who calls the occurrence off
  // between the read above and the CAS met this order as `pending`, could not
  // expire a session that had already completed, and refunded nothing; read
  // only before the CAS, this delivery would then seat the buyer on a class
  // that is not happening. After the CAS the race has no gap left:
  // `events-cancel` records the exception BEFORE it reads the orders, so a
  // cancel this read misses reads this order as `paid` and refunds it itself
  // (decisions § 1839). A failed re-read cannot 500 — the order is already
  // `paid`, so a Stripe retry finds no transition — and it does not unseat a
  // buyer whose class may well be on: it seats, and the reconciliation sweep
  // (`events-refund-sweep`) refunds any paid order on a cancelled occurrence,
  // whose `charge.refunded` then releases the seat.
  const cancelledAfterPay = cancelled !== null || await recheckOccurrenceCancelled(service, order);

  // The class is not happening: never seat, and give the money back the way
  // the host's own cancel would have (decisions § 1833). The order is `paid`
  // first because that is the truth — the money arrived — and because the
  // `charge.refunded` this refund produces transitions out of `paid`.
  if (cancelledAfterPay) {
    return await refundCancelledOccurrenceOrder(service, {
      id: updated.id,
      status: updated.status,
      stripe_payment_intent_id: paymentIntent,
    }, refunds);
  }

  // Confirm-time capacity recheck against the event's hard cap.
  const { data: event } = await service
    .from('events')
    .select('capacity')
    .eq('id', attendee.event_id)
    .maybeSingle();
  const capacity = event?.capacity ?? null;

  if (capacity !== null) {
    const { count: goingCount } = await service
      .from('event_attendees')
      .select('event_id', { count: 'exact', head: true })
      .eq('event_id', attendee.event_id)
      .eq('instance_start', attendee.instance_start)
      .eq('status', 'going')
      .neq('user_id', attendee.user_id);
    // Best-effort fast path only. This recheck is NOT authoritative: it counts
    // only seated 'going' rows and holds no lock, so a competing paid order
    // that hasn't seated yet is invisible and N webhooks racing the last seat
    // all read 'available'. The advisory-locked enforce_event_capacity trigger
    // below is the real never-oversell guard; this just shortcuts the obvious
    // already-full case.
    if (capacityDecision(goingCount ?? 0, 0, capacity) === 'full') {
      // Oversold against another path. P1 has NO automated refund: leave
      // the order paid, do NOT seat, and flag for a manual Stripe-
      // dashboard refund. Logged with the order id so ops can act.
      console.error(
        'OVERSOLD: paid order seats no slot, flag for manual refund. order:',
        order.id,
      );
      return Response.json({ ok: true, oversold: true, order_id: order.id });
    }
  }

  // Seat the attendee (the paid order_id satisfies the
  // enforce_paid_order_for_priced_event trigger). Upsert on the PK so a
  // retry is idempotent. Read the PERSISTED status back: the advisory-locked
  // enforce_event_capacity BEFORE trigger silently rewrites NEW.status to
  // 'waitlisted' when the seat is over capacity (it demotes rather than
  // raising), and that trigger — not the lock-free recheck above — is the
  // authoritative guard. RETURNING reflects the BEFORE-trigger mutation.
  const { data: seated, error: seatErr } = await service
    .from('event_attendees')
    .upsert({
      event_id: attendee.event_id,
      user_id: attendee.user_id,
      instance_start: attendee.instance_start,
      status: 'going',
      order_id: attendee.order_id,
    }, { onConflict: 'event_id,user_id,instance_start' })
    .select('status')
    .maybeSingle();
  if (seatErr) {
    console.error('attendee seat failed (code):', seatErr?.code ?? 'unknown');
    return Response.json({ ok: false, error: 'seat_failed' }, { status: 500 });
  }

  // The buyer paid but the capacity trigger demoted them to the waitlist
  // (lost the last seat to a concurrent paid order the recheck couldn't see).
  // P1 has no automated refund — report oversold + order_id so ops can refund,
  // instead of falsely telling the caller the seat was confirmed.
  if (seated?.status === 'waitlisted') {
    console.error(
      'OVERSOLD: paid order demoted to waitlist by capacity trigger, flag for manual refund. order:',
      order.id,
    );
    return Response.json({
      ok: true,
      oversold: true,
      waitlisted: true,
      order_id: order.id,
    });
  }

  return Response.json({ ok: true, seated: true, order_id: order.id });
}

/// The post-CAS cancellation read (decisions § 1839). A read error answers
/// "not cancelled" and is logged: the order is already `paid`, so failing the
/// delivery would buy no retry, and the sweep refunds whatever this misses.
async function recheckOccurrenceCancelled(
  service: DbClient,
  order: { id: string; event_id: string; instance_start: string },
): Promise<boolean> {
  const { data, error } = await service
    .from('event_exceptions')
    .select('event_id')
    .eq('event_id', order.event_id)
    .eq('instance_start', order.instance_start)
    .maybeSingle();
  if (error) {
    console.error(
      'occurrence cancel re-read failed after paid; seating, the refund sweep is the backstop. code:',
      error?.code ?? 'unknown',
      'order:',
      order.id,
    );
    return false;
  }
  return data !== null;
}

/// Refund a paid order on a cancelled occurrence through the same
/// `refundOrder` as `events-cancel`, over the SDK-free transport. Always a 200:
/// the order is already `paid`, so a Stripe retry would find no transition and
/// do nothing. An order this cannot refund stays `paid` with no
/// `refund_initiated_at` on a cancelled occurrence, which is exactly what the
/// event page lists as owed with a **Refund now** — that is the backstop, and
/// the response and the log name the order for it.
async function refundCancelledOccurrenceOrder(
  service: DbClient,
  order: RefundableOrder,
  refunds: CancelledOccurrenceRefunds,
): Promise<Response> {
  const stripeSecretKey = refunds.stripeSecretKey;
  if (!stripeSecretKey) {
    console.error(
      'CANCELLED OCCURRENCE: paid order seats no slot and Stripe is unset; refund owed. order:',
      order.id,
    );
    return Response.json({
      ok: true,
      occurrence_cancelled: true,
      refund: 'owed',
      order_id: order.id,
    });
  }
  const result = await refundOrder(refunds.transport(stripeSecretKey), service, order);
  if (result.outcome === 'failed') {
    console.error(
      'CANCELLED OCCURRENCE: paid order seats no slot and the refund failed; refund owed. code:',
      result.code ?? 'unknown',
      'order:',
      order.id,
    );
    return Response.json({
      ok: true,
      occurrence_cancelled: true,
      refund: 'owed',
      order_id: order.id,
    });
  }
  return Response.json({
    ok: true,
    occurrence_cancelled: true,
    refund: result.outcome,
    order_id: order.id,
  });
}
