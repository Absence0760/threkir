import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildVtimezone, zoneTransitions } from './ics_timezone';

const at = (iso: string) => Date.parse(iso);

function components(lines: string[]): string[][] {
	const out: string[][] = [];
	let cur: string[] | null = null;
	for (const l of lines) {
		if (l === 'BEGIN:STANDARD' || l === 'BEGIN:DAYLIGHT') cur = [l];
		else if (cur) {
			cur.push(l);
			if (l.startsWith('END:')) {
				out.push(cur);
				cur = null;
			}
		}
	}
	return out;
}

test('zoneTransitions finds each offset change to the second', () => {
	const ts = zoneTransitions('America/New_York', at('2026-01-01T00:00:00Z'), at('2026-12-31T00:00:00Z'));
	assert.deepEqual(
		ts.map((t) => [new Date(t.atMs).toISOString(), t.fromMs / 3_600_000, t.toMs / 3_600_000]),
		[
			['2026-03-08T07:00:00.000Z', -5, -4],
			['2026-11-01T06:00:00.000Z', -4, -5]
		]
	);
});

test('buildVtimezone states a regular DST zone as two yearly rules', () => {
	const lines = buildVtimezone('America/New_York', at('2026-10-22T01:30:00Z'));
	assert.equal(lines[0], 'BEGIN:VTIMEZONE');
	assert.equal(lines[1], 'TZID:America/New_York');
	assert.equal(lines[lines.length - 1], 'END:VTIMEZONE');
	assert.deepEqual(components(lines), [
		[
			'BEGIN:STANDARD',
			'DTSTART:20251102T020000',
			'TZOFFSETFROM:-0400',
			'TZOFFSETTO:-0500',
			'RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU',
			'END:STANDARD'
		],
		[
			'BEGIN:DAYLIGHT',
			'DTSTART:20260308T020000',
			'TZOFFSETFROM:-0500',
			'TZOFFSETTO:-0400',
			'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU',
			'END:DAYLIGHT'
		]
	]);
});

test('buildVtimezone uses a last-weekday rule where the date wanders across nth', () => {
	const lines = buildVtimezone('Europe/London', at('2026-06-01T00:00:00Z'));
	assert.ok(lines.includes('RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU'));
	assert.ok(lines.includes('RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU'));
});

test('buildVtimezone gives a zone with no DST one fixed observance', () => {
	assert.deepEqual(components(buildVtimezone('Asia/Kolkata', at('2026-10-21T00:00:00Z'))), [
		['BEGIN:STANDARD', 'DTSTART:19700101T000000', 'TZOFFSETFROM:+0530', 'TZOFFSETTO:+0530', 'END:STANDARD']
	]);
});

test('buildVtimezone writes out an irregular rule onset by onset instead of guessing', () => {
	// Israel moves to daylight time on the Friday before the last Sunday of
	// March, which is the fourth Friday until 2030 and the fifth that year.
	const lines = buildVtimezone('Asia/Jerusalem', at('2026-06-01T00:00:00Z'));
	const daylight = components(lines).filter((c) => c[0] === 'BEGIN:DAYLIGHT');
	assert.ok(daylight.every((c) => !c.some((l) => l.startsWith('RRULE'))));
	assert.ok(daylight.some((c) => c.includes('DTSTART:20300329T020000')));
});

test('buildVtimezone closes a rule the zone stopped observing', () => {
	// Brazil abolished DST in 2019; viewed from 2017, the yearly rule has to
	// end rather than run on.
	const lines = buildVtimezone('America/Sao_Paulo', at('2017-06-01T00:00:00Z'));
	const rules = lines.filter((l) => l.startsWith('RRULE:'));
	assert.ok(rules.length > 0);
	assert.ok(rules.every((r) => /;UNTIL=\d{8}T\d{6}Z$/.test(r)), rules.join('\n'));
});

test('buildVtimezone formats a half-hour offset', () => {
	const lines = buildVtimezone('Australia/Lord_Howe', at('2026-10-28T00:00:00Z'));
	assert.ok(lines.includes('TZOFFSETTO:+1030'));
	assert.ok(lines.includes('TZOFFSETTO:+1100'));
});
