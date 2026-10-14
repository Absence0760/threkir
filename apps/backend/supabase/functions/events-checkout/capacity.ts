/// The capacity precheck `events-checkout` runs before it opens a Checkout
/// Session (club_events.md § Capacity, waitlist & the payment race; decisions
/// § 1840). Its own module so a deno test can drive it against a fake client:
/// the three reads, the waitlist holds they feed, and the refusal a failed
/// read must produce.

import type { DbClient } from '../_shared/database.ts';
import { capacityDecision, heldOfferCount } from './lib.ts';

/// going + non-expired pending + other people's waitlist offers count
/// against capacity, the single shared decision. Pending orders whose
/// reserved_until has lapsed do not count (they're swept / released on
/// expiry). A failed read answers 'unknown' rather than 'available': a seat
/// must not be sold because a read errored, whether the read was the seated
/// count or the holds.
export async function precheckCapacity(
  service: DbClient,
  eventId: string,
  instanceStart: string,
  capacity: number | null,
  callerId: string,
  nowMs: number = Date.now(),
): Promise<'available' | 'full' | 'unknown'> {
  if (capacity === null) return 'available';

  const { count: goingCount, error: goingErr } = await service
    .from('event_attendees')
    .select('event_id', { count: 'exact', head: true })
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .eq('status', 'going');
  if (goingErr) {
    console.error('seated count read failed (code):', goingErr?.code ?? 'unknown');
    return 'unknown';
  }

  const nowIso = new Date(nowMs).toISOString();
  const { data: pendingRows, error: pendingErr } = await service
    .from('event_orders')
    .select('buyer_user_id')
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .eq('status', 'pending')
    .gt('reserved_until', nowIso);
  if (pendingErr) {
    console.error('pending hold read failed (code):', pendingErr?.code ?? 'unknown');
    return 'unknown';
  }

  const { data: offers, error: offersErr } = await service
    .from('event_attendees')
    .select('user_id, offer_expires_at')
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .eq('status', 'waitlisted')
    .not('offer_expires_at', 'is', null);
  if (offersErr) {
    console.error('waitlist offer read failed (code):', offersErr?.code ?? 'unknown');
    return 'unknown';
  }

  const pending = pendingRows ?? [];
  const held = heldOfferCount(
    offers ?? [],
    new Set(pending.map((r) => r.buyer_user_id)),
    callerId,
    nowMs,
  );
  return capacityDecision(goingCount ?? 0, pending.length + held, capacity);
}
