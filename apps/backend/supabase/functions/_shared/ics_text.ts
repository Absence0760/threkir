// RFC 5545 content-line primitives shared by every .ics this product writes:
// the club-event download (`event_ics.ts`, built in the browser) and the
// subscribable training-plan feed (built by the `plan-calendar` Edge
// Function). The Edge Function cannot import from this tree at run time, so
// it carries a byte-for-byte copy at
// apps/backend/supabase/functions/_shared/ics_text.ts, and
// `_shared/ics_text_mirror.test.ts` fails the PR when the two differ. Edit
// this file, then copy it over. It imports nothing, so the copy runs
// unchanged under Deno and under tsx.

const encoder = new TextEncoder();

/** Escape a TEXT value per RFC 5545 §3.3.11 (backslash, semicolon, comma,
 * newline). Colon needs no escaping in a TEXT value. The grammar's TSAFE-CHAR
 * excludes every CONTROL character but HTAB, and no escape spells one, so
 * once the line breaks are escaped every other control character is dropped —
 * a NUL or vertical tab pasted into an event title made strict parsers refuse
 * the whole file. */
export function escapeText(value: string): string {
	return value
		.replace(/\\/g, '\\\\')
		.replace(/;/g, '\\;')
		.replace(/,/g, '\\,')
		.replace(/\r\n|\r|\n/g, '\\n')
		.replace(/[\u0000-\u0008\u000A-\u001F\u007F]/g, '');
}

/** Fold a content line to ≤75 octets per RFC 5545 §3.1, breaking on whole
 * code points (never mid-character) and prefixing continuations with a space. */
export function foldLine(line: string): string {
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

/** Join content lines into a document: each folded, CRLF-terminated. */
export function joinIcsLines(lines: readonly string[]): string {
	return lines.map(foldLine).join('\r\n') + '\r\n';
}

const p2 = (n: number) => String(n).padStart(2, '0');

/** Format an ISO instant as a UTC iCalendar date-time (`YYYYMMDDTHHMMSSZ`).
 * Returns null for an unparseable input. */
export function toIcsUtc(iso: string): string | null {
	const d = new Date(iso);
	const ms = d.getTime();
	if (Number.isNaN(ms)) return null;
	return (
		`${d.getUTCFullYear()}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCDate())}` +
		`T${p2(d.getUTCHours())}${p2(d.getUTCMinutes())}${p2(d.getUTCSeconds())}Z`
	);
}

const CALENDAR_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** A calendar date (`YYYY-MM-DD`, the shape a Postgres `date` serialises to)
 * as an iCalendar DATE value (`YYYYMMDD`), shifted by `addDays`. A DATE has
 * no zone: an all-day entry lands on that day in whatever zone the reader's
 * calendar is in, which is what a training day is. Returns null for anything
 * that is not a real date, so 2026-02-30 is refused rather than rolled into
 * March. */
export function toIcsDate(ymd: string, addDays = 0): string | null {
	const m = CALENDAR_DATE.exec(ymd);
	if (!m) return null;
	const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
	const base = new Date(Date.UTC(y, mo - 1, d));
	if (base.getUTCFullYear() !== y || base.getUTCMonth() !== mo - 1 || base.getUTCDate() !== d) {
		return null;
	}
	const u = new Date(Date.UTC(y, mo - 1, d + addDays));
	return `${String(u.getUTCFullYear()).padStart(4, '0')}${p2(u.getUTCMonth() + 1)}${p2(u.getUTCDate())}`;
}
