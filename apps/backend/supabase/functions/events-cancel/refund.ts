/// Refund one charged event order: the one shape, the one key, the one stamp.
///
/// Three functions return a buyer's money. `events-cancel` does it for a buyer
/// cancel and for a host calling an occurrence off; `stripe-events-webhook`
/// does it for a checkout that completed on an occurrence already called off
/// (decisions § 1833); `events-refund-sweep` retries whatever a cancelled
/// occurrence still owes (§ 1839). All three go through `refundOrder` below,
/// so the params (`buildRefundParams`), the idempotency key
/// (`refundIdempotencyKey`) and the `refund_initiated_at` stamp discipline
/// exist once — and so does the request: every caller passes
/// `stripeRestRefundCreator`, the one transport. There used to be two (the
/// SDK's `refunds.create` in `events-cancel`, this REST post in the webhook)
/// sharing one idempotency key, and Stripe refuses a key replayed with
/// different parameters; nobody had shown the two encodings were the same
/// request, so § 1839 deleted the SDK one rather than prove it.
///
/// Keep this file free of a value import of Stripe: the webhook bundles it, and
/// a value import of the SDK is 4.4x its eszip on an endpoint Stripe retries on
/// timeout.

import type { DbClient } from '../_shared/database.ts';
import {
  buildRefundParams,
  isAlreadyRefundedError,
  type OrderRefundResult,
  refundIdempotencyKey,
} from './lib.ts';

export type RefundParams = ReturnType<typeof buildRefundParams>;

/// Create one refund at Stripe. Throws on failure; a thrown value carrying
/// `code: 'charge_already_refunded'` is read by `isAlreadyRefundedError` as
/// done rather than failed.
export type CreateRefund = (params: RefundParams, idempotencyKey: string) => Promise<unknown>;

export interface RefundableOrder {
  id: string;
  status: string;
  stripe_payment_intent_id: string | null;
}

/// Refund one charged order through the one shape and the one key. Returns the
/// outcome instead of a Response so the occurrence cancel can fold many of
/// them; each caller maps it to its own status codes.
///
/// The `refund_initiated_at` stamp is written only when absent and rolled back
/// only when it is still the one this call wrote, so a failed retry cannot wipe
/// the "refund in progress" mark an earlier, successful refund left behind.
/// Both writes are guarded on the status we READ, not a hardcoded 'paid': a
/// refundable order may be 'partially_refunded', and matching only 'paid'
/// silently stamped nothing while reporting success.
export async function refundOrder(
  createRefund: CreateRefund,
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
    await createRefund(buildRefundParams(paymentIntent), refundIdempotencyKey(order.id));
  } catch (e) {
    if (isAlreadyRefundedError(e)) {
      // The money is already on its way back; charge.refunded reconciles the
      // order. Keep the stamp — "refund in progress" is the truth.
      return { orderId: order.id, outcome: 'already_refunded' };
    }
    // Clear our optimistic stamp so the UI doesn't show "refund in progress"
    // forever, and report the failure (the order is untouched — status stays
    // charged, and a retry resumes here).
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

export const STRIPE_REFUNDS_URL = 'https://api.stripe.com/v1/refunds';

/// A non-2xx answer from `POST /v1/refunds`, carrying Stripe's error `code` so
/// `isAlreadyRefundedError` reads it exactly as it reads the SDK's error.
export class StripeRefundError extends Error {
  readonly code: string | null;
  constructor(message: string, code: string | null) {
    super(message);
    this.name = 'StripeRefundError';
    this.code = code;
  }
}

/// The form body for these params: every key, booleans as `true`. This is the
/// only encoding a refund ever has, so a replay under the order's key is the
/// same request whichever function sends it.
export function refundFormBody(params: RefundParams): URLSearchParams {
  const body = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) body.append(key, String(value));
  return body;
}

/// The tier's one refund transport (decisions § 1839).
export function stripeRestRefundCreator(
  secretKey: string,
  fetchImpl: typeof fetch = fetch,
): CreateRefund {
  return async (params, idempotencyKey) => {
    const res = await fetchImpl(STRIPE_REFUNDS_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${secretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Idempotency-Key': idempotencyKey,
      },
      body: refundFormBody(params),
    });
    if (res.ok) {
      await res.body?.cancel();
      return;
    }
    let code: string | null = null;
    let message = `stripe refunds.create answered ${res.status}`;
    try {
      const parsed = await res.json() as { error?: { code?: unknown; message?: unknown } };
      if (typeof parsed?.error?.code === 'string') code = parsed.error.code;
      if (typeof parsed?.error?.message === 'string') message = parsed.error.message;
    } catch {
      // A non-JSON error body still fails the refund; it only has no code.
    }
    throw new StripeRefundError(message, code);
  };
}
