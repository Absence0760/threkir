import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	expandInstances,
	nextInstanceAfter,
	describeRecurrence,
} from './recurrence';
import type { Event } from '../types';

// Build a partial Event with just enough fields for recurrence math.
// Casts the rest to `unknown as Event` — the recurrence helpers only
// touch `starts_at`, `recurrence_freq`, `recurrence_byday`,
// `recurrence_until`, and `recurrence_count`.
function ev(partial: Partial<Event>): Event {
	return partial as unknown as Event;
}

test('expandInstances — non-recurring event returns its single instance when in window', () => {
	const e = ev({ starts_at: '2026-04-10T08:00:00Z' });
	const inWindow = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-04-30T23:59:59Z'),
	);
	assert.equal(inWindow.length, 1);

	const outOfWindow = expandInstances(
		e,
		new Date('2026-05-01T00:00:00Z'),
		new Date('2026-05-31T23:59:59Z'),
	);
	assert.equal(outOfWindow.length, 0);
});

test('expandInstances — weekly event produces multiple instances in a month', () => {
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-04-30T23:59:59Z'),
	);
	// Apr 1 (Wed), Apr 8, Apr 15, Apr 22, Apr 29 → 5 instances. The Apr 1
	// instance used to slip on UTC hosts because the loop compared a
	// midnight cursor against starts_at's 08:00 time-of-day — the fix
	// separates calendar-day and stamped-time comparisons so the first-
	// week instance is no longer silently dropped.
	assert.equal(out.length, 5);
});

test('expandInstances — weekly emits the starts_at week even when start has a non-midnight time-of-day', () => {
	// Regression: this used to drop the Tuesday instance because the
	// midnight cursor for the start day was < starts_at (Tuesday 19:00),
	// so the entire first week's matching day was filtered out before
	// time-of-day was stamped.
	const e = ev({
		starts_at: '2026-04-07T19:00:00Z', // Tue
		recurrence_freq: 'weekly',
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-04-30T23:59:59Z'),
	);
	const firstDay = out[0]?.toISOString().slice(0, 10);
	assert.equal(firstDay, '2026-04-07', `first instance should be Apr 7, got ${firstDay}`);
});

test('expandInstances — weekly emits the starts_at week when starts_at carries milliseconds', () => {
	// Regression: `stamp()` rebuilds the instant with a zero millisecond, so a
	// starts_at of ...:18.132Z produced a first candidate of ...:18.000 that
	// lost `stamped < start` — the series' own first occurrence vanished from
	// the picker, the listings and every RSVP key.
	const withMs = ev({
		starts_at: '2026-08-23T02:49:18.132Z', // Sun
		recurrence_freq: 'weekly',
		timezone: 'UTC',
	});
	const from = new Date('2026-08-17T00:00:00Z');
	const to = new Date('2026-09-30T23:59:59Z');
	const out = expandInstances(withMs, from, to);
	assert.equal(out[0]?.toISOString(), '2026-08-23T02:49:18.000Z');

	const withoutMs = ev({
		starts_at: '2026-08-23T02:49:18.000Z',
		recurrence_freq: 'weekly',
		timezone: 'UTC',
	});
	assert.deepEqual(
		out.map((d) => d.toISOString()),
		expandInstances(withoutMs, from, to).map((d) => d.toISOString()),
	);
});

test('expandInstances — biweekly produces fewer instances than weekly in the same window', () => {
	const start = '2026-04-01T08:00:00Z';
	const weekly = ev({ starts_at: start, recurrence_freq: 'weekly' });
	const biweekly = ev({ starts_at: start, recurrence_freq: 'biweekly' });
	const from = new Date('2026-04-01T00:00:00Z');
	const to = new Date('2026-04-30T23:59:59Z');
	const w = expandInstances(weekly, from, to);
	const b = expandInstances(biweekly, from, to);
	assert.ok(b.length < w.length, `biweekly ${b.length} should be fewer than weekly ${w.length}`);
});

test('expandInstances — biweekly with a weekend-crossing byday anchors on Monday', () => {
	// Twin-parity contract with apps/mobile_android/lib/recurrence.dart: the week
	// is anchored on Monday, so a biweekly [SA, SU] event starting on a Saturday
	// fires Sat+Sun on the start week, skips a week, then Sat+Sun again. A Sunday
	// anchor (the old Dart behaviour) split the Sunday into the next week and
	// produced a different set of dates. CI runs in UTC; the start time is given
	// in Z so getDay() reads Saturday.
	const e = ev({
		starts_at: '2026-05-02T09:00:00Z', // Sat
		recurrence_freq: 'biweekly',
		recurrence_byday: ['SA', 'SU'],
	});
	const out = expandInstances(
		e,
		new Date('2026-05-01T00:00:00Z'),
		new Date('2026-05-31T23:59:59Z'),
	);
	const dates = out.map((d) => d.toISOString().slice(0, 10));
	assert.deepEqual(dates, [
		'2026-05-02',
		'2026-05-03',
		'2026-05-16',
		'2026-05-17',
		'2026-05-30',
		'2026-05-31',
	]);
});

test('expandInstances — recurrence_count caps the number of instances', () => {
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_count: 3,
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-12-31T23:59:59Z'),
	);
	assert.equal(out.length, 3);
});

test('expandInstances — a recurrence_count of 0 yields no instance, weekly as monthly', () => {
	// The column admits 0 (20270705000004). The monthly loop and the
	// database's is_event_occurrence both read it as no occurrence; the weekly
	// loop counted after emitting and so offered the first one, an instant the
	// photo trigger then refused.
	for (const recurrence_freq of ['weekly', 'biweekly', 'monthly'] as const) {
		const e = ev({
			starts_at: '2026-04-01T08:00:00Z',
			recurrence_freq,
			recurrence_count: 0,
			timezone: 'UTC',
		});
		const out = expandInstances(
			e,
			new Date('2026-04-01T00:00:00Z'),
			new Date('2026-12-31T23:59:59Z'),
		);
		assert.deepEqual(out, [], recurrence_freq);
	}
});

test('expandInstances — count-limited weekly is exhausted before a later window (no phantom occurrences)', () => {
	// Regression: recurrence_count caps TOTAL occurrences, not in-window ones. A
	// 3-occurrence weekly series (Apr 1/8/15) viewed in a LATER window must
	// return nothing — the series ended before the window opened. The old code
	// counted only in-window pushes, so it walked past the real end and emitted
	// three phantom April-29-onward instances.
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z', // Wed
		recurrence_freq: 'weekly',
		recurrence_count: 3,
	});
	const out = expandInstances(
		e,
		new Date('2026-05-01T00:00:00Z'),
		new Date('2026-12-31T23:59:59Z'),
	);
	assert.equal(out.length, 0);
});

test('expandInstances — count-limited weekly partially overlapping a window counts pre-window occurrences', () => {
	// Window opens after the 1st occurrence (Apr 1) but before the series end.
	// Occurrences are Apr 1/8/15 (count 3); a window of [Apr 8, …] must yield
	// only Apr 8 + Apr 15 — the Apr 1 occurrence still consumes one of the three.
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_count: 3,
	});
	const out = expandInstances(
		e,
		new Date('2026-04-08T00:00:00Z'),
		new Date('2026-12-31T23:59:59Z'),
	);
	const dates = out.map((d) => d.toISOString().slice(0, 10));
	assert.deepEqual(dates, ['2026-04-08', '2026-04-15']);
});

test('expandInstances — count-limited monthly is exhausted before a later window (no phantom occurrences)', () => {
	const e = ev({
		starts_at: '2026-01-05T09:00:00Z',
		recurrence_freq: 'monthly',
		recurrence_count: 3, // Jan 5, Feb 5, Mar 5 — series ends after March
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-12-31T23:59:59Z'),
	);
	assert.equal(out.length, 0);
});

test('nextInstanceAfter — exhausted count-limited series returns null, not a phantom', () => {
	// nextInstanceAfter passes from = now; for a series that already ran out of
	// its count it must report no upcoming instance (data.ts scopes RSVP keys to
	// this — a phantom would arm a dead series).
	const e = ev({
		starts_at: '2026-01-07T09:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_count: 3, // Jan 7/14/21
	});
	const next = nextInstanceAfter(e, new Date('2026-02-01T00:00:00Z'));
	assert.equal(next, null);
});

test('expandInstances — recurrence_until stops the expansion', () => {
	const until = '2026-04-22T08:00:00Z';
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_until: until,
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-12-31T23:59:59Z'),
	);
	assert.ok(out.length > 0);
	const untilMs = new Date(until).getTime();
	for (const d of out) {
		assert.ok(d.getTime() <= untilMs, `instance ${d.toISOString()} after until`);
	}
});

test('expandInstances — monthly produces one instance per month in window', () => {
	const e = ev({
		starts_at: '2026-04-05T10:00:00Z',
		recurrence_freq: 'monthly',
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-06-30T23:59:59Z'),
	);
	assert.equal(out.length, 3);
});

test('expandInstances — day-31 monthly clamps to month-end (no overflow)', () => {
	// Jan-31 monthly must land on Feb-28 (2026 is not a leap year), Mar-31,
	// Apr-30 — never roll into the following month. A naive setMonth(+1) on a
	// Jan-31 cursor overflows to March 3. Local-time start (no Z) so the
	// day-of-month is unambiguous in the UTC CI runner.
	const e = ev({
		starts_at: '2026-01-31T09:00:00',
		recurrence_freq: 'monthly',
	});
	const out = expandInstances(
		e,
		new Date('2026-01-01T00:00:00'),
		new Date('2026-04-30T23:59:59'),
	);
	const dates = out.map((d) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`);
	assert.deepEqual(dates, ['2026-1-31', '2026-2-28', '2026-3-31', '2026-4-30']);
	// Each instance re-anchors on the original day (March is back to 31), so a
	// February clamp doesn't permanently shrink the day-of-month.
	for (const d of out) {
		assert.equal(d.getHours(), 9);
		assert.equal(d.getMinutes(), 0);
	}
});

test('expandInstances — day-31 monthly hits Feb-29 in a leap year', () => {
	const e = ev({
		starts_at: '2024-01-31T08:00:00',
		recurrence_freq: 'monthly',
	});
	const out = expandInstances(
		e,
		new Date('2024-02-01T00:00:00'),
		new Date('2024-02-29T23:59:59'),
	);
	assert.equal(out.length, 1);
	assert.equal(out[0].getMonth(), 1); // February
	assert.equal(out[0].getDate(), 29);
});

test('expandInstances — instances do not precede the original starts_at', () => {
	const startsAt = '2026-04-08T09:00:00Z';
	const e = ev({ starts_at: startsAt, recurrence_freq: 'weekly' });
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-04-30T23:59:59Z'),
	);
	const startMs = new Date(startsAt).getTime();
	for (const d of out) {
		assert.ok(d.getTime() >= startMs, `instance ${d.toISOString()} precedes starts_at`);
	}
});

test('expandInstances — monthly with recurrence_count caps instances', () => {
	const e = ev({
		starts_at: '2026-01-01T09:00:00Z',
		recurrence_freq: 'monthly',
		recurrence_count: 4,
	});
	const out = expandInstances(
		e,
		new Date('2026-01-01T00:00:00Z'),
		new Date('2026-12-31T23:59:59Z'),
	);
	assert.equal(out.length, 4);
});

test('nextInstanceAfter — returns the next instance after a cutoff', () => {
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
	});
	const next = nextInstanceAfter(e, new Date('2026-04-10T00:00:00Z'));
	assert.ok(next != null);
	// The first weekly instance after Apr 10 should be Apr 15 (Wed).
	assert.equal(next!.toISOString().slice(0, 10), '2026-04-15');
});

test('nextInstanceAfter — returns null past recurrence_until', () => {
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_until: '2026-04-30T23:59:59Z',
	});
	const next = nextInstanceAfter(e, new Date('2026-05-01T00:00:00Z'));
	assert.equal(next, null);
});

test('nextInstanceAfter — a years-old weekly series still reports its next occurrence', () => {
	// A club's long-running Monday-night run. The scan budget used to be derived
	// from `max` (1 here), so the walk gave up 49 days after the series began and
	// the caller fell back to showing starts_at — years in the past — as the next
	// instance, scoping the going-count to a stale instance key.
	const e = ev({
		starts_at: '2024-01-01T09:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_byday: ['MO'],
		timezone: 'UTC',
	});
	const next = nextInstanceAfter(e, new Date('2026-08-09T00:00:00Z'));
	assert.equal(next?.toISOString(), '2026-08-10T09:00:00.000Z');
});

test('nextInstanceAfter — a years-old monthly series still reports its next occurrence', () => {
	const e = ev({
		starts_at: '2024-01-15T09:00:00Z',
		recurrence_freq: 'monthly',
		timezone: 'UTC',
	});
	const next = nextInstanceAfter(e, new Date('2026-08-09T00:00:00Z'));
	assert.equal(next?.toISOString(), '2026-08-15T09:00:00.000Z');
});

test('expandInstances — a small max does not shorten how far the scan reaches', () => {
	// `max` caps the RESULT count, never the distance walked: a four-instance
	// preview of a window two years past starts_at must still find them.
	const e = ev({
		starts_at: '2024-01-01T09:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_byday: ['MO'],
		timezone: 'UTC',
	});
	const out = expandInstances(
		e,
		new Date('2026-08-01T00:00:00Z'),
		new Date('2026-08-31T00:00:00Z'),
		4,
	);
	assert.deepEqual(
		out.map((d) => d.toISOString()),
		[
			'2026-08-03T09:00:00.000Z',
			'2026-08-10T09:00:00.000Z',
			'2026-08-17T09:00:00.000Z',
			'2026-08-24T09:00:00.000Z',
		],
	);
});

function isoList(e: Event, from: string, to: string): string[] {
	return expandInstances(e, new Date(from), new Date(to)).map((d) => d.toISOString());
}

test('expandInstances — a timezoned weekly series keeps its local time of day across a DST change', () => {
	// The capacity key + race-arm key of an occurrence must be one instant for
	// every viewer, and it must be the organiser's wall-clock: 07:00 in New York
	// on both sides of the 1 November fall-back, so the UTC hour moves.
	const e = ev({
		starts_at: '2026-10-21T11:00:00Z', // Wed 07:00 EDT
		timezone: 'America/New_York',
		recurrence_freq: 'weekly'
	});
	assert.deepEqual(isoList(e, '2026-10-15T00:00:00Z', '2026-11-12T00:00:00Z'), [
		'2026-10-21T11:00:00.000Z',
		'2026-10-28T11:00:00.000Z',
		'2026-11-04T12:00:00.000Z',
		'2026-11-11T12:00:00.000Z'
	]);
});

test('expandInstances — two cross-TZ viewers compute the SAME instance_start (timezoned event)', () => {
	// Re-running the same input stands in for two viewers; the absolute-time
	// assertion is what guards the cross-process case (the suite runs under
	// several TZ values, and the shared vectors replay every viewer zone).
	const e = ev({
		starts_at: '2026-05-02T08:00:00Z', // Sat 09:00 BST
		timezone: 'Europe/London',
		recurrence_freq: 'biweekly',
		recurrence_byday: ['SA']
	});
	const viewerA = isoList(e, '2026-05-01T00:00:00Z', '2026-05-31T23:59:59Z');
	const viewerB = isoList(e, '2026-05-01T00:00:00Z', '2026-05-31T23:59:59Z');
	assert.deepEqual(viewerA, viewerB);
	assert.deepEqual(viewerA, [
		'2026-05-02T08:00:00.000Z',
		'2026-05-16T08:00:00.000Z',
		'2026-05-30T08:00:00.000Z'
	]);
});

test('expandInstances — a timezoned monthly series keeps its local day-of-month and time', () => {
	// 22:00 UTC on 31 January is 09:00 on 1 February in Sydney, so the series
	// is "the 1st at 09:00": the UTC hour moves when Sydney leaves DST on 5 April.
	const e = ev({
		starts_at: '2026-01-31T22:00:00Z',
		timezone: 'Australia/Sydney',
		recurrence_freq: 'monthly'
	});
	assert.deepEqual(isoList(e, '2026-01-01T00:00:00Z', '2026-04-30T23:59:59Z'), [
		'2026-01-31T22:00:00.000Z',
		'2026-02-28T22:00:00.000Z',
		'2026-03-31T22:00:00.000Z',
		'2026-04-30T23:00:00.000Z'
	]);
});

test('expandInstances — a weekday chip is a local weekday, so an evening series west of UTC keeps its day', () => {
	// Wednesday 21:30 in New York is Thursday in UTC. Read on the UTC clock the
	// WE chip moved the series to Tuesday evenings and dropped its first night.
	const e = ev({
		starts_at: '2026-10-22T01:30:00Z',
		timezone: 'America/New_York',
		recurrence_freq: 'weekly',
		recurrence_byday: ['WE']
	});
	assert.deepEqual(isoList(e, '2026-10-15T00:00:00Z', '2026-11-13T00:00:00Z'), [
		'2026-10-22T01:30:00.000Z',
		'2026-10-29T01:30:00.000Z',
		'2026-11-05T02:30:00.000Z',
		'2026-11-12T02:30:00.000Z'
	]);
});

test('expandInstances — a wall-clock inside the spring-forward gap moves forward by the gap', () => {
	// 02:30 does not exist in New York on 14 March 2027; it becomes 03:30 EDT.
	const e = ev({
		starts_at: '2027-03-07T07:30:00Z', // Sun 02:30 EST
		timezone: 'America/New_York',
		recurrence_freq: 'weekly'
	});
	assert.deepEqual(isoList(e, '2027-03-01T00:00:00Z', '2027-03-22T00:00:00Z'), [
		'2027-03-07T07:30:00.000Z',
		'2027-03-14T07:30:00.000Z',
		'2027-03-21T06:30:00.000Z'
	]);
});

test('expandInstances — a wall-clock inside the fall-back overlap takes the earlier instant', () => {
	// 01:30 happens twice in New York on 1 November 2026; the occurrence is the
	// first, 01:30 EDT, as RFC 5545 resolves it.
	const e = ev({
		starts_at: '2026-10-25T05:30:00Z', // Sun 01:30 EDT
		timezone: 'America/New_York',
		recurrence_freq: 'weekly'
	});
	assert.deepEqual(isoList(e, '2026-10-20T00:00:00Z', '2026-11-09T00:00:00Z'), [
		'2026-10-25T05:30:00.000Z',
		'2026-11-01T05:30:00.000Z',
		'2026-11-08T06:30:00.000Z'
	]);
});

test('expandInstances — a series started in the second pass of an overlap hour keeps starts_at first', () => {
	const e = ev({
		starts_at: '2026-11-01T06:30:00Z', // Sun 01:30 EST, the later of the two
		timezone: 'America/New_York',
		recurrence_freq: 'weekly'
	});
	assert.deepEqual(isoList(e, '2026-10-20T00:00:00Z', '2026-11-09T00:00:00Z'), [
		'2026-11-01T06:30:00.000Z',
		'2026-11-08T06:30:00.000Z'
	]);
});

test('expandInstances — a zone the runtime cannot resolve expands in UTC', () => {
	const e = ev({
		starts_at: '2026-04-07T13:00:00Z',
		timezone: 'Not/AZone',
		recurrence_freq: 'weekly'
	});
	assert.deepEqual(isoList(e, '2026-04-01T00:00:00Z', '2026-04-15T00:00:00Z'), [
		'2026-04-07T13:00:00.000Z',
		'2026-04-14T13:00:00.000Z'
	]);
});

test('expandInstances — legacy event with no timezone keeps viewer-local behaviour', () => {
	// A row predating 20270111_001 has no timezone; expansion must fall back to
	// the original local-zone stamping so its already-placed RSVPs don't shift.
	const e = ev({
		starts_at: '2026-04-07T13:00:00Z',
		recurrence_freq: 'weekly',
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-04-30T23:59:59Z'),
	);
	assert.equal(out.length, 4);
});

test('describeRecurrence — null freq is "One-off event"', () => {
	assert.equal(describeRecurrence(null, []), 'One-off event');
	assert.equal(describeRecurrence(null, null), 'One-off event');
});

test('describeRecurrence — monthly is "Repeats monthly"', () => {
	assert.equal(describeRecurrence('monthly', null), 'Repeats monthly');
	assert.equal(describeRecurrence('monthly', ['MO']), 'Repeats monthly');
});

test('describeRecurrence — weekly with byday lists days in ISO order', () => {
	// Even when input order is shuffled, output order is MO,TU,...,SU.
	assert.equal(describeRecurrence('weekly', ['WE', 'MO']), 'Every week · Mon, Wed');
});

test('describeRecurrence — biweekly without byday is bare', () => {
	assert.equal(describeRecurrence('biweekly', null), 'Every other week');
	assert.equal(describeRecurrence('biweekly', []), 'Every other week');
});
