// A paid occurrence's waitlist offer (migration 20270726000002, decisions
// § 1840): when a seat frees, the earliest waitlister is not seated but
// OFFERED it until `event_attendees.offer_expires_at`, and told so by an
// `event_waitlist_slot` notification. This module is the two pure halves the
// web renders from: which sentence the notification reads as on the bell and
// the inbox, and what the viewer's own row says about their place.
import type { MessageKey } from '#lib/i18n/messages.ts';

export type WaitlistSlotSurface = 'notificationBell' | 'notificationsList';

export interface WaitlistSlotMessage {
	key: MessageKey;
	params?: { title: string };
}

const KEYS: Record<WaitlistSlotSurface, [titled: MessageKey, untitled: MessageKey]> = {
	notificationBell: ['notificationBell.waitlistSlotTitled', 'notificationBell.waitlistSlot'],
	notificationsList: ['notificationsList.verbWaitlistSlotTitled', 'notificationsList.verbWaitlistSlot'],
};

export function waitlistSlotMessage(
	surface: WaitlistSlotSurface,
	eventTitle: string | null,
): WaitlistSlotMessage {
	const [titled, untitled] = KEYS[surface];
	return eventTitle ? { key: titled, params: { title: eventTitle } } : { key: untitled };
}

export const WAITLIST_SLOT_KEYS: readonly MessageKey[] = Object.values(KEYS).flat();

/// The viewer's place on a paid occurrence's waitlist, read off their own
/// attendee row.
///   - `none`    — not on the waitlist (no row, or any other status).
///   - `waiting` — queued; nothing has been offered.
///   - `offered` — a seat is held for them until `deadline`; Register claims it.
///   - `lapsed`  — the deadline has passed and the mover has not removed the
///                 row yet. Nothing is held any more, so the page must not
///                 promise the seat; checkout decides whether one is free.
export type WaitlistOfferState =
	| { kind: 'none' }
	| { kind: 'waiting' }
	| { kind: 'offered'; deadline: string }
	| { kind: 'lapsed' };

export function waitlistOfferState(
	row: { status: string; offer_expires_at: string | null } | null,
	nowMs: number,
): WaitlistOfferState {
	if (!row || row.status !== 'waitlisted') return { kind: 'none' };
	if (row.offer_expires_at === null) return { kind: 'waiting' };
	const deadlineMs = Date.parse(row.offer_expires_at);
	if (!Number.isFinite(deadlineMs) || deadlineMs <= nowMs) return { kind: 'lapsed' };
	return { kind: 'offered', deadline: row.offer_expires_at };
}
