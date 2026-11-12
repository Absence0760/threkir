// Which sentence an `event_cancel` notification reads as, on the bell popover
// and the full inbox. A paid registrant's row carries `refunded`
// (migration 20270725000002) and must say the payment is being refunded —
// "being", because events-cancel records the cancel before it calls Stripe, so
// the flag means a refund was owed and issued in that request, not that it has
// landed. Shared by both components because the four-way choice (refunded ×
// titled) is the part that can drift; the key namespace is the only difference.
//
// A row with no `event_id` reports the whole event deleted, not one occurrence
// cancelled: `notify_event_deleted` (20271112000013) writes it unlinked so the
// delete's cascade cannot erase it, with the title in the row's own
// `event_title`. That row is never a refunded one: no delete issues a refund.
// A user cannot delete a paid event (`guard_paid_event_delete`), and an account
// or club erasure that cascades past the guard leaves its paid buyers a plain
// cancel notice.
import type { MessageKey } from '#lib/i18n/messages.ts';

export type EventCancelSurface = 'notificationBell' | 'notificationsList';

export interface EventCancelMessage {
	key: MessageKey;
	params?: { title: string };
}

type Variant = 'plain' | 'refunded' | 'deleted';

const KEYS: Record<EventCancelSurface, Record<Variant, [titled: MessageKey, untitled: MessageKey]>> = {
	notificationBell: {
		plain: ['notificationBell.eventCancelTitled', 'notificationBell.eventCancel'],
		refunded: ['notificationBell.eventCancelRefundedTitled', 'notificationBell.eventCancelRefunded'],
		deleted: ['notificationBell.eventDeletedTitled', 'notificationBell.eventDeleted'],
	},
	notificationsList: {
		plain: ['notificationsList.verbEventCancelTitled', 'notificationsList.verbEventCancel'],
		refunded: ['notificationsList.verbEventCancelRefundedTitled', 'notificationsList.verbEventCancelRefunded'],
		deleted: ['notificationsList.verbEventDeletedTitled', 'notificationsList.verbEventDeleted'],
	},
};

export function eventCancelMessage(
	surface: EventCancelSurface,
	row: { refunded?: boolean | null; event_id?: string | null },
	eventTitle: string | null,
): EventCancelMessage {
	const variant: Variant =
		row.refunded === true ? 'refunded' : row.event_id === null ? 'deleted' : 'plain';
	const [titled, untitled] = KEYS[surface][variant];
	return eventTitle ? { key: titled, params: { title: eventTitle } } : { key: untitled };
}

export const EVENT_CANCEL_KEYS: readonly MessageKey[] = Object.values(KEYS).flatMap((s) => [
	...s.plain,
	...s.refunded,
	...s.deleted,
]);
