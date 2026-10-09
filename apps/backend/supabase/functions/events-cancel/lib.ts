/// Pure helpers for buyer self-cancel of a paid event registration
/// (events-cancel, club_events.md slice P2). Extracted so the
/// refund-eligibility decision can be unit-tested without Stripe or the
/// Supabase stack.
///
/// Keep this file dependency-free — no `Deno.env`, no `createClient`,
/// no `fetch`, no Stripe import. The Stripe refund + DB writes live in
/// index.ts; this file only decides.
///
/// The refund-eligibility rule mirrors the web pure helper
/// (apps/web/src/lib/social/paid_registration.ts resolveRefundEligibility)
/// — the same three policies, same cutoffs — so the client preview and the
/// server enforcement can't disagree on whether a cancel is refundable.
/// (Not a registered TS↔Dart parity pair: the Dart side lands with mobile
/// register, P3.)

export type RefundPolicy = 'full_until_start' | 'full_until_24h' | 'no_refund';

export interface RefundEligibility {
  /// Whether a Stripe refund is owed for this cancel.
  eligible: boolean;
  /// Full vs partial. P1/P2 refunds are full-or-nothing per policy (no
  /// proration), so this equals `eligible`; it's a distinct field so a
  /// future partial-refund policy can diverge without changing call sites.
  fullRefund: boolean;
}

/// Resolve whether a buyer self-cancel is refund-eligible, per the event's
/// refund policy.
///   - 'no_refund'        — never eligible.
///   - 'full_until_start' — eligible until the instance start.
///   - 'full_until_24h'   — eligible until 24h before the instance start.
/// Returns not-eligible on an unparseable instance start (fail closed: we
/// don't issue a refund we can't time-bound).
export function resolveRefundEligibility(
  policy: RefundPolicy,
  nowMs: number,
  instanceStartIso: string,
): RefundEligibility {
  const startMs = Date.parse(instanceStartIso);
  if (!Number.isFinite(startMs)) return { eligible: false, fullRefund: false };
  let cutoffMs: number;
  switch (policy) {
    case 'no_refund':
      return { eligible: false, fullRefund: false };
    case 'full_until_start':
      cutoffMs = startMs;
      break;
    case 'full_until_24h':
      cutoffMs = startMs - 24 * 60 * 60 * 1000;
      break;
    default:
      // Unknown policy -> fail closed (no refund) rather than guessing.
      return { eligible: false, fullRefund: false };
  }
  const eligible = nowMs < cutoffMs;
  return { eligible, fullRefund: eligible };
}

export type CancelAction =
  /// A still-`pending` order (no charge captured yet): release the soft
  /// reservation, no Stripe refund.
  | 'release_reservation'
  /// A charged order whose policy allows a refund: initiate the Stripe refund.
  | 'refund'
  /// A charged order whose policy denies a refund (e.g. inside the no-refund
  /// window): nothing to do — the buyer keeps the seat (we don't free a seat
  /// without refunding their money), the caller reports policy_no_refund.
  | 'policy_no_refund'
  /// Terminal / not-cancelable (already refunded, canceled, failed): no-op.
  | 'noop';

/// Decide what the cancel EF should do, given the order's current status and
/// (for a charged order) its refund eligibility. Pure so the branch logic is
/// unit-tested independently of Stripe.
///   pending                             -> release_reservation
///   paid | partially_refunded + eligible-> refund
///   paid | partially_refunded + not     -> policy_no_refund
///   anything else (terminal status)     -> noop
///
/// `partially_refunded` decides EXACTLY as `paid` does, because it is still a
/// held seat: `enforce_paid_order_for_priced_event` accepts it as backing a
/// registration (20270522_001) and the webhook keeps the seat on a partial
/// refund by design. Reading it as terminal instead was a silent money bug —
/// the caller's `.in('status', [...])` had already been widened to select such
/// an order, and the buyer policy in 20270522_001 widened to admit it, so a
/// buyer cancelling a partially-refunded registration reached here, was told
/// `noop`, and the web toast reported success while no refund was created and
/// the seat was never released (decisions § 769). A partial refund is not the
/// buyer giving up their place; it is money coming back on a place they kept.
export function cancelAction(
  status: string,
  refundEligible: boolean,
): CancelAction {
  if (status === 'pending') return 'release_reservation';
  if (status === 'paid' || status === 'partially_refunded') {
    return refundEligible ? 'refund' : 'policy_no_refund';
  }
  return 'noop';
}

/// Shape the `stripe.refunds.create` params for a DESTINATION-charge refund.
///
/// Both flags are load-bearing and Stripe couples them: "If you refund the
/// application fee for a destination charge, you must also reverse the
/// transfer."
///
///   - `reverse_transfer` pulls the host's share back out of their connected
///     account. Without it, "by default the destination account keeps the funds
///     that were transferred to it, leaving the platform account to cover the
///     negative balance from the refund" — so the buyer was made whole out of
///     the PLATFORM's balance and the host kept the whole ticket.
///   - `refund_application_fee` does NOT claw our cut back to us, which is what
///     this call was written believing: it "push[es] the application fee funds
///     back to the connected account". It is the half that leaves the host
///     whole once the transfer above has been reversed off them.
///
/// Together they net every party to zero on a full refund. Set alone, as it was
/// (decisions § 769), the second one pays the host our fee ON TOP of the ticket
/// they already kept, so a cancelled $50 class cost the platform the full $50
/// and paid the host $50 for a class nobody attended.
///
/// No `amount`: Stripe refunds the whole remaining unrefunded balance of the
/// charge, which is what both refundable statuses want — the entire ticket for
/// a `paid` order, and only what is still owed for a `partially_refunded` one.
export function buildRefundParams(paymentIntentId: string) {
  return {
    payment_intent: paymentIntentId,
    refund_application_fee: true,
    reverse_transfer: true,
  };
}

/// The one Stripe idempotency key for refunding an order, shared by BOTH
/// cancel paths. It is derived from the order alone, not from who cancelled,
/// because what it must dedupe is "a refund of this order": a buyer who cancels
/// and a host who then calls off the whole occurrence, inside Stripe's 24 h
/// idempotency window, send byte-identical params under this key and get the
/// first refund replayed instead of a second one attempted. Past the window the
/// guard is Stripe's own: the params carry no `amount`, so a second refund of a
/// fully refunded charge is refused (`charge_already_refunded`, see
/// `isAlreadyRefundedError`) rather than paid twice.
export function refundIdempotencyKey(orderId: string): string {
  return `event-order-refund:${orderId}`;
}

/// What the cancel EF was asked to do. `self` is the buyer cancelling their own
/// registration (the original behaviour, and the default when the field is
/// absent); `occurrence` is an organiser calling off one occurrence, which
/// refunds every registrant of it. Anything else is refused rather than
/// guessed: a typo must not quietly turn a host's "refund everyone" into a
/// self-cancel of an order they do not have.
export type CancelScope = 'self' | 'occurrence';

export function parseCancelScope(raw: unknown): CancelScope | null {
  if (raw === undefined || raw === null) return 'self';
  if (raw === 'self' || raw === 'occurrence') return raw;
  return null;
}

/// `event_exceptions_reason_len_chk` (20270503_001). Checked in the handler so
/// an over-long reason is a 400 before anything is cancelled, not a 23514 from
/// the insert.
export const CANCEL_REASON_MAX_CHARS = 500;

/// Trim a host's free-text cancel reason; blank is no reason. `undefined` means
/// the value is unusable (wrong type, or longer than the column allows) and the
/// caller answers 400.
export function normalizeCancelReason(raw: unknown): string | null | undefined {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== 'string') return undefined;
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  if ([...trimmed].length > CANCEL_REASON_MAX_CHARS) return undefined;
  return trimmed;
}

/// The order statuses an occurrence cancel acts on: the set the buyer path
/// selects, and the set `guard_paid_occurrence_cancel` (20270723000003) refuses
/// a direct client cancel over. A pending order is a held reservation; a paid
/// or partially refunded one is a held seat with money behind it.
export const OCCURRENCE_CANCEL_STATUSES = ['pending', 'paid', 'partially_refunded'] as const;

export type HostCancelAction = 'release_reservation' | 'refund' | 'noop';

/// What an occurrence cancel does to one order. The refund policy is NOT
/// consulted: the host called the class off, so every registrant is owed their
/// money whatever window they bought under (club_events.md § Refunds). Beyond
/// that it decides exactly as `cancelAction` does for an eligible buyer, so the
/// two paths cannot disagree about which statuses carry money.
export function hostCancelAction(status: string): HostCancelAction {
  const action = cancelAction(status, true);
  if (action === 'release_reservation' || action === 'refund') return action;
  return 'noop';
}

/// Whether a failed `stripe.refunds.create` failed because the charge has no
/// unrefunded balance left. That is not a failure of THIS cancel: an earlier
/// call (the buyer's own cancel, a previous attempt at this one whose response
/// was lost, a dashboard refund) already returned the money, and the webhook
/// reconciles the order off its `charge.refunded`. Read off Stripe's error
/// `code` only; the message is prose and changes.
export function isAlreadyRefundedError(e: unknown): boolean {
  if (typeof e !== 'object' || e === null) return false;
  return (e as { code?: unknown }).code === 'charge_already_refunded';
}

/// One order's result inside an occurrence cancel.
///   initiated        a refund was created at Stripe for this order now.
///   already_refunded nothing was left to refund; an earlier refund holds.
///   released         a pending reservation's Checkout Session was expired.
///   failed           the order still holds money and no refund exists. The
///                    occurrence stays cancelled; re-running the same cancel
///                    resumes from here, and the shared key makes that safe.
export type OrderRefundOutcome = 'initiated' | 'already_refunded' | 'released' | 'failed';

export interface OrderRefundResult {
  orderId: string;
  outcome: OrderRefundOutcome;
  /// Machine reason for a `failed` outcome (`missing_payment_intent`,
  /// `stripe_refund_failed`, `stamp_failed`). Absent otherwise.
  code?: string;
}

export interface OccurrenceRefundSummary {
  /// `complete` only when no order is left holding money without a refund.
  outcome: 'complete' | 'incomplete';
  initiated: number;
  already_refunded: number;
  released: number;
  failed: number;
  failed_order_ids: string[];
}

/// Fold the per-order results into what the host is told. One `failed` makes
/// the whole cancel `incomplete`: a host told "done" while a registrant's money
/// is still held has no reason to look again.
export function summarizeOccurrenceRefunds(
  results: readonly OrderRefundResult[],
): OccurrenceRefundSummary {
  const summary: OccurrenceRefundSummary = {
    outcome: 'complete',
    initiated: 0,
    already_refunded: 0,
    released: 0,
    failed: 0,
    failed_order_ids: [],
  };
  for (const r of results) {
    summary[r.outcome] += 1;
    if (r.outcome === 'failed') summary.failed_order_ids.push(r.orderId);
  }
  if (summary.failed > 0) summary.outcome = 'incomplete';
  return summary;
}
