// Source guard: every "this week" window on web comes from ONE helper,
// `weekStartLocal` in training/goals.ts.
//
// The offset arithmetic used to be re-typed in seven places — the dashboard
// tile, the weekly chart, the week strip, the week lead, the trend deltas, the
// consistency card and the period summary. Each copy was correct on its own;
// what broke was that a copy could be handed the wrong preference (the chart
// was bucketed before `week_start_day` loaded) or none at all (the period
// summary was Monday-only), and nothing tied the copies together. A
// Sunday-first runner saw 22.50 km "this week" on the tile and 7.50 km on the
// chart beside it.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

const SRC = resolve(import.meta.dirname, '../..');
const HELPER = 'lib/training/goals.ts';

/// Monday-first offsets that are deliberately NOT a preference-honouring
/// week window. A new entry needs a reason a reviewer can check.
const MONDAY_ONLY_ALLOWED: Record<string, string> = {
	'lib/runs/recap.ts': 'ISO-8601 weeks for the year recap, documented at the call site',
	'lib/social/recurrence.ts': 'weekly-recurrence anchor, in lockstep with recurrence.dart',
	'lib/components/DateRangePicker.svelte': 'calendar-grid column layout, not a week window',
};

function sources(dir: string): string[] {
	const out: string[] = [];
	for (const name of readdirSync(dir)) {
		const path = join(dir, name);
		if (statSync(path).isDirectory()) out.push(...sources(path));
		else if (/\.(ts|svelte)$/.test(name) && !name.endsWith('.test.ts')) out.push(path);
	}
	return out;
}

const FILES = sources(SRC).map((p) => ({
	rel: relative(SRC, p).split('\\').join('/'),
	text: readFileSync(p, 'utf8'),
}));

test('only weekStartLocal turns week_start_day into a day offset', () => {
	const offenders = FILES.filter(
		(f) => f.rel !== HELPER && /'sunday'\s*\?\s*[\w.]+\.getDay\(\)/.test(f.text),
	).map((f) => f.rel);
	assert.deepEqual(offenders, [], 'import weekStartLocal from training/goals instead');
});

test('no Monday-only week offset outside the documented exceptions', () => {
	const offenders = FILES.filter(
		(f) =>
			f.rel !== HELPER &&
			!(f.rel in MONDAY_ONLY_ALLOWED) &&
			/\([\w.]+\.getDay\(\) \+ 6\) % 7/.test(f.text),
	).map((f) => f.rel);
	assert.deepEqual(offenders, [], 'a week window must honour week_start_day via weekStartLocal');
	for (const rel of Object.keys(MONDAY_ONLY_ALLOWED)) {
		const f = FILES.find((x) => x.rel === rel);
		assert.ok(f && /\.getDay\(\) \+ 6\) % 7/.test(f.text), `${rel} no longer needs its exemption`);
	}
});

test('every "this week" surface reads the shared helper', () => {
	for (const rel of [
		'lib/training/current_week.ts',
		'lib/training/consistency.ts',
		'lib/training/trend_deltas.ts',
		'lib/training/week_lead.ts',
		'lib/core/weekly_mileage.ts',
		'lib/components/PeriodSummary.svelte',
		'routes/dashboard/+page.svelte',
	]) {
		const f = FILES.find((x) => x.rel === rel);
		assert.ok(f, `${rel} moved — re-anchor this guard`);
		assert.match(f.text, /\bweekStartLocal\(/, `${rel} must take its week window from weekStartLocal`);
	}
});
