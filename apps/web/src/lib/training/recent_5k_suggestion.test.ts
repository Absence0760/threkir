import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	RECENT_5K_WINDOW_DAYS,
	isPlausibleRecent5k,
	pickRecent5k,
	type Recent5kCandidate,
} from './recent_5k_suggestion';

const NOW = Date.parse('2026-10-18T12:00:00Z');

function run(id: string, startedAt: string, fastest5kS: number | null, extra: Partial<Recent5kCandidate> = {}): Recent5kCandidate {
	return { id, startedAt, fastest5kS, activityType: 'run', isDnf: false, ...extra };
}

test('no runs suggests nothing', () => {
	assert.equal(pickRecent5k([], NOW, null), null);
});

test('the fastest 5K in the window is the one suggested', () => {
	const s = pickRecent5k(
		[run('a', '2026-10-10T08:00:00Z', 1500), run('b', '2026-10-03T08:00:00Z', 1450), run('c', '2026-09-20T08:00:00Z', 1480)],
		NOW,
		null,
	);
	assert.deepEqual(s, { runId: 'b', startedAt: '2026-10-03T08:00:00Z', seconds: 1450 });
});

test('a tie goes to the more recent run', () => {
	const s = pickRecent5k([run('old', '2026-09-01T08:00:00Z', 1450), run('new', '2026-10-01T08:00:00Z', 1450)], NOW, null);
	assert.equal(s?.runId, 'new');
});

test('the window is 56 days, inclusive of its first instant', () => {
	assert.equal(RECENT_5K_WINDOW_DAYS, 56);
	const edge = new Date(NOW - 56 * 86_400_000).toISOString();
	const outside = new Date(NOW - 56 * 86_400_000 - 1000).toISOString();
	assert.equal(pickRecent5k([run('edge', edge, 1450)], NOW, null)?.runId, 'edge');
	assert.equal(pickRecent5k([run('out', outside, 1300)], NOW, null), null);
});

test('a run dated in the future is not offered', () => {
	assert.equal(pickRecent5k([run('f', '2026-10-19T08:00:00Z', 1450)], NOW, null), null);
});

test('only runs count, and a run with no activity type is a run', () => {
	const s = pickRecent5k(
		[
			run('walk', '2026-10-10T08:00:00Z', 1300, { activityType: 'walk' }),
			run('ride', '2026-10-11T08:00:00Z', 800, { activityType: 'cycle' }),
			run('stroller', '2026-10-12T08:00:00Z', 1350, { activityType: 'stroller' }),
			run('legacy', '2026-10-09T08:00:00Z', 1500, { activityType: null }),
		],
		NOW,
		null,
	);
	assert.equal(s?.runId, 'legacy');
});

test('a DNF is not offered', () => {
	const s = pickRecent5k(
		[run('dnf', '2026-10-10T08:00:00Z', 1300, { isDnf: true }), run('ok', '2026-10-09T08:00:00Z', 1500, { isDnf: null })],
		NOW,
		null,
	);
	assert.equal(s?.runId, 'ok');
});

test('a time the wizard cannot take is not offered', () => {
	const s = pickRecent5k(
		[
			run('none', '2026-10-10T08:00:00Z', null),
			run('tooFast', '2026-10-10T08:00:00Z', 600),
			run('tooSlow', '2026-10-10T08:00:00Z', 3600),
			run('fraction', '2026-10-10T08:00:00Z', 1400.5),
		],
		NOW,
		null,
	);
	assert.equal(s, null);
});

test('after a dismissal only a run started later brings it back', () => {
	const runs = [run('seen', '2026-10-01T08:00:00Z', 1400), run('between', '2026-10-05T08:00:00Z', 1500)];
	assert.equal(pickRecent5k(runs, NOW, '2026-10-06T00:00:00Z'), null);
	assert.equal(pickRecent5k(runs, NOW, '2026-10-05T08:00:00Z'), null);
	const later = [...runs, run('newer', '2026-10-12T08:00:00Z', 1550)];
	assert.equal(pickRecent5k(later, NOW, '2026-10-06T00:00:00Z')?.runId, 'newer');
});

test('an unreadable dismissal stamp is treated as no dismissal', () => {
	const s = pickRecent5k([run('a', '2026-10-01T08:00:00Z', 1450)], NOW, 'not a date');
	assert.equal(s?.runId, 'a');
});

test('a run whose start cannot be read is skipped', () => {
	const s = pickRecent5k([run('bad', 'yesterday', 1300), run('good', '2026-10-01T08:00:00Z', 1450)], NOW, null);
	assert.equal(s?.runId, 'good');
});

test('isPlausibleRecent5k takes 12:00 to 59:59 in whole seconds', () => {
	assert.equal(isPlausibleRecent5k(719), false);
	assert.equal(isPlausibleRecent5k(720), true);
	assert.equal(isPlausibleRecent5k(3599), true);
	assert.equal(isPlausibleRecent5k(3600), false);
	assert.equal(isPlausibleRecent5k(1450.5), false);
	assert.equal(isPlausibleRecent5k(null), false);
});
