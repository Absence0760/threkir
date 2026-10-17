/**
 * The load signal for a runner who has just come back from a break.
 *
 * `self_load.ts` grades the runner's acute:chronic workload ratio and refuses
 * to say anything below `MIN_ACTIVE_WEEKS` of the chronic window — correctly,
 * because dividing a comeback week by a near-empty month manufactures a
 * terrifying ratio out of thin air. But that refusal is silent exactly where
 * the runner is most exposed: someone back from three months off, logging a
 * 30 km first week, sees no card at all.
 *
 * The gap is the *instrument*, not the threshold. ACWR asks "how does this
 * week compare with the month you just trained", and a comeback runner has no
 * such month. This asks a question their history can actually answer: "how
 * does this week compare with the weeks you were running before the break".
 * Their own pre-break average is real data; the near-zero month is not.
 *
 * It fires only where `selfLoad` is silent — the same `activeWeeks` gate, read
 * the other way round — so the two cards are mutually exclusive by
 * construction rather than by the dashboard remembering to choose.
 *
 * Pure (no Svelte / Supabase) so it runs under `npx tsx --test`.
 *
 * Dart twin: apps/mobile_android/lib/comeback.dart (parity pair — keep the
 * algorithm, thresholds, gates, and test counts in lockstep). The surfaces are
 * `ComebackCard.svelte` here and `widgets/comeback_card.dart` there.
 */

import { kLayoffResetDays } from './training_load';
import { EASY_RUN_FLOOR_KM, RECOVERY_RUN_MAX_KM } from './training';
import {
	CHRONIC_WINDOW_WEEKS,
	MIN_ACTIVE_WEEKS,
	recentRunVolume,
	volumeSample,
	type RunForVolume,
} from './plan_ramp';

const DAY_MS = 86_400_000;
const WEEK_MS = 7 * DAY_MS;

/// How long a run-less stretch has to be before it counts as a break rather
/// than a rest week. Deliberately `training_load`'s own layoff constant: that
/// is already the point at which the app writes the runner's fitness EWMAs
/// down to zero, and a break big enough to erase their modelled fitness is
/// the same break this card is about. Two numbers for one idea would drift.
export const LAYOFF_MIN_DAYS = kLayoffResetDays;

/// Past this, the pre-break average stops being a usable anchor and the card
/// says nothing. A base two years stale describes a body that no longer
/// exists, and grading a return against it would produce a *reassuring*
/// number for a runner who is effectively starting over — over-reporting
/// safety is the failure that hurts here.
export const LAYOFF_MAX_DAYS = 365;

/// The share of the pre-break weekly average above which a first week back is
/// called steep. An editorial line, not a clinical one: the widely-taught
/// return-to-running shape is to resume at around half of what you were doing
/// and rebuild from there. It is deliberately one flat threshold rather than a
/// curve decaying with layoff length — a decay function would invent precision
/// the underlying evidence does not have, and a runner can reason about "half".
export const RETURN_WEEK_SHARE = 0.5;

export type ComebackVerdict = 'insufficient' | 'easing_in' | 'steep';

export interface ComebackLoad {
	/// 'insufficient' whenever there is no break, no usable pre-break base, or
	/// no running this week — the caller renders nothing rather than a claim it
	/// cannot stand behind.
	verdict: ComebackVerdict;
	/// Whole days between the last run before the break and the first run
	/// after it. 0 when the verdict is 'insufficient'.
	layoffDays: number;
	/// `layoffDays` as whole weeks, rounded to nearest — the figure the copy
	/// renders. Rounded rather than floored because overstating a break is the
	/// conservative direction for a safety claim. Never below 4, since
	/// `LAYOFF_MIN_DAYS` is 28.
	layoffWeeks: number;
	/// Last 7 days' running distance, metres.
	thisWeekM: number;
	/// Mean weekly running distance over the four windows before the break.
	preLayoffWeeklyM: number;
	/// `thisWeekM` / `preLayoffWeeklyM`. 0 when the verdict is 'insufficient'.
	share: number;
}

const UNGRADED: ComebackLoad = {
	verdict: 'insufficient',
	layoffDays: 0,
	layoffWeeks: 0,
	thisWeekM: 0,
	preLayoffWeeklyM: 0,
	share: 0,
};

/**
 * Grade the runner's first weeks back against the weeks they were running
 * before the break.
 *
 * Fail-closed at every step. No run this week, no break in the history, a
 * break too old to anchor against, or too thin a pre-break base all return
 * `insufficient` — the caller shows nothing, exactly as it does today, rather
 * than a number derived from a history that cannot carry it.
 */
export function comebackLoad(runs: RunForVolume[], nowMs: number): ComebackLoad {
	const recent = recentRunVolume(runs, nowMs);
	// The ratio card owns any runner whose recent history can carry it; this
	// one exists for the hole that refusal leaves, and two load cards claiming
	// the same week would be worse than either alone.
	if (recent.activeWeeks >= MIN_ACTIVE_WEEKS) return UNGRADED;
	// A week with no running has no load to grade, and an "easing in" verdict
	// off zero kilometres would read as praise for not running.
	if (recent.acuteM <= 0) return UNGRADED;

	// A device whose clock runs ahead stamps a just-finished run in the future.
	// `recentRunVolume` absorbs that by clamping the age to zero; the same
	// clamp has to happen here, because an unclamped future stamp opens a gap
	// to the run before it and would be read as a layoff that never happened.
	const samples = runs
		.map(volumeSample)
		.filter((s): s is NonNullable<typeof s> => s !== null)
		.map((s) => ({ ...s, startedMs: Math.min(s.startedMs, nowMs) }))
		.sort((a, b) => b.startedMs - a.startedMs);

	// The most recent run-less stretch long enough to count, walking back from
	// today. Later breaks are the ones the runner is living through; an older
	// one is history they have already trained past.
	let gapIndex = -1;
	for (let i = 0; i < samples.length - 1; i++) {
		if (samples[i].startedMs - samples[i + 1].startedMs >= LAYOFF_MIN_DAYS * DAY_MS) {
			gapIndex = i;
			break;
		}
	}
	if (gapIndex < 0) return UNGRADED;

	const layoffDays = Math.floor(
		(samples[gapIndex].startedMs - samples[gapIndex + 1].startedMs) / DAY_MS,
	);
	if (layoffDays > LAYOFF_MAX_DAYS) return UNGRADED;

	// The base is reduced over the same rolling 7-day windows as the acute
	// week, anchored on the last run before the break instead of on today.
	const anchorMs = samples[gapIndex + 1].startedMs;
	let baseTotalM = 0;
	const baseWeeks = new Set<number>();
	for (const sample of samples) {
		const age = anchorMs - sample.startedMs;
		if (age < 0) continue;
		const week = Math.floor(age / WEEK_MS);
		if (week >= CHRONIC_WINDOW_WEEKS) continue;
		baseTotalM += sample.distanceM;
		baseWeeks.add(week);
	}
	// The same evidence bar `plan_ramp` sets, applied where the history is
	// real: a single run before the break is not a base to come back to.
	if (baseWeeks.size < MIN_ACTIVE_WEEKS) return UNGRADED;
	const preLayoffWeeklyM = baseTotalM / CHRONIC_WINDOW_WEEKS;
	if (preLayoffWeeklyM <= 0) return UNGRADED;

	const share = recent.acuteM / preLayoffWeeklyM;
	return {
		verdict: share > RETURN_WEEK_SHARE ? 'steep' : 'easing_in',
		layoffDays,
		layoffWeeks: Math.round(layoffDays / 7),
		thisWeekM: recent.acuteM,
		preLayoffWeeklyM,
		share,
	};
}

/// A comeback the caller may actually render copy for.
export type GradedComebackVerdict = Exclude<ComebackVerdict, 'insufficient'>;
export interface GradedComebackLoad extends ComebackLoad {
	verdict: GradedComebackVerdict;
}

/// Whether the dashboard has a comeback worth showing.
///
/// A type predicate rather than a bare boolean, for the reason
/// `shouldSurfaceSelfLoad` already documents: it narrows the verdict to the
/// two the card has copy for, so an unlabelled verdict is a compile error
/// rather than a missing-key render.
export function shouldSurfaceComeback(load: ComebackLoad): load is GradedComebackLoad {
	return load.verdict !== 'insufficient';
}

/// A break the plan wizard can size a first week from.
export interface ReturnFromBreak {
	/// Whole days off: from the last run before the break to the first run
	/// after it, or to today while the break is still open.
	layoffDays: number;
	/// `layoffDays` as whole weeks, rounded to nearest, as `ComebackLoad` does.
	layoffWeeks: number;
	/// Mean weekly running distance over the four windows before the break.
	preLayoffWeeklyM: number;
	/// The ceiling on a new plan's opening week: `RETURN_WEEK_SHARE` of the
	/// pre-break average, the same "about half" the dashboard card grades by.
	openingCapM: number;
}

/// How much a capped return week may grow on the one before it. The common
/// "no more than about 10% a week" rule of thumb: editorial, like
/// `RETURN_WEEK_SHARE`, and stated as a round number for the same reason.
export const RETURN_WEEKLY_GROWTH = 1.1;

/**
 * Is the runner coming back from a break, as the plan wizard needs to know it?
 *
 * `comebackLoad` answers a different question: it grades a week the runner has
 * already run, so it needs running this week and says nothing to someone who
 * has not started again yet. The wizard is often opened before that first run,
 * which is when a capped opening week helps most. So this reads the break the
 * runner is in or has just ended, whether or not they have run this week:
 * still open when the latest run is a layoff ago, otherwise the most recent
 * run-less stretch long enough to count, provided it ended inside the chronic
 * window. A break that ended longer ago than that is history the runner has
 * been running through, sporadically or not, and its base is too old to cap a
 * plan against.
 *
 * The same gates as `comebackLoad` otherwise: only below `MIN_ACTIVE_WEEKS`
 * (above it `plan_ramp` grades the plan against real recent training), a break
 * of `LAYOFF_MIN_DAYS` to `LAYOFF_MAX_DAYS`, and a pre-break base with at
 * least `MIN_ACTIVE_WEEKS` active windows. Null whenever any of them fails.
 */
export function returningFromBreak(runs: RunForVolume[], nowMs: number): ReturnFromBreak | null {
	if (recentRunVolume(runs, nowMs).activeWeeks >= MIN_ACTIVE_WEEKS) return null;
	const samples = runs
		.map(volumeSample)
		.filter((s): s is NonNullable<typeof s> => s !== null)
		.map((s) => ({ ...s, startedMs: Math.min(s.startedMs, nowMs) }))
		.sort((a, b) => b.startedMs - a.startedMs);
	if (samples.length === 0) return null;

	let endMs: number;
	let anchorMs: number;
	if (nowMs - samples[0].startedMs >= LAYOFF_MIN_DAYS * DAY_MS) {
		endMs = nowMs;
		anchorMs = samples[0].startedMs;
	} else {
		let gapIndex = -1;
		for (let i = 0; i < samples.length - 1; i++) {
			if (samples[i].startedMs - samples[i + 1].startedMs >= LAYOFF_MIN_DAYS * DAY_MS) {
				gapIndex = i;
				break;
			}
		}
		if (gapIndex < 0) return null;
		endMs = samples[gapIndex].startedMs;
		if (nowMs - endMs >= CHRONIC_WINDOW_WEEKS * WEEK_MS) return null;
		anchorMs = samples[gapIndex + 1].startedMs;
	}
	const layoffDays = Math.floor((endMs - anchorMs) / DAY_MS);
	if (layoffDays > LAYOFF_MAX_DAYS) return null;

	let baseTotalM = 0;
	const baseWeeks = new Set<number>();
	for (const sample of samples) {
		const age = anchorMs - sample.startedMs;
		if (age < 0) continue;
		const week = Math.floor(age / WEEK_MS);
		if (week >= CHRONIC_WINDOW_WEEKS) continue;
		baseTotalM += sample.distanceM;
		baseWeeks.add(week);
	}
	if (baseWeeks.size < MIN_ACTIVE_WEEKS) return null;
	const preLayoffWeeklyM = baseTotalM / CHRONIC_WINDOW_WEEKS;
	if (preLayoffWeeklyM <= 0) return null;
	return {
		layoffDays,
		layoffWeeks: Math.round(layoffDays / 7),
		preLayoffWeeklyM,
		openingCapM: preLayoffWeeklyM * RETURN_WEEK_SHARE,
	};
}

/// The fields `capReturnRamp` reads and writes. Structural, so a generated
/// plan's weeks pass straight in.
export interface RampWorkout {
	kind: string;
	target_distance_m: number | null;
	target_duration_seconds: number | null;
	target_pace_sec_per_km: number | null;
	target_pace_tolerance_sec: number | null;
	structure: unknown;
	notes: string | null;
}
export interface RampWeek<W extends RampWorkout> {
	week_index: number;
	target_volume_m: number;
	workouts: W[];
}

const QUALITY_KINDS = new Set(['tempo', 'interval', 'marathon_pace']);
/// The easy run's pace band, so a quality session turned easy matches the
/// generator's own easy run (training.ts `easyWorkout`).
const EASY_TOLERANCE_SEC = 30;

function isFixed(kind: string): boolean {
	return kind === 'race' || kind === 'rest';
}

/**
 * Ease a generated plan in for a runner coming back from a break.
 *
 * Week 1 may ask for at most `openingCapM` of running, and each week after it
 * at most `RETURN_WEEKLY_GROWTH` times the cap before it, so the plan climbs
 * from half the runner's pre-break volume by about 10% a week. The first week
 * whose own schedule fits under its cap ends the climb: it and every week
 * after are left exactly as generated. A race is never counted against a cap
 * or touched, and rest stays rest.
 *
 * Every week before that point is a return week:
 * - its tempo, interval and marathon-pace sessions become easy runs, because
 *   the first weeks back rebuild volume before intensity, and deciding that by
 *   position rather than per week stops speed work coming and going;
 * - its sessions scale by one factor to fit the cap (distance to the nearest
 *   100 m, duration to the second), so the week keeps its shape;
 * - a session the scaling would take under the generator's 3 km floor is
 *   dropped to rest, shortest first, and the cap is shared among the rest, so
 *   the cap never prescribes a pointless 300 m run. The last session standing
 *   is kept whatever its length: a short run is still a week of running;
 * - an easy run under 4 km is labelled recovery, as the generator labels it.
 * The week's stated volume is re-summed from what it now prescribes.
 *
 * Pure: returns new weeks and leaves the input alone. A cap that is not a
 * positive number returns the weeks unchanged.
 */
export function capReturnRamp<W extends RampWorkout, K extends RampWeek<W>>(
	weeks: K[],
	openingCapM: number,
	easyPaceSecPerKm: number,
): K[] {
	if (!Number.isFinite(openingCapM) || openingCapM <= 0 || weeks.length === 0) return weeks;
	const ordered = [...weeks].sort((a, b) => a.week_index - b.week_index);
	const firstIndex = ordered[0].week_index;
	const capped = new Map<K, K>();
	for (const week of ordered) {
		const capM = openingCapM * RETURN_WEEKLY_GROWTH ** (week.week_index - firstIndex);
		const runningM = week.workouts.reduce(
			(s, wo) => s + (isFixed(wo.kind) ? 0 : (wo.target_distance_m ?? 0)),
			0,
		);
		if (runningM <= capM) break;
		capped.set(week, capWeek(week, capM, easyPaceSecPerKm));
	}
	return weeks.map((w) => capped.get(w) ?? w);
}

function capWeek<W extends RampWorkout, K extends RampWeek<W>>(week: K, capM: number, easyPace: number): K {
	const kept = new Set<number>();
	week.workouts.forEach((wo, i) => {
		if (!isFixed(wo.kind)) kept.add(i);
	});
	const distanceOf = (i: number) => week.workouts[i].target_distance_m ?? 0;
	const keptM = () => [...kept].reduce((s, i) => s + distanceOf(i), 0);
	let factor = capM / keptM();
	for (;;) {
		const measured = [...kept].filter((i) => distanceOf(i) > 0).sort((a, b) => distanceOf(a) - distanceOf(b));
		if (measured.length <= 1 || distanceOf(measured[0]) * factor >= EASY_RUN_FLOOR_KM * 1000) break;
		kept.delete(measured[0]);
		factor = capM / keptM();
	}
	factor = Math.min(1, factor);
	const workouts = week.workouts.map((wo, i): W => {
		if (isFixed(wo.kind)) return wo;
		if (!kept.has(i)) {
			return {
				...wo,
				kind: 'rest',
				target_distance_m: null,
				target_duration_seconds: null,
				target_pace_sec_per_km: null,
				target_pace_tolerance_sec: null,
				structure: null,
				notes: null,
			};
		}
		const metres =
			wo.target_distance_m == null ? null : Math.round((wo.target_distance_m * factor) / 100) * 100;
		const seconds =
			wo.target_duration_seconds == null ? null : Math.round(wo.target_duration_seconds * factor);
		const quality = QUALITY_KINDS.has(wo.kind);
		let kind = quality ? 'easy' : wo.kind;
		if (kind === 'easy' && metres != null && metres < RECOVERY_RUN_MAX_KM * 1000) kind = 'recovery';
		return {
			...wo,
			kind,
			target_distance_m: metres,
			target_duration_seconds: seconds,
			...(quality
				? {
						target_pace_sec_per_km: easyPace,
						target_pace_tolerance_sec: EASY_TOLERANCE_SEC,
						structure: null,
						notes: null,
					}
				: {}),
		};
	});
	const volume = workouts.reduce((s, wo) => s + (wo.target_distance_m ?? 0), 0);
	return { ...week, target_volume_m: volume, workouts };
}
