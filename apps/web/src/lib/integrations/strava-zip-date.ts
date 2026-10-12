// Pure date parsing for the Strava bulk-export `activities.csv` "Activity
// Date" column. Extracted from strava-zip.ts so it can be unit-tested without
// the JSZip / supabase import chain (same reason strava-zip-header.ts and
// strava-zip-classify.ts are standalone).
//
// The bug this fixes: Strava emits "Activity Date" as a UTC wall-clock string
// WITHOUT a zone designator, e.g. "Apr 15, 2026, 1:00:00 PM". Feeding that to
// `new Date(...)` reads it in the importer's LOCAL zone, shifting every
// imported run by the local offset — a midnight run lands on the wrong day,
// week, and heatmap cell. We parse the documented no-zone shape explicitly as
// UTC. A value that already names its zone is left to the native parser so
// we never corrupt an offset it carries; a zone-less value in any shape we do
// not recognise is refused rather than read in the importer's zone.
//
// NOTE: written against Strava's DOCUMENTED export format without a real
// export fixture on hand. A real Strava bulk export should validate the format
// string(s) below pre-prod (decisions_or_risks).

const MONTHS: Record<string, number> = {
	jan: 0,
	feb: 1,
	mar: 2,
	apr: 3,
	may: 4,
	jun: 5,
	jul: 6,
	aug: 7,
	sep: 8,
	oct: 9,
	nov: 10,
	dec: 11,
};

// "Apr 15, 2026, 1:00:00 PM" — month name, day, year, h:m:s, optional AM/PM.
// Commas after the day and year are optional; the month may be the long form
// (we slice the first 3 chars for the lookup).
const NO_ZONE_RE =
	/^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4}),?\s+(\d{1,2}):(\d{2}):(\d{2})\s*([AP]M)?$/i;

// "15 Apr 2026, 13:00:00" — the same fields day-first, as a non-US export
// writes them. Still UTC wall-clock with no zone designator.
const DAY_FIRST_RE =
	/^(\d{1,2})\s+([A-Za-z]+)\.?,?\s+(\d{4}),?\s+(\d{1,2}):(\d{2}):(\d{2})\s*([AP]M)?$/i;

// "2026-04-15T13:00:00" / "2026-04-15 13:00" — ISO fields with no zone.
const ISO_NO_ZONE_RE = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/;

const ISO_DATE_ONLY_RE = /^\d{4}-\d{2}-\d{2}$/;

// A trailing `Z` / `±hh:mm` / `±hhmm`, or a GMT / UTC token: the value names
// its own zone, so the native parser reads it correctly wherever it runs.
const EXPLICIT_ZONE_RE = /(?:Z|[+-]\d{2}:?\d{2})$|\b(?:GMT|UTC)\b/i;

/// Parse a Strava CSV "Activity Date" cell into an ISO-8601 UTC instant.
///
/// - The documented no-zone shape (month-first or day-first) and a zone-less
///   ISO datetime are read as UTC wall-clock fields (Strava's documented
///   semantics) via `Date.UTC`.
/// - A value that names its own zone, or a date-only ISO value (which the
///   spec already reads as UTC), defers to the native `Date` parser.
/// - Anything else is null: the native parser would read a zone-less value in
///   the importer's own zone and shift the run by that offset. So is a
///   calendar date or clock that does not exist (Feb 30, 24:00), which
///   `Date.UTC` would otherwise roll into a neighbouring day. The caller
///   reports a null as a failed row rather than inventing a date.
export function parseStravaCsvDateToIso(raw: string | undefined | null): string | null {
	if (!raw) return null;
	const trimmed = raw.trim();
	if (!trimmed) return null;

	const named = NO_ZONE_RE.exec(trimmed);
	if (named) {
		return fromNamedMonth(named[1], named[2], named[3], named.slice(4, 8));
	}
	const dayFirst = DAY_FIRST_RE.exec(trimmed);
	if (dayFirst) {
		return fromNamedMonth(dayFirst[2], dayFirst[1], dayFirst[3], dayFirst.slice(4, 8));
	}
	const iso = ISO_NO_ZONE_RE.exec(trimmed);
	if (iso) {
		return utcIso(
			Number(iso[1]),
			Number(iso[2]) - 1,
			Number(iso[3]),
			Number(iso[4]),
			Number(iso[5]),
			Number(iso[6] ?? 0),
		);
	}
	if (ISO_DATE_ONLY_RE.test(trimmed) || EXPLICIT_ZONE_RE.test(trimmed)) {
		return nativeParse(trimmed);
	}
	return null;
}

function fromNamedMonth(
	monthName: string,
	dayText: string,
	yearText: string,
	[hourText, minuteText, secondText, ampmText]: string[],
): string | null {
	const month = MONTHS[monthName.slice(0, 3).toLowerCase()];
	if (month === undefined) return null;
	let hour = Number(hourText);
	const ampm = ampmText?.toUpperCase();
	if (ampm === 'PM' && hour < 12) hour += 12;
	if (ampm === 'AM' && hour === 12) hour = 0;
	return utcIso(Number(yearText), month, Number(dayText), hour, Number(minuteText), Number(secondText));
}

/// The UTC instant for these wall-clock fields, or null when any field is out
/// of range — checked by round-tripping, since `Date.UTC` normalises an
/// overflow into the next unit instead of refusing it.
function utcIso(
	year: number,
	month: number,
	day: number,
	hour: number,
	minute: number,
	second: number,
): string | null {
	if (hour > 23 || minute > 59 || second > 59) return null;
	const d = new Date(Date.UTC(year, month, day, hour, minute, second));
	if (d.getUTCFullYear() !== year || d.getUTCMonth() !== month || d.getUTCDate() !== day) {
		return null;
	}
	return d.toISOString();
}

function nativeParse(s: string): string | null {
	const d = new Date(s);
	return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
