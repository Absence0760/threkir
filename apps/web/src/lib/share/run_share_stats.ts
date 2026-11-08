// The numbers every run share image prints, chosen and formatted once so the
// map card, the photo and the sticker never disagree with each other or with
// the phone. Twin of apps/mobile_android/lib/run_share_stats.dart: the same
// kinds, the same "only what the run measured" rule, the same fall-back to
// distance, and the same value / unit split, formatted through the same
// arithmetic as Dart's `UnitFormat`.

import type { PreferredUnit, TrackPoint } from '../types';
import { formatDecimal } from '../format/number';
import { paceMinutesSeconds } from '../format/pace_format';
import { formatElevationValue } from '../format/elevation';
import { computeRunElevationGain } from '../runs/run_altitude';
import { movingTimeSeconds } from '../runs/run_stats';
import { activityUsesSpeed } from '../runs/activity_type';

/// A number a share image can print. `pace` prints as speed for an activity
/// measured in speed (a ride), so a runner never has to pick between them.
export const RUN_SHARE_STAT_KINDS = ['distance', 'pace', 'time', 'climb', 'heartRate'] as const;
export type RunShareStatKind = (typeof RUN_SHARE_STAT_KINDS)[number];

/// One headline stat as the share images print it.
export interface RunShareStat {
	kind: RunShareStatKind;
	label: string;
	value: string;
	unit: string | null;
}

/// The fields of a run the share images read.
export interface ShareableRun {
	distance_m: number;
	duration_s: number;
	track: TrackPoint[] | null;
	source: string | null;
	activity_type: string | null;
	metadata: Record<string, unknown> | null;
}

/// The catalogue strings the stats are labelled with, resolved by the caller
/// so this module stays free of the i18n runtime.
export interface RunShareStatLabels {
	distance: string;
	pace: string;
	speed: string;
	time: string;
	climb: string;
	heartRate: string;
	bpm: string;
}

const METRES_PER_MILE = 1609.344;

/// The moving time every share image prints, in whole seconds: the moving
/// time of the stored track, or the elapsed duration when there is no track
/// to measure it from.
export function runShareMovingSeconds(run: ShareableRun): number {
	const track = run.track ?? [];
	if (track.length < 2) return run.duration_s;
	const computed = movingTimeSeconds(track);
	return computed === 0 ? run.duration_s : computed;
}

/// Seconds per km over `movingSeconds`, or null when the run is too short to
/// carry a pace.
export function runShareMovingPace(run: ShareableRun, movingSeconds: number): number | null {
	if (run.distance_m < 10) return null;
	if (movingSeconds < 1) return null;
	return movingSeconds / (run.distance_m / 1000);
}

/// `h:mm:ss`, or `mm:ss` under an hour.
export function formatShareDuration(seconds: number): string {
	const total = Math.max(0, Math.floor(seconds));
	const h = Math.floor(total / 3600);
	const m = Math.floor(total / 60) % 60;
	const s = total % 60;
	const pad = (n: number) => String(n).padStart(2, '0');
	return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
}

/// The climb a share image prints, or null when it has none worth printing:
/// no track, or under a metre of gain. The shared helper, so the number
/// matches the climb the run's altitude series gives everywhere else.
export function runShareClimbMetres(run: ShareableRun): number | null {
	const track = run.track ?? [];
	if (track.length < 2) return null;
	const gain = computeRunElevationGain(track, run.source);
	return gain >= 1 ? gain : null;
}

/// The run's average heart rate, or null when it was not measured. A
/// suppressed or absent average is absent, never zero.
export function runShareAvgBpm(run: ShareableRun): number | null {
	const v = run.metadata?.avg_bpm;
	const bpm = typeof v === 'number' && Number.isFinite(v) ? Math.round(v) : null;
	return bpm !== null && bpm > 0 ? bpm : null;
}

/// The kinds `run` actually has a number for, in display order. Distance,
/// pace and time always; climb and heart rate only when measured, so a chip
/// for a number the run cannot print is never offered.
export function availableShareStats(run: ShareableRun): RunShareStatKind[] {
	return [
		'distance',
		'pace',
		'time',
		...(runShareClimbMetres(run) !== null ? (['climb'] as const) : []),
		...(runShareAvgBpm(run) !== null ? (['heartRate'] as const) : []),
	];
}

function distanceValue(metres: number, unit: PreferredUnit, locale: string | undefined): string {
	return formatDecimal(unit === 'mi' ? metres / METRES_PER_MILE : metres / 1000, 2, locale);
}

function paceValue(secPerKm: number | null, unit: PreferredUnit): string {
	if (secPerKm === null || !Number.isFinite(secPerKm) || secPerKm <= 0) return '--:--';
	return paceMinutesSeconds(unit === 'mi' ? secPerKm * (METRES_PER_MILE / 1000) : secPerKm);
}

function speedValue(secPerKm: number | null, unit: PreferredUnit, locale: string | undefined): string {
	if (secPerKm === null || !Number.isFinite(secPerKm) || secPerKm <= 0) return '--';
	const kmh = 3600 / secPerKm;
	return formatDecimal(unit === 'mi' ? kmh / 1.609344 : kmh, 1, locale);
}

/// The stats a share image prints for `run`, in display order: the `kinds`
/// asked for that the run has a number for. Never empty: a look whose every
/// pick is unavailable on this run falls back to distance.
export function runShareStats(
	labels: RunShareStatLabels,
	run: ShareableRun,
	unit: PreferredUnit,
	opts: { kinds?: readonly RunShareStatKind[]; locale?: string } = {},
): RunShareStat[] {
	const kinds = opts.kinds ?? ['distance', 'pace', 'time'];
	const locale = opts.locale;
	const available = availableShareStats(run);
	let chosen = RUN_SHARE_STAT_KINDS.filter((k) => kinds.includes(k) && available.includes(k));
	if (chosen.length === 0) chosen = ['distance'];

	const moving = runShareMovingSeconds(run);
	const pace = runShareMovingPace(run, moving);
	const usesSpeed = activityUsesSpeed(run.activity_type);
	const stat = (kind: RunShareStatKind): RunShareStat => {
		switch (kind) {
			case 'distance':
				return {
					kind,
					label: labels.distance,
					value: distanceValue(run.distance_m, unit, locale),
					unit: unit === 'mi' ? 'mi' : 'km',
				};
			case 'pace':
				return usesSpeed
					? { kind, label: labels.speed, value: speedValue(pace, unit, locale), unit: unit === 'mi' ? 'mph' : 'km/h' }
					: { kind, label: labels.pace, value: paceValue(pace, unit), unit: unit === 'mi' ? '/mi' : '/km' };
			case 'time':
				return { kind, label: labels.time, value: formatShareDuration(moving), unit: null };
			case 'climb':
				return {
					kind,
					label: labels.climb,
					value: formatElevationValue(runShareClimbMetres(run) as number, unit, locale),
					unit: unit === 'mi' ? 'ft' : 'm',
				};
			case 'heartRate':
				return { kind, label: labels.heartRate, value: String(runShareAvgBpm(run)), unit: labels.bpm };
		}
	};
	return chosen.map(stat);
}
