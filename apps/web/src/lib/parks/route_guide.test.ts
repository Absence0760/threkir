import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
	GUIDE_EN,
	GUIDE_LINE_KEYS,
	formatGuideLine,
	parseRouteGuide,
	routeGuideEnglish,
	routeGuideLines,
	routeGuideText,
	type GuideFormat,
} from './route_guide';
import { en } from '../i18n/locales/en';

// The TS reader of fixtures/route_guide_cases.json, the case table the Dart
// twin (apps/mobile_android/test/route_guide_test.dart) reads too.
const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
const { cases } = JSON.parse(readFileSync(join(REPO, 'fixtures', 'route_guide_cases.json'), 'utf-8')) as {
	cases: {
		name: string;
		guide: unknown;
		parsed: { lang: string; getting_there: string | null } | null;
		lines?: Record<string, unknown>[];
	}[];
};

for (const c of cases) {
	test(`route guide case: ${c.name}`, () => {
		const guide = parseRouteGuide(c.guide);
		if (c.parsed === null) {
			assert.equal(guide, null);
			return;
		}
		assert.ok(guide);
		assert.equal(guide.lang, c.parsed.lang);
		assert.equal(guide.gettingThere, c.parsed.getting_there);
		assert.deepEqual(routeGuideLines(guide), c.lines);
	});
}

const catalogue = en as Record<string, string>;
const english: GuideFormat = {
	message: (key, params) =>
		catalogue[`parks.guide.${key}`].replace(/\{(\w+)\}/g, (_, p: string) => String(params[p])),
	distance: (m) => `${(m / 1000).toFixed(1)} km`,
	short: (m) => `${m} m`,
};

test('every line key has an English template whose placeholders it fills', () => {
	for (const key of GUIDE_LINE_KEYS) {
		const template = catalogue[`parks.guide.${key}`];
		assert.ok(template, key);
		const line = formatGuideLine(
			{ key, at: 1000, name: 'N', landmark: 'L', gain: 5, length: 50, n: 2, total: 3 },
			english,
		);
		assert.doesNotMatch(line, /\{\w+\}/, key);
	}
});

test('routeGuideText renders a guide as English lines', () => {
	const guide = parseRouteGuide(cases[0].guide);
	assert.ok(guide);
	const text = routeGuideText(guide, english);
	assert.equal(text[0], 'Start on Lake Trail.');
	assert.equal(text[1], 'Run the loop clockwise.');
	assert.equal(text[2], 'Pass every checkpoint in order, or the run is not timed.');
	assert.equal(text[3], '0.4 km: turn left onto Ridge Trail.');
	assert.equal(text[6], '0.8 km: a climb of 14 m over 300 m.');
	assert.equal(text.at(-1), '2.0 km: finish.');
});

test('GUIDE_EN is the English catalogue, entry for entry', () => {
	for (const [key, value] of Object.entries(GUIDE_EN)) {
		assert.equal(value, catalogue[`parks.guide.${key}`], key);
	}
	assert.deepEqual(
		Object.keys(GUIDE_EN).sort(),
		[...GUIDE_LINE_KEYS, 'pending', 'checked'].sort(),
	);
});

test('routeGuideEnglish leads with the ground-check status and the getting-there note', () => {
	const guide = parseRouteGuide(cases[0].guide);
	assert.ok(guide);
	const pending = routeGuideEnglish(guide, null);
	assert.equal(pending[0], 'Drafted from map data, not yet checked on the ground.');
	assert.equal(pending[1], 'Park by the boathouse.');
	assert.equal(pending[2], 'Start on Lake Trail.');
	assert.equal(routeGuideEnglish(guide, '2026-12-01')[0], 'Checked on the ground on 2026-12-01.');
});
