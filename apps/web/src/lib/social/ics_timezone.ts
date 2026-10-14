// RFC 5545 § 3.6.5 VTIMEZONE for a named IANA zone, derived from the
// platform's tz database. Every TZID a file cites must be defined in that file;
// Google and Apple Calendar resolve a recognised IANA name against their own
// database anyway, but Outlook and strict parsers read the offsets from here,
// so the component has to be right, not decorative.

import { wallClockIn, zoneOffsetMs } from './zoned_time';

const DAY_MS = 86_400_000;
// Offsets are sampled a week apart and each change is then bisected to the
// second. No zone in the tz database changes offset twice inside a week in the
// years a club series can reach, and the coarse step keeps a ten-year scan to a
// few hundred formatter calls.
const SAMPLE_MS = 7 * DAY_MS;
const WEEKDAY_CODES = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'] as const;

interface Transition {
	/** The UTC instant the new offset takes effect. */
	atMs: number;
	fromMs: number;
	toMs: number;
}

/** First instant in (lo, hi] whose offset equals hi's, to the second. */
function bisect(zone: string, lo: number, hi: number): number {
	const target = zoneOffsetMs(hi, zone);
	while (hi - lo > 1000) {
		const mid = lo + Math.floor((hi - lo) / 2000) * 1000;
		if (zoneOffsetMs(mid, zone) === target) hi = mid;
		else lo = mid;
	}
	return hi;
}

export function zoneTransitions(zone: string, fromMs: number, toMs: number): Transition[] {
	const out: Transition[] = [];
	let prevT = fromMs;
	let prev = zoneOffsetMs(prevT, zone);
	for (let t = fromMs + SAMPLE_MS; t <= toMs + SAMPLE_MS; t += SAMPLE_MS) {
		const cur = zoneOffsetMs(t, zone);
		if (cur !== prev) {
			const atMs = bisect(zone, prevT, t);
			out.push({ atMs, fromMs: prev, toMs: cur });
		}
		prevT = t;
		prev = cur;
	}
	return out;
}

function offsetText(ms: number): string {
	const sign = ms < 0 ? '-' : '+';
	const total = Math.abs(ms) / 1000;
	const p2 = (n: number) => String(n).padStart(2, '0');
	const h = Math.floor(total / 3600);
	const m = Math.floor((total % 3600) / 60);
	const s = total % 60;
	return `${sign}${p2(h)}${p2(m)}${s ? p2(s) : ''}`;
}

function localText(ms: number): string {
	const d = new Date(ms);
	const p2 = (n: number) => String(n).padStart(2, '0');
	return (
		`${String(d.getUTCFullYear()).padStart(4, '0')}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCDate())}` +
		`T${p2(d.getUTCHours())}${p2(d.getUTCMinutes())}${p2(d.getUTCSeconds())}`
	);
}

function utcText(ms: number): string {
	return `${localText(ms)}Z`;
}

/** The onset as the wall clock read just before it, which is how an
 * observance's DTSTART is written (§ 3.6.5: local time, TZOFFSETFROM in force). */
function onsetLocalMs(t: Transition): number {
	return t.atMs + t.fromMs;
}

/** The yearly BYDAY a run of same-shaped onsets follows (`2SU`, `-1SU`), or
 * null when no single nth-weekday or last-weekday rule covers all of them. */
function yearlyByday(onsets: number[]): string | null {
	const wd = new Date(onsets[0]).getUTCDay();
	const nth = (ms: number) => Math.ceil(new Date(ms).getUTCDate() / 7);
	const isLast = (ms: number) => {
		const d = new Date(ms);
		const dim = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
		return d.getUTCDate() + 7 > dim;
	};
	if (onsets.every((o) => nth(o) === nth(onsets[0])) && nth(onsets[0]) <= 4) {
		return `${nth(onsets[0])}${WEEKDAY_CODES[wd]}`;
	}
	if (onsets.every(isLast)) return `-1${WEEKDAY_CODES[wd]}`;
	return null;
}

/**
 * The VTIMEZONE lines for `zone`, valid for every instant from `coverFromMs`
 * on. Transitions are read over a window starting a year before it and
 * running `horizonYears` past it — long enough that a rule which only happens
 * to fit a few years (Israel's "Friday before the last Sunday" reads as the
 * fourth Friday until 2030) is caught and written out explicitly instead. Each
 * recurring shape (same offsets, month, weekday and wall-clock time, one per
 * consecutive year, on a stable nth or last weekday) becomes one observance
 * with a yearly RRULE — open-ended when it is still running at the end of the
 * window, closed with UNTIL when the zone stopped observing it. A transition
 * that fits no such rule is its own single-onset observance, so an irregular
 * zone is stated exactly over the window rather than approximated by a rule.
 */
export function buildVtimezone(zone: string, coverFromMs: number, horizonYears = 10): string[] {
	const scanFrom = coverFromMs - 400 * DAY_MS;
	const scanTo = coverFromMs + horizonYears * 366 * DAY_MS;
	const transitions = zoneTransitions(zone, scanFrom, scanTo);

	const lines = ['BEGIN:VTIMEZONE', `TZID:${zone}`];
	const observance = (t: Transition, extra: string[] = []) => {
		const kind = t.toMs > t.fromMs ? 'DAYLIGHT' : 'STANDARD';
		lines.push(
			`BEGIN:${kind}`,
			`DTSTART:${localText(onsetLocalMs(t))}`,
			`TZOFFSETFROM:${offsetText(t.fromMs)}`,
			`TZOFFSETTO:${offsetText(t.toMs)}`,
			...extra,
			`END:${kind}`
		);
	};

	if (!transitions.some((t) => t.atMs <= coverFromMs)) {
		const base = zoneOffsetMs(scanFrom, zone);
		observance({ atMs: Date.UTC(1970, 0, 1) - base, fromMs: base, toMs: base });
	}

	const groups = new Map<string, Transition[]>();
	for (const t of transitions) {
		const local = new Date(onsetLocalMs(t));
		const key = [
			t.fromMs,
			t.toMs,
			local.getUTCMonth(),
			local.getUTCDay(),
			local.getUTCHours() * 3600 + local.getUTCMinutes() * 60 + local.getUTCSeconds()
		].join('|');
		groups.set(key, [...(groups.get(key) ?? []), t]);
	}

	for (const group of groups.values()) {
		const years = group.map((t) => new Date(onsetLocalMs(t)).getUTCFullYear());
		const consecutive = years.every((y, i) => i === 0 || y === years[i - 1] + 1);
		const byday = group.length > 1 && consecutive ? yearlyByday(group.map(onsetLocalMs)) : null;
		if (!byday) {
			for (const t of group) observance(t);
			continue;
		}
		const first = group[0];
		const last = group[group.length - 1];
		const month = new Date(onsetLocalMs(first)).getUTCMonth() + 1;
		const stillRunning = scanTo - last.atMs < 366 * DAY_MS;
		observance(first, [
			`RRULE:FREQ=YEARLY;BYMONTH=${month};BYDAY=${byday}` +
				(stillRunning ? '' : `;UNTIL=${utcText(last.atMs)}`)
		]);
	}

	lines.push('END:VTIMEZONE');
	return lines;
}

/** `instant` as a TZID-qualified local DATE-TIME value in `zone`. */
export function localDateTimeText(instant: number, zone: string): string {
	const w = wallClockIn(instant, zone);
	return localText(Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second));
}
