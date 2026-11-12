// Wall-clock arithmetic in a named IANA zone, read off the platform's own tz
// database through Intl — the browser has no other zone source, and Temporal
// is not shipped everywhere this app runs. Pure and machine-zone-independent:
// every answer depends only on the instant and the zone name passed in.

export interface WallClock {
	year: number;
	/** 1–12. */
	month: number;
	day: number;
	hour: number;
	minute: number;
	second: number;
	/** 0 = Sunday … 6 = Saturday, as `Date.getUTCDay`. */
	weekday: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatterFor(zone: string): Intl.DateTimeFormat {
	let f = formatters.get(zone);
	if (!f) {
		f = new Intl.DateTimeFormat('en-US', {
			timeZone: zone,
			hourCycle: 'h23',
			year: 'numeric',
			month: 'numeric',
			day: 'numeric',
			hour: 'numeric',
			minute: 'numeric',
			second: 'numeric'
		});
		formatters.set(zone, f);
	}
	return f;
}

/** True when the platform's tz database knows `zone`. */
export function isKnownTimeZone(zone: string | null | undefined): zone is string {
	if (!zone) return false;
	try {
		formatterFor(zone);
		return true;
	} catch {
		return false;
	}
}

/** The wall clock `instant` reads in `zone`. Throws on an unknown zone. */
export function wallClockIn(instant: Date | number, zone: string): WallClock {
	const ms = typeof instant === 'number' ? instant : instant.getTime();
	const parts: Record<string, number> = {};
	for (const p of formatterFor(zone).formatToParts(new Date(ms))) {
		if (p.type !== 'literal') parts[p.type] = Number(p.value);
	}
	const { year, month, day, hour, minute, second } = parts;
	return {
		year,
		month,
		day,
		hour,
		minute,
		second,
		weekday: new Date(Date.UTC(year, month - 1, day)).getUTCDay()
	};
}

/** UTC offset of `zone` at `instant`, in milliseconds east of UTC, at whole-
 * second resolution (the formatter reports no finer). */
export function zoneOffsetMs(instant: Date | number, zone: string): number {
	const ms = typeof instant === 'number' ? instant : instant.getTime();
	const w = wallClockIn(ms, zone);
	const asUtc = Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second);
	return asUtc - (ms - (((ms % 1000) + 1000) % 1000));
}

const DAY_MS = 86_400_000;

/** The instant a wall-clock reading names in `zone`, resolved the RFC 5545
 * § 3.3.5 way: a reading inside a spring-forward gap is taken with the offset
 * in force before the gap (02:30 → 03:30 on a one-hour gap), and a reading the
 * fall-back hour repeats takes the EARLIER of its two instants. */
export function instantForWallClock(
	w: Pick<WallClock, 'year' | 'month' | 'day' | 'hour' | 'minute' | 'second'>,
	zone: string
): Date {
	const naive = Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second);
	const before = zoneOffsetMs(naive - DAY_MS, zone);
	const after = zoneOffsetMs(naive + DAY_MS, zone);
	const matches = [...new Set([before, after])]
		.map((offset) => naive - offset)
		.filter((t) => zoneOffsetMs(t, zone) === naive - t)
		.sort((a, b) => a - b);
	return new Date(matches[0] ?? naive - before);
}
