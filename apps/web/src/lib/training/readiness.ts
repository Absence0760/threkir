/**
 * Readiness-to-run score. Combines training balance (form / TSB),
 * last night's sleep, and resting-HR drift vs a baseline into a
 * single 0–100 number the dashboard can show.
 *
 * Garmin's "Body Battery", Whoop's "Recovery" and Oura's "Readiness"
 * are the precedents. We compute deltas around a neutral baseline of
 * 75; positive contributors push it up, negative ones drag it down,
 * and the result is clamped to 0–100.
 *
 * Pure — no Supabase, no DOM. TS↔Dart parity pair with
 * `apps/mobile_android/lib/readiness.dart`. Keep in lockstep — the
 * shared-library-syncer agent watches the pair.
 */

import type { MessageKey } from '../i18n/messages';

export interface ReadinessInputs {
	/** Training Stress Balance (Form). Positive = fresh, negative = fatigued. Pass null if unknown. */
	tsb: number | null;
	/** Hours of sleep last night. Pass null if unknown. */
	sleepHours?: number | null;
	/** This morning's resting heart rate, in bpm. Pass null if unknown. */
	restingHrBpm?: number | null;
	/** 30-day baseline resting heart rate. Pass null if unknown. */
	baselineRestingHrBpm?: number | null;
}

export type ReadinessBand = 'low' | 'moderate' | 'high';

/**
 * Which input a contribution came from. The UI names it in the reader's
 * locale. The form input is deliberately not labelled like the TSB tile it is
 * derived from: this is the POINTS form added to the score, not the TSB value,
 * and one name over two different numbers read as a contradiction (#902).
 */
export type ReadinessContributorKind = 'form' | 'sleep' | 'resting_hr';

/// Why an input moved the score. The words live in the reader's catalogue
/// (`dash.readinessReason_<reason>`), read by `readinessAdviceText`.
export type ReadinessReason =
	| 'heavyFatigue'
	| 'fatigued'
	| 'slightFatigue'
	| 'formNeutral'
	| 'fresh'
	| 'veryFresh'
	| 'overTapered'
	| 'veryLittleSleep'
	| 'shortSleep'
	| 'underSleep'
	| 'wellRested'
	| 'extendedSleep'
	| 'hrWellAbove'
	| 'hrAbove'
	| 'hrSlightlyHigh'
	| 'hrBaseline'
	| 'hrBelow';

export interface ReadinessContribution {
	kind: ReadinessContributorKind;
	/** Signed delta this input added to the score. */
	delta: number;
	reason: ReadinessReason;
	/** Resting HR above baseline, for the reasons that name it. */
	diffBpm?: number;
}

export interface Readiness {
	/** Final score in 0..100. */
	score: number;
	/** Bucket — drives card colour and tone of advice. */
	band: ReadinessBand;
	/** The contributor the advice line names; null when there are no inputs. */
	dominant: ReadinessContribution | null;
	/** Per-input breakdown so the UI can show "why". */
	contributors: ReadinessContribution[];
}

/** Neutral starting point. A user with no inputs at all gets 75. */
const BASELINE_SCORE = 75;

function clamp(v: number, lo: number, hi: number): number {
	return Math.min(hi, Math.max(lo, v));
}

function bandFor(score: number): ReadinessBand {
	if (score >= 70) return 'high';
	if (score >= 40) return 'moderate';
	return 'low';
}

/**
 * Score the contribution from Training Stress Balance.
 *
 * TSB convention (matches `lib/training/training_load.ts`):
 *  - TSB ≈ 0   → neutral / maintenance form
 *  - TSB > +5  → fresh; small positive on score
 *  - TSB < -10 → fatigued; large negative on score
 *  - TSB > +25 → over-tapered, slightly negative again ("detraining
 *               risk" / blunted edge — small but real)
 */
function scoreTsb(tsb: number | null): ReadinessContribution | null {
	// A non-finite TSB (a NaN out of a poisoned load series) is no signal:
	// every comparison below is false for NaN, so it used to land on the
	// final "over-tapered" branch and cost the score 3 points.
	if (tsb == null || !Number.isFinite(tsb)) return null;
	let delta = 0;
	let reason: ReadinessReason;
	if (tsb < -20) {
		delta = -20;
		reason = 'heavyFatigue';
	} else if (tsb < -10) {
		delta = -12;
		reason = 'fatigued';
	} else if (tsb < -5) {
		delta = -6;
		reason = 'slightFatigue';
	} else if (tsb <= 5) {
		delta = 0;
		reason = 'formNeutral';
	} else if (tsb <= 15) {
		delta = 8;
		reason = 'fresh';
	} else if (tsb <= 25) {
		delta = 5;
		reason = 'veryFresh';
	} else {
		delta = -3;
		reason = 'overTapered';
	}
	return { kind: 'form', delta, reason };
}

function scoreSleep(hours: number | null | undefined): ReadinessContribution | null {
	if (hours == null || !Number.isFinite(hours)) return null;
	let delta = 0;
	let reason: ReadinessReason;
	if (hours < 5) {
		delta = -25;
		reason = 'veryLittleSleep';
	} else if (hours < 6.5) {
		delta = -12;
		reason = 'shortSleep';
	} else if (hours < 7.5) {
		delta = -3;
		reason = 'underSleep';
	} else if (hours <= 9) {
		delta = 5;
		reason = 'wellRested';
	} else {
		delta = 0;
		reason = 'extendedSleep';
	}
	return { kind: 'sleep', delta, reason };
}

function scoreRestingHr(
	resting: number | null | undefined,
	baseline: number | null | undefined,
): ReadinessContribution | null {
	if (resting == null || baseline == null || !Number.isFinite(resting - baseline)) return null;
	const diff = resting - baseline;
	let delta = 0;
	let reason: ReadinessReason;
	if (diff > 10) {
		delta = -18;
		reason = 'hrWellAbove';
	} else if (diff > 5) {
		delta = -10;
		reason = 'hrAbove';
	} else if (diff > 2) {
		delta = -4;
		reason = 'hrSlightlyHigh';
	} else if (diff >= -2) {
		delta = 0;
		reason = 'hrBaseline';
	} else {
		delta = 3;
		reason = 'hrBelow';
	}
	return reason === 'hrWellAbove' || reason === 'hrAbove'
		? { kind: 'resting_hr', delta, reason, diffBpm: diff }
		: { kind: 'resting_hr', delta, reason };
}

/** Pick the contributor that pushed the score the most (in absolute terms). */
function dominantContributor(contributors: ReadinessContribution[]): ReadinessContribution | null {
	if (contributors.length === 0) return null;
	// Ties in |delta| are common — a TSB of -12 and six hours of sleep both
	// score -12, and the two carry DIFFERENT advice — so which one wins is a
	// contract, not an accident. `Array.prototype.sort` is stable, so the
	// first contributor added wins; the Dart twin's `List.sort` is NOT, and
	// carries an explicit index tiebreak to match.
	return contributors.slice().sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta))[0];
}

export type ReadinessTranslate = (key: MessageKey, params?: Record<string, string | number>) => string;

const NEXT: Record<ReadinessBand, MessageKey> = {
	low: 'dash.readinessNext_low',
	moderate: 'dash.readinessNext_moderate',
	high: 'dash.readinessNext_high',
};

/// The advice line in the reader's language: the dominant input's reason and
/// what the band suggests, or, with no inputs, a band-aware suggestion.
export function readinessAdviceText(r: Readiness, t: ReadinessTranslate): string {
	const d = r.dominant;
	if (!d) return t(r.band === 'high' ? 'dash.readinessAdvice_noSignalHigh' : 'dash.readinessAdvice_noSignal');
	return t('dash.readinessAdviceLine', {
		reason: t(`dash.readinessReason_${d.reason}`, d.diffBpm == null ? undefined : { bpm: d.diffBpm }),
		next: t(NEXT[r.band]),
	});
}

export function computeReadiness(inputs: ReadinessInputs): Readiness {
	const contributors: ReadinessContribution[] = [];
	const tsb = scoreTsb(inputs.tsb);
	if (tsb) contributors.push(tsb);
	const sleep = scoreSleep(inputs.sleepHours ?? null);
	if (sleep) contributors.push(sleep);
	const hr = scoreRestingHr(
		inputs.restingHrBpm ?? null,
		inputs.baselineRestingHrBpm ?? null,
	);
	if (hr) contributors.push(hr);

	const sum = contributors.reduce((s, c) => s + c.delta, 0);
	const score = clamp(Math.round(BASELINE_SCORE + sum), 0, 100);
	const band = bandFor(score);
	return {
		score,
		band,
		dominant: dominantContributor(contributors),
		contributors,
	};
}
