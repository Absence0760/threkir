// Which sentence a `park_course_month_closed` notification reads as, on the
// bell popover and the full inbox (issue #1343). The row carries the course,
// the month as the park-local 1st and the runner's best time from it, never a
// rank (decisions § 2511). A course the reader can no longer see (its park or
// segment pulled) or a row missing its month or time reads as the plain
// sentence rather than a half-filled one. Shared by both components, like
// `event_cancel_copy.ts`; the key namespace is the only difference.
import type { MessageKey } from '#lib/i18n/messages.ts';
import { monthYearLabel } from '#lib/format/calendar.ts';
import { formatDuration } from '#lib/format/time.ts';

export type ParkMonthNoticeSurface = 'notificationBell' | 'notificationsList';

export interface ParkMonthNoticeMessage {
	key: MessageKey;
	params?: { course: string; month: string; time: string };
}

const KEYS: Record<ParkMonthNoticeSurface, [named: MessageKey, plain: MessageKey]> = {
	notificationBell: ['notificationBell.parkCourseMonthClosedNamed', 'notificationBell.parkCourseMonthClosed'],
	notificationsList: ['notificationsList.verbParkCourseMonthClosedNamed', 'notificationsList.verbParkCourseMonthClosed'],
};

/** `2026-10-01` → `{ season: 2026, month: 10 }`; null for anything else. */
export function parkNoticeMonth(raw: string | null | undefined): { season: number; month: number } | null {
	const m = /^(\d{4})-(\d{2})-\d{2}/.exec(raw ?? '');
	if (!m) return null;
	const month = Number(m[2]);
	return month >= 1 && month <= 12 ? { season: Number(m[1]), month } : null;
}

export function parkMonthNoticeMessage(
	surface: ParkMonthNoticeSurface,
	row: { park_course_month?: string | null; park_course_time_s?: number | null },
	courseName: string | null,
	locale: string | undefined,
): ParkMonthNoticeMessage {
	const [named, plain] = KEYS[surface];
	const month = parkNoticeMonth(row.park_course_month);
	const time = row.park_course_time_s;
	if (!courseName || !month || time == null || !Number.isFinite(time) || time <= 0) return { key: plain };
	return {
		key: named,
		params: {
			course: courseName,
			month: monthYearLabel(month.season, month.month, locale),
			time: formatDuration(time),
		},
	};
}

export const PARK_MONTH_NOTICE_KEYS: readonly MessageKey[] = Object.values(KEYS).flat();
