// Which sentence an `event_cancel` notification reads as, on the bell popover
// and the full inbox. A paid registrant's row carries `refunded`
// (migration 20270725000002) and must say the payment is being refunded —
// "being", because events-cancel records the cancel before it calls Stripe, so
// the flag means a refund was owed and issued in that request, not that it has
// landed. Shared by both components because the four-way choice (refunded ×
// titled) is the part that can drift; the key namespace is the only difference.
import type { MessageKey } from '#lib/i18n/messages.ts';

export type EventCancelSurface = 'notificationBell' | 'notificationsList';

export interface EventCancelMessage {
	key: MessageKey;
	params?: { title: string };
}

const KEYS: Record<EventCancelSurface, Record<'plain' | 'refunded', [titled: MessageKey, untitled: MessageKey]>> = {
	notificationBell: {
		plain: ['notificationBell.eventCancelTitled', 'notificationBell.eventCancel'],
		refunded: ['notificationBell.eventCancelRefundedTitled', 'notificationBell.eventCancelRefunded'],
	},
	notificationsList: {
		plain: ['notificationsList.verbEventCancelTitled', 'notificationsList.verbEventCancel'],
		refunded: ['notificationsList.verbEventCancelRefundedTitled', 'notificationsList.verbEventCancelRefunded'],
	},
};

export function eventCancelMessage(
	surface: EventCancelSurface,
	row: { refunded?: boolean | null },
	eventTitle: string | null,
): EventCancelMessage {
	const [titled, untitled] = KEYS[surface][row.refunded === true ? 'refunded' : 'plain'];
	return eventTitle ? { key: titled, params: { title: eventTitle } } : { key: untitled };
}

export const EVENT_CANCEL_KEYS: readonly MessageKey[] = Object.values(KEYS).flatMap((s) => [
	...s.plain,
	...s.refunded,
]);
