import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildEventIcs,
	buildEventSeriesIcs,
	buildRrule,
	toIcsUtc,
	icsFilename
} from './event_ics';
import type { Event } from '../types';

const BASE = {
	uid: 'event-abc-2026-07-11T18:00:00Z@threkir.com',
	title: 'Saturday Long Run',
	startIso: '2026-07-11T18:00:00.000Z',
	nowMs: Date.parse('2026-07-01T00:00:00.000Z')
};

test('toIcsUtc formats an ISO instant as a UTC iCalendar date-time', () => {
	assert.equal(toIcsUtc('2026-07-11T18:05:09.000Z'), '20260711T180509Z');
});

test('toIcsUtc converts a non-UTC offset to the UTC instant', () => {
	assert.equal(toIcsUtc('2026-07-11T20:00:00+02:00'), '20260711T180000Z');
});

test('toIcsUtc returns null for an unparseable string', () => {
	assert.equal(toIcsUtc('not-a-date'), null);
});

test('buildEventIcs wraps one VEVENT in a VCALENDAR with CRLF endings', () => {
	const ics = buildEventIcs(BASE);
	assert.ok(ics);
	assert.ok(ics!.startsWith('BEGIN:VCALENDAR\r\n'));
	assert.ok(ics!.trimEnd().endsWith('END:VCALENDAR'));
	assert.equal((ics!.match(/BEGIN:VEVENT/g) ?? []).length, 1);
	assert.match(ics!, /\r\n/);
	assert.doesNotMatch(ics!, /[^\r]\n/); // every LF is preceded by CR
});

test('buildEventIcs emits required properties', () => {
	const ics = buildEventIcs(BASE)!;
	assert.match(ics, /VERSION:2\.0/);
	assert.match(ics, /UID:event-abc-2026-07-11T18:00:00Z@threkir\.com/);
	assert.match(ics, /DTSTART:20260711T180000Z/);
	assert.match(ics, /DTSTAMP:20260701T000000Z/);
	assert.match(ics, /SUMMARY:Saturday Long Run/);
});

test('buildEventIcs derives DTEND from durationMin', () => {
	const ics = buildEventIcs({ ...BASE, durationMin: 90 })!;
	assert.match(ics, /DTEND:20260711T193000Z/);
});

test('buildEventIcs omits DTEND when duration is absent or non-positive', () => {
	assert.doesNotMatch(buildEventIcs(BASE)!, /DTEND/);
	assert.doesNotMatch(buildEventIcs({ ...BASE, durationMin: 0 })!, /DTEND/);
	assert.doesNotMatch(buildEventIcs({ ...BASE, durationMin: null })!, /DTEND/);
});

test('buildEventIcs escapes TEXT special characters per RFC 5545', () => {
	const ics = buildEventIcs({
		...BASE,
		title: 'Run; then brunch, maybe',
		description: 'Line one\nLine two\\end'
	})!;
	assert.match(ics, /SUMMARY:Run\\; then brunch\\, maybe/);
	assert.match(ics, /DESCRIPTION:Line one\\nLine two\\\\end/);
});

test('buildEventIcs includes optional LOCATION and URL only when set', () => {
	const withExtras = buildEventIcs({
		...BASE,
		location: 'Central Park',
		url: 'https://threkir.com/share/event/abc'
	})!;
	assert.match(withExtras, /LOCATION:Central Park/);
	assert.match(withExtras, /URL:https:\/\/threkir\.com\/share\/event\/abc/);

	const bare = buildEventIcs(BASE)!;
	assert.doesNotMatch(bare, /LOCATION:/);
	assert.doesNotMatch(bare, /URL:/);
});

test('buildEventIcs folds a long line to <=75 octets with space continuations', () => {
	const longTitle = 'A'.repeat(200);
	const ics = buildEventIcs({ ...BASE, title: longTitle })!;
	for (const line of ics.split('\r\n')) {
		assert.ok(
			Buffer.byteLength(line, 'utf8') <= 75,
			`line exceeds 75 octets: ${line.length}`
		);
	}
	// A folded continuation line begins with a single space.
	assert.match(ics, /\r\n [A]/);
});

test('buildEventIcs returns null for an invalid start instant', () => {
	assert.equal(buildEventIcs({ ...BASE, startIso: 'garbage' }), null);
});

test('buildRrule states a weekly series with its BYDAY set', () => {
	assert.equal(buildRrule({ freq: 'weekly', byday: ['SA'] }), 'FREQ=WEEKLY;BYDAY=SA');
});

test('buildRrule normalises BYDAY into Monday-first order', () => {
	assert.equal(
		buildRrule({ freq: 'weekly', byday: ['TH', 'TU'] }),
		'FREQ=WEEKLY;BYDAY=TU,TH'
	);
});

test('buildRrule expresses biweekly as a two-week interval', () => {
	assert.equal(
		buildRrule({ freq: 'biweekly', byday: ['TU', 'TH'] }),
		'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH'
	);
});

test('buildRrule emits BYMONTHDAY for a monthly series', () => {
	assert.equal(
		buildRrule({ freq: 'monthly', monthDay: 15 }),
		'FREQ=MONTHLY;BYMONTHDAY=15'
	);
});

test('buildRrule refuses a monthly series past the 28th — BYMONTHDAY cannot clamp', () => {
	for (const monthDay of [29, 30, 31]) {
		assert.equal(buildRrule({ freq: 'monthly', monthDay }), null);
	}
	assert.equal(buildRrule({ freq: 'monthly', monthDay: 28 }), 'FREQ=MONTHLY;BYMONTHDAY=28');
	assert.equal(buildRrule({ freq: 'monthly', monthDay: null }), null);
	assert.equal(buildRrule({ freq: 'monthly', monthDay: 0 }), null);
});

test('buildRrule emits UNTIL as a UTC instant', () => {
	assert.equal(
		buildRrule({ freq: 'weekly', byday: ['SA'], untilIso: '2026-09-05T20:00:00+02:00' }),
		'FREQ=WEEKLY;UNTIL=20260905T180000Z;BYDAY=SA'
	);
});

test('buildRrule never emits UNTIL and COUNT together (RFC 5545 §3.3.10)', () => {
	const rule = buildRrule({
		freq: 'weekly',
		byday: ['SA'],
		untilIso: '2026-09-05T18:00:00Z',
		count: 4
	})!;
	assert.match(rule, /COUNT=4/);
	assert.doesNotMatch(rule, /UNTIL=/);
});

test('buildRrule fails closed on a bound it cannot state', () => {
	assert.equal(buildRrule({ freq: 'weekly', byday: ['SA'], count: 0 }), null);
	assert.equal(buildRrule({ freq: 'weekly', byday: ['SA'], count: 2.5 }), null);
	assert.equal(buildRrule({ freq: 'weekly', byday: ['SA'], untilIso: 'garbage' }), null);
	assert.equal(
		buildRrule({ freq: 'weekly', byday: ['XX' as unknown as 'MO'] }),
		null
	);
});

test('buildEventIcs emits RRULE and EXDATE for a series', () => {
	const ics = buildEventIcs({
		...BASE,
		recurrence: { freq: 'weekly', byday: ['SA'] },
		exdatesIso: ['2026-07-25T18:00:00.000Z', '2026-07-18T18:00:00.000Z']
	})!;
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=SA/);
	// Sorted + deduped so the same series always serialises identically.
	assert.match(ics, /EXDATE:20260718T180000Z,20260725T180000Z/);
	assert.equal((ics.match(/BEGIN:VEVENT/g) ?? []).length, 1);
});

test('buildEventIcs drops unparseable and duplicate EXDATE values', () => {
	const ics = buildEventIcs({
		...BASE,
		recurrence: { freq: 'weekly', byday: ['SA'] },
		exdatesIso: ['2026-07-18T18:00:00.000Z', '2026-07-18T18:00:00Z', 'nonsense']
	})!;
	assert.match(ics, /EXDATE:20260718T180000Z\r\n/);
});

test('buildEventIcs ignores EXDATE for a single occurrence', () => {
	const ics = buildEventIcs({ ...BASE, exdatesIso: ['2026-07-18T18:00:00.000Z'] })!;
	assert.doesNotMatch(ics, /EXDATE/);
	assert.doesNotMatch(ics, /RRULE/);
});

test('buildEventIcs fails the whole build when the recurrence is unrepresentable', () => {
	assert.equal(
		buildEventIcs({ ...BASE, recurrence: { freq: 'monthly', monthDay: 31 } }),
		null
	);
});

// A minimal RFC 5545 reader for the files this module writes: it unfolds the
// lines, resolves every TZID reading through the file's OWN VTIMEZONE (never
// Intl), and expands the RRULE the way a calendar would. Asserting against its
// output checks the file a member's calendar receives, not the strings that
// happen to build it.
interface Observance {
	onsetLocal: number;
	from: number;
	to: number;
	rule: Map<string, string> | null;
}

function unfold(ics: string): string[] {
	return ics.replace(/\r\n /g, '').split('\r\n').filter(Boolean);
}

function localMs(v: string): number {
	const m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$/.exec(v)!;
	return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
}

function offsetMs(v: string): number {
	const m = /^([+-])(\d{2})(\d{2})(\d{2})?$/.exec(v)!;
	return (m[1] === '-' ? -1 : 1) * ((+m[2] * 60 + +m[3]) * 60 + +(m[4] ?? 0)) * 1000;
}

function ruleParts(v: string): Map<string, string> {
	return new Map(v.split(';').map((kv) => kv.split('=') as [string, string]));
}

const WD = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];

function observanceOnsets(o: Observance, untilYear: number): number[] {
	if (!o.rule) return [o.onsetLocal];
	const month = +o.rule.get('BYMONTH')! - 1;
	const m = /^(-?\d)([A-Z]{2})$/.exec(o.rule.get('BYDAY')!)!;
	const nth = +m[1];
	const wd = WD.indexOf(m[2]);
	const until = o.rule.has('UNTIL') ? localMs(o.rule.get('UNTIL')!) : Infinity;
	const t = new Date(o.onsetLocal);
	const tod = o.onsetLocal - Date.UTC(t.getUTCFullYear(), t.getUTCMonth(), t.getUTCDate());
	const out: number[] = [];
	for (let y = t.getUTCFullYear(); y <= untilYear; y++) {
		const dim = new Date(Date.UTC(y, month + 1, 0)).getUTCDate();
		const days = [];
		for (let d = 1; d <= dim; d++) {
			if (new Date(Date.UTC(y, month, d)).getUTCDay() === wd) days.push(d);
		}
		const day = nth > 0 ? days[nth - 1] : days[days.length + nth];
		const onset = Date.UTC(y, month, day) + tod;
		if (onset - o.from > until) break;
		out.push(onset);
	}
	return out;
}

function parseIcs(ics: string) {
	const lines = unfold(ics);
	const observances: Observance[] = [];
	let cur: Partial<Observance> & { rule?: Map<string, string> | null } = {};
	let tzid: string | null = null;
	const props = new Map<string, { params: string; value: string }>();
	let inEvent = false;
	for (const line of lines) {
		if (line === 'BEGIN:STANDARD' || line === 'BEGIN:DAYLIGHT') cur = { rule: null };
		else if (line === 'END:STANDARD' || line === 'END:DAYLIGHT') observances.push(cur as Observance);
		else if (line === 'BEGIN:VEVENT') inEvent = true;
		else if (line === 'END:VEVENT') inEvent = false;
		const [head, ...rest] = line.split(':');
		const value = rest.join(':');
		const [name, ...params] = head.split(';');
		if (name === 'TZID') tzid = value;
		if (!inEvent && line !== 'BEGIN:VEVENT') {
			if (name === 'DTSTART') cur.onsetLocal = localMs(value);
			if (name === 'TZOFFSETFROM') cur.from = offsetMs(value);
			if (name === 'TZOFFSETTO') cur.to = offsetMs(value);
			if (name === 'RRULE') cur.rule = ruleParts(value);
		} else if (inEvent) {
			props.set(name, { params: params.join(';'), value });
		}
	}
	const onsets = observances
		.flatMap((o) => observanceOnsets(o, 2031).map((l) => ({ utc: l - o.from, from: o.from, to: o.to })))
		.sort((a, b) => a.utc - b.utc);
	const offsetAt = (utc: number) => {
		let off: number | null = null;
		for (const o of onsets) if (o.utc <= utc) off = o.to;
		return off;
	};
	// RFC 5545 §3.3.5: a reading two instants share takes the earlier; a
	// reading a gap skips takes the offset in force before the gap.
	const resolve = (reading: string) => {
		const l = localMs(reading);
		const valid = [...new Set(onsets.map((o) => o.to))]
			.map((off) => l - off)
			.filter((t) => offsetAt(t) === l - t)
			.sort((a, b) => a - b);
		if (valid.length) return valid[0];
		const gap = onsets.find((o) => l >= o.utc + o.from && l < o.utc + o.to)!;
		return l - gap.from;
	};
	return { tzid, props, resolve, observances };
}

/** The first `n` UTC instants a calendar would show for the file's VEVENT. */
function calendarInstants(ics: string, n: number): string[] {
	const { props, resolve, tzid } = parseIcs(ics);
	const dtstart = props.get('DTSTART')!;
	assert.equal(dtstart.params, `TZID=${tzid}`);
	const rule = ruleParts(props.get('RRULE')!.value);
	const count = rule.has('COUNT') ? +rule.get('COUNT')! : Infinity;
	const until = rule.has('UNTIL') ? localMs(rule.get('UNTIL')!) : Infinity;
	const exdates = new Set(
		(props.get('EXDATE')?.value.split(',') ?? []).map((v) => resolve(v))
	);
	if (props.has('EXDATE')) assert.equal(props.get('EXDATE')!.params, `TZID=${tzid}`);
	const start = localMs(dtstart.value);
	const startDay = new Date(start);
	const tod = start - Date.UTC(startDay.getUTCFullYear(), startDay.getUTCMonth(), startDay.getUTCDate());
	const p2 = (x: number) => String(x).padStart(2, '0');
	const reading = (dayMs: number) => {
		const d = new Date(dayMs + tod);
		return `${d.getUTCFullYear()}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCDate())}T${p2(d.getUTCHours())}${p2(d.getUTCMinutes())}${p2(d.getUTCSeconds())}`;
	};
	const candidates: string[] = [];
	if (rule.get('FREQ') === 'MONTHLY') {
		const md = +rule.get('BYMONTHDAY')!;
		for (let i = 0; candidates.length < n * 3 && i < 120; i++) {
			const y = startDay.getUTCFullYear();
			const m = startDay.getUTCMonth() + i;
			if (new Date(Date.UTC(y, m + 1, 0)).getUTCDate() < md) continue;
			candidates.push(reading(Date.UTC(y, m, md)));
		}
	} else {
		const interval = +(rule.get('INTERVAL') ?? 1);
		const byday = rule.get('BYDAY')!.split(',').map((c) => WD.indexOf(c));
		const startMidnight = Date.UTC(startDay.getUTCFullYear(), startDay.getUTCMonth(), startDay.getUTCDate());
		const monday = startMidnight - ((startDay.getUTCDay() + 6) % 7) * 86_400_000;
		for (let w = 0; candidates.length < n * 3 && w < 400; w += interval) {
			for (let k = 0; k < 7; k++) {
				const day = monday + (w * 7 + k) * 86_400_000;
				if (day < startMidnight || !byday.includes(new Date(day).getUTCDay())) continue;
				candidates.push(reading(day));
			}
		}
	}
	return candidates
		.slice(0, count)
		.map(resolve)
		.filter((t) => t <= until && !exdates.has(t))
		.slice(0, n)
		.map((t) => new Date(t).toISOString());
}

function ev(partial: Partial<Event>): Event {
	return {
		id: 'evt-1',
		title: 'Saturday Long Run',
		timezone: 'UTC',
		duration_min: 90,
		description: null,
		meet_label: null,
		recurrence_byday: null,
		recurrence_until: null,
		recurrence_count: null,
		...partial
	} as unknown as Event;
}

const SERIES_OPTS = { nowMs: Date.parse('2026-07-01T00:00:00.000Z') };

test('buildEventSeriesIcs returns null for a one-off event', () => {
	assert.equal(
		buildEventSeriesIcs(ev({ starts_at: '2026-07-11T18:00:00Z' }), SERIES_OPTS),
		null
	);
});

test('buildEventSeriesIcs anchors DTSTART on the series and carries the RRULE', () => {
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA'],
			meet_label: 'Clubhouse steps'
		}),
		{ ...SERIES_OPTS, url: 'https://threkir.com/share/event/evt-1' }
	)!;
	assert.match(ics, /DTSTART;TZID=UTC:20260711T180000\r\n/);
	assert.match(ics, /\r\nDURATION:PT90M\r\n/);
	assert.doesNotMatch(ics, /DTEND/);
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=SA/);
	assert.match(ics, /LOCATION:Clubhouse steps/);
	// A distinct UID from the per-occurrence export, so importing the series
	// does not overwrite (or get overwritten by) a single occurrence.
	assert.match(ics, /UID:event-evt-1-series@threkir\.com/);
});

test('buildEventSeriesIcs defines every TZID it cites with a VTIMEZONE before the VEVENT', () => {
	const ics = buildEventSeriesIcs(
		ev({
			timezone: 'America/New_York',
			starts_at: '2026-10-22T01:30:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['WE']
		}),
		{ ...SERIES_OPTS, cancelledIso: ['2026-11-05T02:30:00Z'] }
	)!;
	const vtz = ics.indexOf('BEGIN:VTIMEZONE\r\nTZID:America/New_York\r\n');
	assert.ok(vtz > 0 && vtz < ics.indexOf('BEGIN:VEVENT'));
	assert.match(ics, /DTSTART;TZID=America\/New_York:/);
	assert.match(ics, /EXDATE;TZID=America\/New_York:/);
	assert.equal(ics.match(/TZID=([^:;]+)/g)!.length, 2);
});

test('buildEventSeriesIcs writes a New York Wednesday 21:30 series on Wednesdays at 21:30 across DST', () => {
	// 21:30 EDT on Wed 21 Oct is already Thursday in UTC. The stored code is
	// the organiser's Wednesday, and after 1 Nov the same 21:30 is an hour
	// later in UTC — a UTC-clock file put these on Thursdays and then drifted.
	const ics = buildEventSeriesIcs(
		ev({
			timezone: 'America/New_York',
			starts_at: '2026-10-22T01:30:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['WE']
		}),
		{ ...SERIES_OPTS, cancelledIso: ['2026-11-05T02:30:00Z'] }
	)!;
	assert.match(ics, /DTSTART;TZID=America\/New_York:20261021T213000\r\n/);
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=WE\r\n/);
	assert.match(ics, /EXDATE;TZID=America\/New_York:20261104T213000\r\n/);
	assert.deepEqual(calendarInstants(ics, 4), [
		'2026-10-22T01:30:00.000Z',
		'2026-10-29T01:30:00.000Z',
		'2026-11-12T02:30:00.000Z',
		'2026-11-19T02:30:00.000Z'
	]);
});

test('buildEventSeriesIcs keeps a morning series on its local time across the southern-hemisphere change', () => {
	// Auckland leaves daylight time on Sun 5 Apr 2026: 06:00 NZDT is 17:00Z,
	// 06:00 NZST is 18:00Z.
	const ics = buildEventSeriesIcs(
		ev({
			timezone: 'Pacific/Auckland',
			starts_at: '2026-03-24T17:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['WE']
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /DTSTART;TZID=Pacific\/Auckland:20260325T060000\r\n/);
	assert.deepEqual(calendarInstants(ics, 3), [
		'2026-03-24T17:00:00.000Z',
		'2026-03-31T17:00:00.000Z',
		'2026-04-07T18:00:00.000Z'
	]);
});

test('buildEventSeriesIcs states a series on its local weekday in a zone with no DST', () => {
	// 05:00 IST on Wednesday is 23:30Z on Tuesday.
	const ics = buildEventSeriesIcs(
		ev({
			timezone: 'Asia/Kolkata',
			starts_at: '2026-10-20T23:30:00Z',
			recurrence_freq: 'weekly'
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /DTSTART;TZID=Asia\/Kolkata:20261021T050000\r\n/);
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=WE\r\n/);
	assert.match(ics, /TZOFFSETTO:\+0530/);
	assert.deepEqual(calendarInstants(ics, 2), [
		'2026-10-20T23:30:00.000Z',
		'2026-10-27T23:30:00.000Z'
	]);
});

test('buildEventSeriesIcs anchors on a DST-gap reading, which resolves forward', () => {
	// Friday 02:30 EST start, Sunday series: Sun 14 Mar 2027 has no 02:30, so
	// that occurrence is 03:30 EDT (07:30Z) and the next is 02:30 EDT.
	const ics = buildEventSeriesIcs(
		ev({
			timezone: 'America/New_York',
			starts_at: '2027-03-12T07:30:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SU']
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /DTSTART;TZID=America\/New_York:20270314T023000\r\n/);
	assert.deepEqual(calendarInstants(ics, 2), [
		'2027-03-14T07:30:00.000Z',
		'2027-03-21T06:30:00.000Z'
	]);
});

test('buildEventSeriesIcs takes the earlier instant of a repeated fall-back reading', () => {
	// 01:30 on Sun 1 Nov 2026 happens twice in New York; the series means the
	// first (05:30Z, EDT), so a start on it anchors there.
	const ics = buildEventSeriesIcs(
		ev({
			timezone: 'America/New_York',
			starts_at: '2026-11-01T05:30:00Z',
			recurrence_freq: 'weekly'
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /DTSTART;TZID=America\/New_York:20261101T013000\r\n/);
	assert.deepEqual(calendarInstants(ics, 2), [
		'2026-11-01T05:30:00.000Z',
		'2026-11-08T06:30:00.000Z'
	]);
});

test('buildEventSeriesIcs withholds a series that starts on the second pass of a fall-back hour', () => {
	// 06:30Z is the SECOND 01:30 on 1 Nov. The app keeps it as the first
	// occurrence, but DTSTART;TZID=…:20261101T013000 names the first pass
	// (05:30Z), so no file can state the series without moving that one.
	assert.equal(
		buildEventSeriesIcs(
			ev({
				timezone: 'America/New_York',
				starts_at: '2026-11-01T06:30:00Z',
				recurrence_freq: 'weekly'
			}),
			SERIES_OPTS
		),
		null
	);
});

test('buildEventSeriesIcs writes a legacy zoneless series in the viewer zone', () => {
	// No stored zone: the page expands it in the viewer's zone, so the file
	// does too — the same instant reads as a Wednesday evening in New York and
	// a Thursday morning in Berlin.
	const legacy = ev({
		timezone: null,
		starts_at: '2026-10-22T01:30:00Z',
		recurrence_freq: 'weekly'
	});
	const ny = buildEventSeriesIcs(legacy, { ...SERIES_OPTS, viewerZone: 'America/New_York' })!;
	assert.match(ny, /DTSTART;TZID=America\/New_York:20261021T213000\r\n/);
	assert.match(ny, /BYDAY=WE/);
	const berlin = buildEventSeriesIcs(legacy, { ...SERIES_OPTS, viewerZone: 'Europe/Berlin' })!;
	assert.match(berlin, /DTSTART;TZID=Europe\/Berlin:20261022T033000\r\n/);
	assert.match(berlin, /BYDAY=TH/);
});

test('buildEventSeriesIcs withholds a series whose zone the platform does not know', () => {
	assert.equal(
		buildEventSeriesIcs(
			ev({ timezone: 'Mars/Olympus', starts_at: '2026-07-11T18:00:00Z', recurrence_freq: 'weekly' }),
			SERIES_OPTS
		),
		null
	);
});

test('buildEventSeriesIcs starts at the first real occurrence, not starts_at', () => {
	// Tuesday start, Saturday series: RFC 5545 requires DTSTART to be a member
	// of the recurrence set, and the club page never shows the Tuesday.
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-07T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA']
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /DTSTART;TZID=UTC:20260711T180000/);
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=SA/);
});

test('buildEventSeriesIcs states the start weekday when no weekdays are stored', () => {
	const ics = buildEventSeriesIcs(
		ev({ starts_at: '2026-07-11T18:00:00Z', recurrence_freq: 'weekly' }),
		SERIES_OPTS
	)!;
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=SA/);
});

test('buildEventSeriesIcs keeps every weekday of a multi-day series', () => {
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-07T18:00:00Z',
			recurrence_freq: 'biweekly',
			recurrence_byday: ['TU', 'TH']
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH/);
});

test('buildEventSeriesIcs skips to the next even week when the start week has no stored weekday left', () => {
	// Saturday 11 Jul start, biweekly on Monday: the week of the start holds
	// no Monday after it and the next week is odd, so the series opens on 20 Jul.
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'biweekly',
			recurrence_byday: ['MO']
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /DTSTART;TZID=UTC:20260720T180000/);
});

test('buildEventSeriesIcs carries a count-bounded series through as COUNT', () => {
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA'],
			recurrence_count: 6
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /RRULE:FREQ=WEEKLY;COUNT=6;BYDAY=SA/);
});

test('buildEventSeriesIcs keeps UNTIL in UTC beside a TZID DTSTART (RFC 5545 §3.3.10)', () => {
	const ics = buildEventSeriesIcs(
		ev({
			timezone: 'America/New_York',
			starts_at: '2026-10-22T01:30:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['WE'],
			recurrence_until: '2026-11-12T03:00:00Z'
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /RRULE:FREQ=WEEKLY;UNTIL=20261112T030000Z;BYDAY=WE/);
	assert.deepEqual(calendarInstants(ics, 9), [
		'2026-10-22T01:30:00.000Z',
		'2026-10-29T01:30:00.000Z',
		'2026-11-05T02:30:00.000Z',
		'2026-11-12T02:30:00.000Z'
	]);
});

test('buildEventSeriesIcs resolves an until+count series to whichever binds first', () => {
	// Jul 11 / 18 / 25 / Aug 1 fit inside the until-bound, so the count of 10
	// never binds and the RRULE must stop at four rather than run on.
	const untilBinds = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA'],
			recurrence_until: '2026-08-01T23:59:00Z',
			recurrence_count: 10
		}),
		SERIES_OPTS
	)!;
	assert.match(untilBinds, /RRULE:FREQ=WEEKLY;COUNT=4;BYDAY=SA/);

	const countBinds = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA'],
			recurrence_until: '2026-12-31T23:59:00Z',
			recurrence_count: 2
		}),
		SERIES_OPTS
	)!;
	assert.match(countBinds, /RRULE:FREQ=WEEKLY;COUNT=2;BYDAY=SA/);
});

test('buildEventSeriesIcs subtracts cancelled occurrences via EXDATE', () => {
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA']
		}),
		{ ...SERIES_OPTS, cancelledIso: ['2026-07-18T18:00:00+00:00', '2026-07-18T18:00:00Z', 'nope'] }
	)!;
	assert.match(ics, /EXDATE;TZID=UTC:20260718T180000\r\n/);
	assert.deepEqual(calendarInstants(ics, 2), [
		'2026-07-11T18:00:00.000Z',
		'2026-07-25T18:00:00.000Z'
	]);
});

test('buildEventSeriesIcs withholds a monthly series it cannot state faithfully', () => {
	assert.equal(
		buildEventSeriesIcs(
			ev({ starts_at: '2026-03-31T09:00:00Z', recurrence_freq: 'monthly' }),
			SERIES_OPTS
		),
		null
	);
	const midMonth = buildEventSeriesIcs(
		ev({ starts_at: '2026-03-15T09:00:00Z', recurrence_freq: 'monthly' }),
		SERIES_OPTS
	)!;
	assert.match(midMonth, /RRULE:FREQ=MONTHLY;BYMONTHDAY=15/);
	assert.match(midMonth, /DTSTART;TZID=UTC:20260315T090000/);
});

test('buildEventSeriesIcs reads a monthly day-of-month in the event zone', () => {
	// 21:00 EDT on 30 Sep is 1 Oct in UTC: the 1st would be a UTC-clock
	// reading; the organiser's series is on the 30th, which no RRULE can clamp.
	assert.equal(
		buildEventSeriesIcs(
			ev({
				timezone: 'America/New_York',
				starts_at: '2026-10-01T01:00:00Z',
				recurrence_freq: 'monthly'
			}),
			SERIES_OPTS
		),
		null
	);
	const fifteenth = buildEventSeriesIcs(
		ev({
			timezone: 'America/New_York',
			starts_at: '2026-10-16T01:00:00Z',
			recurrence_freq: 'monthly'
		}),
		SERIES_OPTS
	)!;
	assert.match(fifteenth, /RRULE:FREQ=MONTHLY;BYMONTHDAY=15/);
	assert.deepEqual(calendarInstants(fifteenth, 2), [
		'2026-10-16T01:00:00.000Z',
		'2026-11-16T02:00:00.000Z'
	]);
});

test('buildEventSeriesIcs returns null for a series with no occurrences at all', () => {
	assert.equal(
		buildEventSeriesIcs(
			ev({
				starts_at: '2026-07-11T18:00:00Z',
				recurrence_freq: 'weekly',
				recurrence_byday: ['SA'],
				recurrence_until: '2026-07-01T00:00:00Z'
			}),
			SERIES_OPTS
		),
		null
	);
});

test('icsFilename slugs the title and always ends in .ics', () => {
	assert.equal(icsFilename('Saturday Long Run'), 'saturday-long-run.ics');
	assert.equal(icsFilename('  !!!  '), 'event.ics');
	assert.equal(icsFilename('Café 10K — Île'), 'caf-10k-le.ics');
});

// RFC 5545 §3.3.11: TSAFE-CHAR excludes every CONTROL character except HTAB,
// and there is no escape for one. A NUL or vertical tab in an event title (the
// column has no control-character CHECK) made strict parsers refuse the file.
test('buildEventIcs drops control characters TEXT cannot carry, keeping tab and line breaks', () => {
	const ics = buildEventIcs({
		...BASE,
		title: 'Tempo\u0000 run\u000B',
		description: 'Bring\twater\r\nand a \u001Blight\u007F',
		location: 'Gate\u0007 3'
	})!;
	assert.match(ics, /\r\nSUMMARY:Tempo run\r\n/);
	assert.match(ics, /\r\nDESCRIPTION:Bring\twater\\nand a light\r\n/);
	assert.match(ics, /\r\nLOCATION:Gate 3\r\n/);
	// Only CRLF line ends remain as raw control characters.
	assert.ok(!/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(ics));
	assert.ok(!/[^\r]\n/.test(ics), 'every LF is part of a CRLF line end');
});

test('buildEventIcs escapes a backslash before the escapes it introduces', () => {
	const bs = '\\';
	const ics = buildEventIcs({ ...BASE, title: `a${bs};b${bs}nc` })!;
	// A literal backslash-semicolon and backslash-n come out as an escaped
	// backslash followed by their own escapes, never as a bare escaped
	// semicolon or a line break.
	assert.ok(ics.includes(`SUMMARY:a${bs}${bs}${bs};b${bs}${bs}nc\r\n`));
});
