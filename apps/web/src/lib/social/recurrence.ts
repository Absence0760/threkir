// Client-side expansion of the enum-recurrence model used by Phase 2 events.
// See docs/architecture/decisions.md #10 — we deliberately avoided RFC 5545 RRULE in favour
// of (freq, byday[], until, count). Expansion is cheap, idempotent, and runs
// on every event-detail render; no need to materialise instances.

import type { Event, Weekday, RecurrenceFreq } from '../types';
import { isKnownTimeZone, zoneOffsetMs } from './zoned_time';

const WEEKDAY_LABEL: Record<Weekday, string> = {
	MO: 'Mon',
	TU: 'Tue',
	WE: 'Wed',
	TH: 'Thu',
	FR: 'Fri',
	SA: 'Sat',
	SU: 'Sun'
};

const ISO_ORDER: Weekday[] = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

// A recurring event's instance_start is its per-occurrence capacity key
// (20261018_001) and the live-race arm key, so every viewer's expansion must
// produce the identical instant. An occurrence is a LOCAL date in the event's
// own zone (events.timezone, 20270111_001): a weekday in `recurrence_byday`
// (else the local weekday of starts_at), biweekly counted in local weeks from
// the local Monday of starts_at, monthly on starts_at's local day-of-month
// clamped to the month's end, stamped at starts_at's local time of day. A
// wall-clock that does not exist (spring-forward gap) moves forward by the
// gap; one that exists twice (fall-back overlap) takes the EARLIER instant,
// as RFC 5545 does. The occurrence on starts_at's own local date is starts_at
// itself (to the second), so a series started in the second pass of an
// overlap hour keeps its first occurrence. A zone the runtime cannot resolve
// expands in UTC. A legacy series with no timezone expands in the VIEWER's
// zone, as it always has, so its placed RSVPs keep their keys. Mirrors
// apps/mobile_android/lib/recurrence.dart and private.event_occurrences /
// private.is_event_occurrence (decisions § 1918).
interface Zone {
	offset(t: number): number;
}

const DAY = 86_400_000;

const utcZone: Zone = { offset: () => 0 };

const localZone: Zone = { offset: (t) => -new Date(t).getTimezoneOffset() * 60_000 };

function namedZone(name: string): Zone | null {
	if (!isKnownTimeZone(name)) return null;
	return { offset: (t) => zoneOffsetMs(t, name) };
}

function eventZone(timezone: string | null | undefined): Zone {
	if (!timezone) return localZone;
	if (timezone === 'UTC') return utcZone;
	return namedZone(timezone) ?? utcZone;
}

function wallToInstant(zone: Zone, wall: number): number {
	const before = zone.offset(wall - DAY);
	const after = zone.offset(wall + DAY);
	let best: number | null = null;
	for (const o of [before, after]) {
		const t = wall - o;
		if (zone.offset(t) === o && (best === null || t < best)) best = t;
	}
	return best ?? wall - before;
}

function isoDow(day: number): number {
	return ((((day + 3) % 7) + 7) % 7) + 1;
}

/**
 * Expand a recurring event into instance start times within [from, to], or
 * return [starts_at] for a non-recurring event. Bounded by the event's
 * `recurrence_until` and `recurrence_count` as well.
 */
export function expandInstances(event: Event, from: Date, to: Date, max = 100): Date[] {
	const start = new Date(event.starts_at);
	if (!event.recurrence_freq) {
		return start >= from && start <= to ? [start] : [];
	}

	const zone = eventZone(event.timezone);
	const until = event.recurrence_until ? new Date(event.recurrence_until) : null;
	const hardCap = event.recurrence_count ?? Infinity;
	const results: Date[] = [];
	// `stamp` rebuilds every instant from whole seconds, so a `starts_at`
	// carrying a non-zero millisecond is compared, and stands as its own first
	// occurrence, at that resolution.
	const startSecond = Math.floor(start.getTime() / 1000) * 1000;
	const startLocal = startSecond + zone.offset(startSecond);
	const startDay = Math.floor(startLocal / DAY);
	const timeOfDay = startLocal - startDay * DAY;
	const stamp = (day: number) =>
		day === startDay ? startSecond : wallToInstant(zone, day * DAY + timeOfDay);
	const localDay = (t: number) => Math.floor((t + zone.offset(t)) / DAY);
	// The walk always starts at `starts_at` (occurrences before `from` still
	// count toward `recurrence_count`), so its budget has to reach the far end
	// of the requested window, not `max` periods past the start.
	const scanEnd = until && until < to ? until : to;

	let produced = 0;
	if (event.recurrence_freq === 'monthly') {
		// Each instance is `i` whole months from start with the day clamped to
		// the target month's last day (Jan-31 → Feb-28/29). Stepping a running
		// cursor would let a clamp permanently shrink the day-of-month.
		const s = new Date(startDay * DAY);
		const e = new Date(localDay(scanEnd.getTime()) * DAY);
		const monthBudget =
			(e.getUTCFullYear() - s.getUTCFullYear()) * 12 + (e.getUTCMonth() - s.getUTCMonth()) + 1;
		for (let i = 0; produced < hardCap; i++) {
			if (i > monthBudget) break;
			const total = s.getUTCMonth() + i;
			const year = s.getUTCFullYear() + Math.floor(total / 12);
			const month = ((total % 12) + 12) % 12;
			const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
			const cursor = new Date(
				stamp(Date.UTC(year, month, Math.min(s.getUTCDate(), lastDay)) / DAY)
			);
			if (until && cursor > until) break;
			// recurrence_count caps TOTAL occurrences from starts_at, not the
			// ones that happen to fall inside [from, to].
			produced++;
			if (cursor > to) break;
			if (cursor >= from) {
				results.push(cursor);
				if (results.length >= max) break;
			}
		}
		return results;
	}

	const stepWeeks = event.recurrence_freq === 'biweekly' ? 2 : 1;
	const byday: Weekday[] = event.recurrence_byday?.length
		? (event.recurrence_byday as Weekday[])
		: [ISO_ORDER[isoDow(startDay) - 1]];
	// Weeks are counted from the local Monday of starts_at's week, matching the
	// Dart twin and the SQL.
	const anchor = startDay - (isoDow(startDay) - 1);
	const lastScanDay = localDay(scanEnd.getTime()) + 1;
	for (let day = startDay; day <= lastScanDay; day++) {
		if (Math.floor((day - anchor) / 7) % stepWeeks !== 0) continue;
		if (!byday.includes(ISO_ORDER[isoDow(day) - 1])) continue;

		const stamped = new Date(stamp(day));
		if (until && stamped > until) continue;
		if (stamped > to) continue;
		if (stamped.getTime() < startSecond) continue;

		// Every real occurrence counts toward recurrence_count, in-window or
		// not, and the cap is checked BEFORE counting so a stored count of 0
		// yields no occurrence (decisions § 1910).
		if (produced >= hardCap) break;
		produced++;
		if (stamped >= from) {
			results.push(stamped);
			if (results.length >= max) break;
		}
	}
	return results;
}

export function nextInstanceAfter(event: Event, after = new Date()): Date | null {
	const in10Years = new Date(after.getTime() + 10 * 365 * 24 * 3600 * 1000);
	const [first] = expandInstances(event, after, in10Years, 1);
	return first ?? null;
}

export function describeRecurrence(
	freq: RecurrenceFreq | null,
	byday: Weekday[] | null | undefined
): string {
	if (!freq) return 'One-off event';
	if (freq === 'monthly') return 'Repeats monthly';
	const days = (byday ?? []).length
		? ISO_ORDER.filter((d) => byday!.includes(d)).map((d) => WEEKDAY_LABEL[d]).join(', ')
		: '';
	const base = freq === 'biweekly' ? 'Every other week' : 'Every week';
	return days ? `${base} · ${days}` : base;
}

export const WEEKDAY_CHOICES: { code: Weekday; label: string }[] = ISO_ORDER.map((code) => ({
	code,
	label: WEEKDAY_LABEL[code]
}));

