// Renders the workout summary out of the real catalogues. Mirrored by
// apps/mobile_android/test/workout_summary_format_test.dart.
import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { interpolate } from '../i18n/interpolate';
import { CATALOGUE_LOADERS } from '../i18n/catalogues';
import type { Locale } from '../i18n/locale';
import type { MessageKey } from '../i18n/messages';
import { walkRunPattern, paceZoneName } from './workout_summary';
import type { WorkoutStructure } from './training';
import { formatPaceZone, formatPlannedSize, formatWalkRunPattern, formatWalkRunTotal } from './workout_summary_format';

type Translate = (key: MessageKey, params?: Record<string, string | number>) => string;

async function translatorFor(loc: Locale): Promise<Translate> {
	const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
	return (key, params) => interpolate(dict[key], params, loc);
}

const week1: WorkoutStructure = {
	warmup: { duration_s: 300, pace: 'easy' },
	repeats: {
		count: 8,
		duration_s: 60,
		pace_sec_per_km: 420,
		recovery_duration_s: 90,
		recovery_pace: 'walk'
	},
	cooldown: { duration_s: 300, pace: 'easy' }
};

const graduation: WorkoutStructure = {
	repeats: { count: 1, duration_s: 1800, pace_sec_per_km: 420, recovery_duration_s: 90, recovery_pace: 'walk' }
};

const fiveK: WorkoutStructure = {
	warmup: { duration_s: 300, pace: 'easy' },
	repeats: { count: 1, distance_m: 5000, pace_sec_per_km: 420, recovery_pace: 'walk' },
	cooldown: { duration_s: 300, pace: 'easy' }
};

const km = (m: number) => `${m / 1000} km`;

test('en: a week-1 walk-run reads as its pattern and its length', async () => {
	const t = await translatorFor('en');
	const p = walkRunPattern(week1)!;
	assert.equal(
		formatWalkRunPattern(t, p, km),
		'5 min warm-up, 8 × (1 min run / 90 s walk), 5 min cool-down'
	);
	// 300 + 8 × 60 + 7 × 90 + 300 = 1710 s, 28.5 min rounds to 29.
	assert.equal(formatWalkRunTotal(t, p, km), 'about 29 min');
});

test('en: the graduation week is one continuous run, no walk breaks', async () => {
	const t = await translatorFor('en');
	assert.equal(formatWalkRunPattern(t, walkRunPattern(graduation)!, km), '30 min run');
});

test('en: the graduation 5K reads as a distance, with no minutes for the run', async () => {
	const t = await translatorFor('en');
	const p = walkRunPattern(fiveK)!;
	assert.equal(formatWalkRunPattern(t, p, km), '5 min warm-up, 5 km run, 5 min cool-down');
	assert.equal(formatWalkRunTotal(t, p, km), '5 km run');
});

test('en: a plan card states a timed session in minutes and a distance as a distance', async () => {
	const t = await translatorFor('en');
	assert.equal(formatPlannedSize(t, { kind: 'duration', seconds: 1710 }, km), '29 min');
	assert.equal(formatPlannedSize(t, { kind: 'distance', metres: 5000 }, km), '5 km');
});

test('en: a Daniels code is named, free text is shown as typed', async () => {
	const t = await translatorFor('en');
	assert.equal(formatPaceZone(t, ' T ', paceZoneName(' T ')), 'Zone T · Tempo');
	assert.equal(formatPaceZone(t, 'Z2', paceZoneName('Z2')), 'Zone Z2');
});

test('fr + pt-BR: the walk-run wording the translation review settled on', async () => {
	const fr = await translatorFor('fr');
	assert.equal(fr('workoutDetail.effortJog'), 'footing');
	assert.equal(
		formatWalkRunPattern(fr, walkRunPattern(week1)!, km),
		"5 min d'échauffement, 8 × (1 min de course / 90 s de marche), 5 min de retour au calme"
	);
	const ptBR = await translatorFor('pt-BR');
	assert.match(ptBR('workoutDetail.taglineWalkRun'), /caminhada-corrida/);
});

test('every locale renders the pattern with no unfilled placeholder', async () => {
	for (const loc of Object.keys(CATALOGUE_LOADERS) as Locale[]) {
		const t = await translatorFor(loc);
		for (const s of [week1, graduation, fiveK]) {
			const p = walkRunPattern(s)!;
			for (const out of [formatWalkRunPattern(t, p, km), formatWalkRunTotal(t, p, km)]) {
				assert.doesNotMatch(out, /[{}]/, `${loc}: ${out}`);
			}
		}
		assert.doesNotMatch(formatPaceZone(t, 'I', 'interval'), /[{}]/, loc);
	}
});
