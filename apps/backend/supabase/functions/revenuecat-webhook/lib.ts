/// Pure helpers for the RevenueCat tier-mapping logic, extracted so
/// they can be unit-tested without booting Supabase. Keep this file
/// dependency-free — no `Deno.env`, no `createClient`, no I/O.

export type Tier = 'free' | 'pro' | 'lifetime';

/// Column on `user_profiles` that records the `event_timestamp_ms` of the
/// event that last moved `subscription_tier` (migration 20270403_001).
export const TIER_EVENT_TS_COLUMN = 'tier_updated_event_ts';

/// Build the PostgREST `.or()` filter that makes the tier write monotonic.
///
/// The event-id dedupe (20260623_001) only rejects a REPLAY of the same
/// event — not two DISTINCT events arriving out of order. RevenueCat does
/// not guarantee delivery order, so an EXPIRATION (event ts T1) delivered
/// AFTER a newer re-subscribe (RENEWAL/INITIAL_PURCHASE, event ts T2 > T1)
/// still maps to 'free' and would silently downgrade a paying user.
///
/// Gating the UPDATE on `tier_updated_event_ts is null OR
/// tier_updated_event_ts <= eventTsMs` applies a tier change only when the
/// event is at least as recent as the one that last moved the tier: the
/// stale deactivation matches zero rows and the tier is left untouched.
/// The `>=` (inclusive `lte`) admits a same-timestamp distinct event; an
/// exact replay is already caught upstream by the event-id dedupe.
export function tierEventGuardFilter(eventTsMs: number): string {
  return `${TIER_EVENT_TS_COLUMN}.is.null,${TIER_EVENT_TS_COLUMN}.lte.${eventTsMs}`;
}

/// Activating events from RevenueCat's taxonomy
/// (https://www.revenuecat.com/docs/integrations/webhooks/event-types).
export const ACTIVATING_EVENTS = [
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'NON_RENEWING_PURCHASE',
  'PRODUCT_CHANGE',
] as const;

/// Events that can end access. EXPIRATION always does. CANCELLATION
/// usually does not: RevenueCat sends it the moment auto-renew is turned
/// off, while the period the user paid for still runs to
/// `expiration_at_ms`, and EXPIRATION follows at that instant.
/// `cancellationEndsAccessNow` decides which CANCELLATIONs downgrade.
export const DEACTIVATING_EVENTS = [
  'EXPIRATION',
  'CANCELLATION',
] as const;

/// RevenueCat's `cancel_reason` for a cancellation made through store
/// support, which is how a refund arrives: the entitlement is revoked at
/// once rather than at the period end.
export const REFUND_CANCEL_REASON = 'CUSTOMER_SUPPORT';

/// Whether a CANCELLATION removes access now. It does when it is a refund
/// (`cancel_reason` CUSTOMER_SUPPORT) or when the paid period has already
/// run out (`expiration_at_ms` at or before `nowMs`). A missing or
/// non-numeric `expiration_at_ms` also counts as ended: the paywall fails
/// closed, and if the period was in fact still running the user's next
/// store event (UNCANCELLATION, RENEWAL) restores Pro.
export function cancellationEndsAccessNow(
  expirationAtMs: unknown,
  cancelReason: unknown,
  nowMs: number,
): boolean {
  if (cancelReason === REFUND_CANCEL_REASON) return true;
  if (typeof expirationAtMs !== 'number' || !Number.isFinite(expirationAtMs)) return true;
  return expirationAtMs <= nowMs;
}

export type CancellationContext = {
  expirationAtMs?: unknown;
  cancelReason?: unknown;
  nowMs?: number;
};

/// Decide what `billing_issue_at` should become for the given event.
/// Returns:
///   - a Date string when the renewal payment failed (set the flag).
///   - `null` when the payment story resolved one way or the other
///     (clear the flag — recovered via RENEWAL / UNCANCELLATION, or
///     ended via EXPIRATION / CANCELLATION; in either case the flag
///     is no longer informative).
///   - `undefined` for events that don't move the billing-issue
///     dimension (no write).
///
/// This is decoupled from `mapEventToTier` because BILLING_ISSUE
/// must NOT change the tier — RC's grace period keeps the user on
/// Pro until EXPIRATION fires. The two functions answer two
/// independent questions; pinning that separation in code (and in
/// tests) prevents a future refactor from accidentally collapsing
/// them and downgrading users mid-grace-period.
export function mapEventToBillingIssue(
  eventType: string,
  now: Date = new Date(),
): string | null | undefined {
  if (eventType === 'BILLING_ISSUE') return now.toISOString();
  if (
    eventType === 'RENEWAL' ||
    eventType === 'UNCANCELLATION' ||
    eventType === 'EXPIRATION' ||
    eventType === 'CANCELLATION'
  ) {
    return null;
  }
  return undefined;
}

/// Decide what tier (if any) an event should drive the user to.
///
/// `currentTier` is the user's tier at the time the event arrives —
/// matters for deactivating events because a `lifetime` holder might
/// also have had a monthly sub for another entitlement; cancelling that
/// shouldn't reset them. `null` / `undefined` means "we don't know yet"
/// and is treated as not-lifetime (the conservative default — if a
/// fetch fails the safest thing is to apply the deactivation).
///
/// `cancellation` carries a CANCELLATION's `expiration_at_ms` and
/// `cancel_reason`: one that leaves the paid period running changes
/// nothing (`cancellationEndsAccessNow`), and the EXPIRATION at the period
/// end does the downgrade.
///
/// Returns `null` when no tier change should be applied.
export function mapEventToTier(
  eventType: string,
  productId: string | null | undefined,
  currentTier: string | null | undefined,
  cancellation: CancellationContext = {},
): Tier | null {
  if ((ACTIVATING_EVENTS as readonly string[]).includes(eventType)) {
    const pid = productId ?? '';
    const next: Tier = pid.includes('lifetime') ? 'lifetime' : 'pro';
    // Never knock a `lifetime` holder down to `pro` on an activating event.
    // PRODUCT_CHANGE fires for a plan change on ANY of the user's products, so
    // a lifetime owner who changes a parallel monthly sub (for a different
    // entitlement) would otherwise be downgraded to pro — and then to free when
    // that sub later expires. lifetime never expires; only an explicit lifetime
    // product can (re)assert it. Mirrors the deactivating-path protection.
    if (currentTier === 'lifetime' && next !== 'lifetime') return null;
    return next;
  }
  if ((DEACTIVATING_EVENTS as readonly string[]).includes(eventType)) {
    if (currentTier === 'lifetime') return null;
    if (
      eventType === 'CANCELLATION' &&
      !cancellationEndsAccessNow(
        cancellation.expirationAtMs,
        cancellation.cancelReason,
        cancellation.nowMs ?? Date.now(),
      )
    ) {
      return null;
    }
    return 'free';
  }
  return null;
}
