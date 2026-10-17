// The catalogue half of workout_summary.ts: the walk-run pattern and the
// zone chip as a reader sees them. Takes the translator so it stays a plain
// module the node:test runner can load.

import type { MessageKey } from '#lib/i18n/messages.ts';
import type { PaceZoneName, SpokenDuration, WalkRunPattern } from './workout_summary';
import { aboutMinutes, spokenDuration } from './workout_summary';

type Translate = (key: MessageKey, params?: Record<string, string | number>) => string;

export function formatSpokenDuration(t: Translate, d: SpokenDuration): string {
	switch (d.unit) {
		case 'min':
			return t('workoutSummary.min', { n: d.minutes });
		case 'sec':
			return t('workoutSummary.sec', { n: d.seconds });
		case 'minSec':
			return t('workoutSummary.minSec', { m: d.minutes, s: d.seconds });
	}
}

/// "5 min warm-up, 8 × (1 min run / 90 s walk), 5 min cool-down".
export function formatWalkRunPattern(t: Translate, p: WalkRunPattern): string {
	const say = (sec: number) => formatSpokenDuration(t, spokenDuration(sec));
	const main =
		p.walkS != null
			? t('workoutSummary.intervals', { count: p.count, run: say(p.runS), walk: say(p.walkS) })
			: t('workoutSummary.continuous', { run: say(p.count * p.runS) });
	const warmup = p.warmupS != null ? t('workoutSummary.warmup', { duration: say(p.warmupS) }) : null;
	const cooldown =
		p.cooldownS != null ? t('workoutSummary.cooldown', { duration: say(p.cooldownS) }) : null;
	if (warmup && cooldown) return t('workoutSummary.withBoth', { warmup, main, cooldown });
	if (warmup) return t('workoutSummary.withWarmup', { warmup, main });
	if (cooldown) return t('workoutSummary.withCooldown', { main, cooldown });
	return main;
}

/// "about 29 min".
export function formatWalkRunTotal(t: Translate, p: WalkRunPattern): string {
	return t('workoutSummary.about', {
		duration: t('workoutSummary.min', { n: aboutMinutes(p.totalS) })
	});
}

const ZONE_NAME_KEYS: Record<PaceZoneName, MessageKey> = {
	easy: 'planEditor.paceEasy',
	marathon: 'planEditor.paceMarathon',
	tempo: 'planEditor.paceTempo',
	interval: 'planEditor.paceInterval',
	repetition: 'planEditor.paceRepetition'
};

/// "Zone T · Tempo" for a Daniels code, "Zone Z2" for free text.
export function formatPaceZone(t: Translate, code: string, name: PaceZoneName | null): string {
	return name
		? t('workoutDetail.zoneNamed', { code: code.trim(), name: t(ZONE_NAME_KEYS[name]) })
		: t('workoutDetail.zoneRaw', { code: code.trim() });
}
