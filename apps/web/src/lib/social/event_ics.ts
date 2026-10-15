// RFC 5545 iCalendar (.ics) builder for a club event — either a single
// occurrence or the whole recurring series (RRULE + EXDATE), so a member of a
// weekly club run drops every future Saturday into their calendar once instead
// of re-downloading each week. Web-only: mobile clients hand off to the OS
// calendar via native intents, so there is no Dart twin. Pure +
// locale/unit-agnostic — the SUMMARY / DESCRIPTION / LOCATION carry the event's
// own text, never a translated label.

import type { Event, RecurrenceFreq, Weekday } from '../types';
import { expandInstances } from './recurrence';
import { buildVtimezone } from './ics_timezone';
import { instantForWallClock, isKnownTimeZone, wallClockIn } from './zoned_time';

// The app's Weekday codes ARE the RFC 5545 weekday abbreviations, so the RRULE
// needs no translation table — only these two orderings of them.
const WEEKDAY_BY_UTC_DAY: readonly Weekday[] = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
const WEEKDAY_ORDER: Weekday[] = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/** The app's (freq, byday[], until, count) recurrence model, restated in the
 * terms an RRULE needs. The weekdays and day-of-month are read on the clock the
 * DTSTART is written in — the event's own zone for a series (see
 * `buildEventSeriesIcs`), UTC for a bare `startIso`. */
export interface IcsRecurrence {
	freq: RecurrenceFreq;
	/** Weekdays the series lands on. Weekly / biweekly only. */
	byday?: readonly Weekday[] | null;
	/** Day-of-month. Monthly only. */
	monthDay?: number | null;
	/** Inclusive end instant. Ignored when `count` is set — RFC 5545 §3.3.10
	 * forbids UNTIL and COUNT in the same rule. */
	untilIso?: string | null;
	/** Total occurrences including the DTSTART one. */
	count?: number | null;
}

export interface IcsEventInput {
	/** Stable unique identifier for this occurrence. Re-importing the same value
	 * updates the calendar entry instead of duplicating it. */
	uid: string;
	title: string;
	/** ISO instant for the occurrence's start (an absolute point in time). */
	startIso: string;
	/** Occurrence length in minutes; when set, emits DTEND. */
	durationMin?: number | null;
	description?: string | null;
	location?: string | null;
	url?: string | null;
	/** DTSTAMP source; injectable for deterministic tests. Defaults to now. */
	nowMs?: number;
	/** When set, the VEVENT describes a whole series rather than one occurrence.
	 * A recurrence the RRULE grammar cannot express faithfully fails the whole
	 * build (null) rather than degrading to a single occurrence — a calendar
	 * that silently disagrees with the app is worse than no calendar entry. */
	recurrence?: IcsRecurrence | null;
	/** Occurrences to subtract from the series (cancelled `event_exceptions`).
	 * Only emitted alongside `recurrence`, and only when `local` is unset. */
	exdatesIso?: readonly string[] | null;
	/** Writes DTSTART and EXDATE as wall-clock readings in a named zone and
	 * defines that zone with a VTIMEZONE, so an RRULE expands on the zone's
	 * clock — same local time across DST — rather than at a fixed UTC offset.
	 * `startIso` then only bounds the VTIMEZONE; DTSTART comes from here. */
	local?: IcsLocalStart | null;
}

export interface IcsLocalStart {
	/** IANA zone name, cited as TZID. */
	tzid: string;
	/** DTSTART's reading, `YYYYMMDDTHHMMSS`. A reading a DST gap skips is
	 * legal and resolves forward (RFC 5545 §3.3.5). */
	dtstart: string;
	/** EXDATE readings in the same form. */
	exdates?: readonly string[] | null;
}

const LOCAL_DATE_TIME = /^\d{8}T\d{6}$/;

/** Escape a TEXT value per RFC 5545 §3.3.11 (backslash, semicolon, comma,
 * newline). Colon needs no escaping in a TEXT value. The grammar's TSAFE-CHAR
 * excludes every CONTROL character but HTAB, and no escape spells one, so
 * once the line breaks are escaped every other control character is dropped —
 * a NUL or vertical tab pasted into an event title made strict parsers refuse
 * the whole file. */
function escapeText(value: string): string {
	return value
		.replace(/\\/g, '\\\\')
		.replace(/;/g, '\\;')
		.replace(/,/g, '\\,')
		.replace(/\r\n|\r|\n/g, '\\n')
		.replace(/[\u0000-\u0008\u000A-\u001F\u007F]/g, '');
}

/** Format an ISO instant as a UTC iCalendar date-time (`YYYYMMDDTHHMMSSZ`).
 * A single occurrence is one instant, so it needs no VTIMEZONE; a series is
 * written on its zone's wall clock instead (`IcsEventInput.local`). Returns
 * null for an unparseable input. */
export function toIcsUtc(iso: string): string | null {
	const d = new Date(iso);
	const ms = d.getTime();
	if (Number.isNaN(ms)) return null;
	const p2 = (n: number) => String(n).padStart(2, '0');
	return (
		`${d.getUTCFullYear()}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCDate())}` +
		`T${p2(d.getUTCHours())}${p2(d.getUTCMinutes())}${p2(d.getUTCSeconds())}Z`
	);
}

/** Render an `IcsRecurrence` as an RRULE value (no `RRULE:` prefix), or null
 * when the series cannot be stated faithfully.
 *
 * The one shape that fails is a monthly series anchored after the 28th: the app
 * clamps a missing day-of-month to the month's last day (Jan 31 → Feb 28), and
 * BYMONTHDAY has no clamp — it skips the short month outright. Emitting it
 * anyway would put a different set of dates in the member's calendar than the
 * one the club page shows, so the series export is withheld for those instead.
 */
export function buildRrule(r: IcsRecurrence): string | null {
	const parts: string[] = [];

	if (r.freq === 'monthly') {
		if (r.monthDay == null || !Number.isInteger(r.monthDay)) return null;
		if (r.monthDay < 1 || r.monthDay > 28) return null;
		parts.push('FREQ=MONTHLY');
	} else {
		parts.push('FREQ=WEEKLY');
		if (r.freq === 'biweekly') parts.push('INTERVAL=2');
	}

	if (r.count != null) {
		if (!Number.isInteger(r.count) || r.count < 1) return null;
		parts.push(`COUNT=${r.count}`);
	} else if (r.untilIso != null) {
		const until = toIcsUtc(r.untilIso);
		if (!until) return null;
		parts.push(`UNTIL=${until}`);
	}

	if (r.freq === 'monthly') {
		parts.push(`BYMONTHDAY=${r.monthDay}`);
	} else if (r.byday?.length) {
		if (r.byday.some((d) => !WEEKDAY_ORDER.includes(d))) return null;
		parts.push(`BYDAY=${WEEKDAY_ORDER.filter((d) => r.byday!.includes(d)).join(',')}`);
	}

	return parts.join(';');
}

const encoder = new TextEncoder();

/** Fold a content line to ≤75 octets per RFC 5545 §3.1, breaking on whole
 * code points (never mid-character) and prefixing continuations with a space. */
function foldLine(line: string): string {
	if (encoder.encode(line).length <= 75) return line;
	const out: string[] = [];
	let current = '';
	let currentBytes = 0;
	// Continuation lines carry a leading space, so cap their payload at 74 octets.
	let limit = 75;
	for (const ch of line) {
		const chBytes = encoder.encode(ch).length;
		if (currentBytes + chBytes > limit) {
			out.push(current);
			current = ch;
			currentBytes = chBytes;
			limit = 74;
		} else {
			current += ch;
			currentBytes += chBytes;
		}
	}
	out.push(current);
	return out.join('\r\n ');
}

/** Build a complete VCALENDAR document (CRLF line endings) wrapping one VEVENT
 * for the given occurrence. Returns null when the start instant is invalid. */
export function buildEventIcs(input: IcsEventInput): string | null {
	const dtStart = toIcsUtc(input.startIso);
	if (!dtStart) return null;
	const dtStamp = toIcsUtc(new Date(input.nowMs ?? Date.now()).toISOString());
	if (!dtStamp) return null;

	const local = input.local ?? null;
	if (local) {
		if (!isKnownTimeZone(local.tzid) || !LOCAL_DATE_TIME.test(local.dtstart)) return null;
		if ((local.exdates ?? []).some((v) => !LOCAL_DATE_TIME.test(v))) return null;
	}

	const lines: string[] = [
		'BEGIN:VCALENDAR',
		'VERSION:2.0',
		'PRODID:-//Threkir//Run App//EN',
		'CALSCALE:GREGORIAN',
		'METHOD:PUBLISH',
		...(local ? buildVtimezone(local.tzid, new Date(input.startIso).getTime()) : []),
		'BEGIN:VEVENT',
		`UID:${input.uid}`,
		`DTSTAMP:${dtStamp}`,
		local ? `DTSTART;TZID=${local.tzid}:${local.dtstart}` : `DTSTART:${dtStart}`
	];

	if (local) {
		// A wall-clock DTEND would be nominal time and stretch or shrink the
		// occurrence that crosses a DST change; DURATION is exact for every
		// member of the set (RFC 5545 §3.8.5.3).
		if (input.durationMin != null && input.durationMin > 0) {
			lines.push(`DURATION:PT${Math.round(input.durationMin)}M`);
		}
	} else if (input.durationMin != null && input.durationMin > 0) {
		const end = toIcsUtc(
			new Date(new Date(input.startIso).getTime() + input.durationMin * 60_000).toISOString()
		);
		if (end) lines.push(`DTEND:${end}`);
	}

	if (input.recurrence) {
		const rrule = buildRrule(input.recurrence);
		if (!rrule) return null;
		lines.push(`RRULE:${rrule}`);
		const exdates = local
			? [...new Set(local.exdates ?? [])].sort()
			: [
			...new Set(
				(input.exdatesIso ?? [])
					.map(toIcsUtc)
					.filter((v): v is string => v !== null)
			)
		].sort();
		// EXDATE takes a value list whose type must match DTSTART's (UTC
		// date-time here), so these are raw values, never TEXT-escaped.
		if (exdates.length) {
			lines.push(
				local
					? `EXDATE;TZID=${local.tzid}:${exdates.join(',')}`
					: `EXDATE:${exdates.join(',')}`
			);
		}
	}

	lines.push(`SUMMARY:${escapeText(input.title)}`);
	if (input.description) lines.push(`DESCRIPTION:${escapeText(input.description)}`);
	if (input.location) lines.push(`LOCATION:${escapeText(input.location)}`);
	if (input.url) lines.push(`URL:${input.url}`);

	lines.push('END:VEVENT', 'END:VCALENDAR');

	return lines.map(foldLine).join('\r\n') + '\r\n';
}

export interface EventSeriesIcsOptions {
	/** `event_exceptions.instance_start` values — the cancelled occurrences,
	 * subtracted from the series via EXDATE. */
	cancelledIso?: readonly string[] | null;
	url?: string | null;
	nowMs?: number;
	/** The zone a legacy series with no stored `timezone` is written in.
	 * Defaults to the browser's, which is the zone the page expands it in. */
	viewerZone?: string | null;
}

function browserZone(): string {
	try {
		return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
	} catch {
		return 'UTC';
	}
}

interface LocalDate {
	year: number;
	month: number;
	day: number;
	weekday: number;
}

function addLocalDays(d: LocalDate, n: number): LocalDate {
	const u = new Date(Date.UTC(d.year, d.month - 1, d.day + n));
	return {
		year: u.getUTCFullYear(),
		month: u.getUTCMonth() + 1,
		day: u.getUTCDate(),
		weekday: u.getUTCDay()
	};
}

function localDateText(d: LocalDate): string {
	const p2 = (n: number) => String(n).padStart(2, '0');
	return `${String(d.year).padStart(4, '0')}${p2(d.month)}${p2(d.day)}`;
}

/** The series' dates in its own zone from the start's date on, in order:
 * every date carrying a stored weekday (in the even weeks counted from the
 * Monday of the start's week, for a biweekly series); a monthly series opens
 * on the start's own date. */
function* seriesDates(
	freq: RecurrenceFreq,
	byday: readonly Weekday[],
	start: LocalDate
): Generator<LocalDate> {
	if (freq === 'monthly') {
		yield start;
		return;
	}
	const sinceMonday = (start.weekday + 6) % 7;
	const monday = addLocalDays(start, -sinceMonday);
	for (let offset = sinceMonday; offset < 35; offset++) {
		if (freq === 'biweekly' && Math.floor(offset / 7) % 2 !== 0) continue;
		const d = addLocalDays(monday, offset);
		if (byday.includes(WEEKDAY_BY_UTC_DAY[d.weekday])) yield d;
	}
}

/** Build a whole-series .ics for a recurring club event: one VEVENT carrying an
 * RRULE, so the member's calendar maintains every future occurrence itself.
 * Returns null for a one-off event, or when the series cannot be expressed as
 * an RRULE without diverging from what the app shows.
 *
 * The stored recurrence fields are wall-clock in the event's own zone — the
 * weekday codes are the organiser's local weekdays and every occurrence keeps
 * `starts_at`'s local time-of-day across DST — so the file speaks that clock:
 * DTSTART and EXDATE carry the event's TZID, a VTIMEZONE defines it, and the
 * RRULE restates the stored codes verbatim. RFC 5545 resolves a DST-gap
 * reading forward and an ambiguous one to its earlier instant, which is the
 * rule the app expands by. A legacy series with no stored zone expands in
 * each viewer's own zone, so it is written in the viewer's zone and the file
 * agrees with the page that viewer downloaded it from. */
export function buildEventSeriesIcs(
	event: Event,
	opts: EventSeriesIcsOptions = {}
): string | null {
	const freq = event.recurrence_freq;
	if (!freq) return null;
	const startMs = new Date(event.starts_at).getTime();
	if (Number.isNaN(startMs)) return null;
	const zone = event.timezone || opts.viewerZone || browserZone();
	if (!isKnownTimeZone(zone)) return null;

	const start = wallClockIn(startMs, zone);
	const stored = event.recurrence_byday ?? [];
	if (stored.some((d) => !WEEKDAY_ORDER.includes(d))) return null;
	const byday: Weekday[] = stored.length
		? WEEKDAY_ORDER.filter((d) => stored.includes(d))
		: [WEEKDAY_BY_UTC_DAY[start.weekday]];

	// DTSTART has to be a real member of the recurrence set (RFC 5545 §3.8.5.3):
	// when starts_at falls on a weekday outside recurrence_byday the series
	// begins at the first date that carries one, and anchoring on starts_at
	// would add a phantom occurrence the club page never shows.
	const startSecond = startMs - (((startMs % 1000) + 1000) % 1000);
	const anchorDate = seriesDates(freq, byday, start).next().value;
	if (!anchorDate) return null;
	const anchorMs = instantForWallClock(
		{ ...anchorDate, hour: start.hour, minute: start.minute, second: start.second },
		zone
	).getTime();
	// A start in the second pass of a fall-back hour is its own first
	// occurrence, and a TZID reading names the first pass (RFC 5545 §3.3.5), so
	// no DTSTART can state it — withheld rather than moved an hour.
	if (anchorMs < startSecond) return null;
	if (event.recurrence_until != null) {
		const untilMs = new Date(event.recurrence_until).getTime();
		if (!Number.isNaN(untilMs) && anchorMs > untilMs) return null;
	}

	const p2 = (n: number) => String(n).padStart(2, '0');
	const timeText = `T${p2(start.hour)}${p2(start.minute)}${p2(start.second)}`;
	const exdates = (opts.cancelledIso ?? []).flatMap((iso) => {
		const ms = new Date(iso).getTime();
		if (Number.isNaN(ms)) return [];
		return [localDateText(wallClockIn(ms, zone)) + timeText];
	});

	return buildEventIcs({
		uid: `event-${event.id}-series@threkir.com`,
		title: event.title,
		startIso: new Date(anchorMs).toISOString(),
		durationMin: event.duration_min,
		description: event.description,
		location: event.meet_label,
		url: opts.url ?? null,
		nowMs: opts.nowMs,
		local: { tzid: zone, dtstart: localDateText(anchorDate) + timeText, exdates },
		recurrence: {
			freq,
			...resolveSeriesEnd(event, new Date(startMs)),
			...(freq === 'monthly' ? { monthDay: start.day } : { byday })
		}
	});
}

/** The app applies `recurrence_until` and `recurrence_count` together; an RRULE
 * may carry only one. Where both are set, count the real occurrences inside the
 * until-bound so whichever binds first survives the translation. */
function resolveSeriesEnd(
	event: Event,
	seriesStart: Date
): { count?: number; untilIso?: string } {
	const { recurrence_count: count, recurrence_until: untilIso } = event;
	if (count != null && untilIso != null) {
		const until = new Date(untilIso);
		if (Number.isNaN(until.getTime())) return { count };
		return { count: expandInstances(event, seriesStart, until, count).length };
	}
	if (count != null) return { count };
	if (untilIso != null) return { untilIso };
	return {};
}

/** A filesystem-safe .ics filename derived from the event title. */
export function icsFilename(title: string): string {
	const slug = title
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '')
		.slice(0, 60);
	return `${slug || 'event'}.ics`;
}
