import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { SessionStartMode } from './course_gates';
import {
	effectiveRaceStatus,
	localFromStartOffset,
	raceCountdownS,
	raceStartInstant,
	selfTimedAttemptState,
	selfTimedBoard,
	startOffsetFromLocal,
	validateStartSettings,
	voiceCountdownCue,
	type RaceStatus
} from './race_start_modes';

// The TS reader of fixtures/race_start_modes_cases.json, the case table the
// race_start_modes pair shares with mobile's race_start_modes_test.dart.
const here = dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(
	readFileSync(join(here, '../../../../../fixtures/race_start_modes_cases.json'), 'utf8')
);
const serverNow = Date.parse(fixture.serverNow);

test('effectiveRaceStatus matches the fixture', () => {
	for (const c of fixture.effectiveStatus) {
		const got = effectiveRaceStatus(
			{
				status: c.status as RaceStatus,
				startMode: c.mode as SessionStartMode,
				scheduledStartAt: c.scheduledStartAt,
				windowOpensAt: c.windowOpensAt,
				windowClosesAt: c.windowClosesAt
			},
			serverNow
		);
		assert.equal(got, c.expected, c.note);
	}
});

test('raceCountdownS matches the fixture', () => {
	for (const c of fixture.countdown) {
		assert.equal(raceCountdownS(c.target, Date.parse(c.deviceNowMs), c.serverOffsetMs), c.expected, c.note);
	}
});

test('voiceCountdownCue matches the fixture', () => {
	for (const c of fixture.voiceCue) {
		assert.equal(voiceCountdownCue(c.previous, c.current), c.expected, c.note ?? `${c.previous} -> ${c.current}`);
	}
});

test('start offsets round-trip through the wall time', () => {
	for (const c of fixture.offsets) {
		assert.equal(
			startOffsetFromLocal(c.startMinuteOfDay, { dayOffset: c.dayOffset, minuteOfDay: c.minuteOfDay }),
			c.offsetS,
			c.note
		);
		assert.deepEqual(localFromStartOffset(c.startMinuteOfDay, c.offsetS), {
			dayOffset: c.dayOffset,
			minuteOfDay: c.minuteOfDay
		});
	}
});

test('selfTimedAttemptState matches the fixture', () => {
	for (const c of fixture.attemptState) {
		assert.equal(selfTimedAttemptState(c), c.expected, JSON.stringify(c));
	}
});

test('validateStartSettings matches the fixture', () => {
	for (const c of fixture.validate) {
		assert.deepEqual(
			validateStartSettings({
				mode: c.mode,
				scheduledOffsetS: c.scheduledOffsetS,
				windowOpenOffsetS: c.windowOpenOffsetS,
				windowLengthS: c.windowLengthS
			}),
			c.expected,
			JSON.stringify(c)
		);
	}
});

test('raceStartInstant is the scheduled GO or the window opening, and none for Host GO', () => {
	const base = { status: 'armed' as const, windowClosesAt: null };
	assert.equal(
		raceStartInstant({ ...base, startMode: 'scheduled', scheduledStartAt: 'a', windowOpensAt: null }),
		'a'
	);
	assert.equal(
		raceStartInstant({ ...base, startMode: 'self_timed', scheduledStartAt: null, windowOpensAt: 'b' }),
		'b'
	);
	assert.equal(raceStartInstant({ ...base, startMode: 'host_go', scheduledStartAt: 'a', windowOpensAt: 'b' }), null);
});

test('selfTimedBoard puts start-line times first, longest on course first, then the untimed block', () => {
	const board = selfTimedBoard([
		{ userId: 'watch', sinceStartLineS: null },
		{ userId: 'short', sinceStartLineS: 60 },
		{ userId: 'long', sinceStartLineS: 900 },
		{ userId: 'old-app', sinceStartLineS: null },
		{ userId: 'tie', sinceStartLineS: 60 }
	]);
	assert.deepEqual(
		board.timed.map((p) => p.userId),
		['long', 'short', 'tie']
	);
	assert.deepEqual(
		board.untimed.map((p) => p.userId),
		['watch', 'old-app']
	);
});
