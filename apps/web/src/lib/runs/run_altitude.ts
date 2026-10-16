import type { TrackPoint } from '../types';
import { computeElevationGain, ELEVATION_GAIN_MIN_DELTA_M } from '../routes/route_simplify';
import { trackLine } from './track_line';

/**
 * Which altitude a recorded run's climb and elevation profile are read from,
 * and the noise band the climb is gated on. Twin of `run_altitude.dart` in
 * `apps/mobile_android/lib/`; keep in lockstep (docs/architecture/parity_pairs.md).
 *
 * Three cases, in order:
 *
 * 1. Any point carries `baroEle` — the phone barometer, anchored to GPS
 *    altitude by the recorder (docs/features/run_recording.md § Barometric
 *    altitude). The run is read off that series alone at the route band
 *    [ELEVATION_GAIN_MIN_DELTA_M]: a barometer resolves well under a metre,
 *    so the 3 m band only has to absorb the slow anchor correction. A point
 *    without `baroEle` (before the anchor levelled, or a sensor stall) is a
 *    dropout the gain rule carries across; GPS `ele` is never spliced in,
 *    because the two series sit on different error budgets and a splice
 *    would count the step between them as climb.
 * 2. A phone-recorded run (`source === 'app'`) without one — GPS altitude
 *    from a phone with no barometer, or a run recorded before the barometer
 *    was read. Gated at [ELEVATION_GAIN_GPS_MIN_DELTA_M].
 * 3. Anything else — an import or a watch, whose `ele` may already be
 *    barometric (Garmin, Apple Watch, the custom watch) and whose device we
 *    cannot see from here — keeps the route band, exactly as before.
 *
 * Off-track fixes (`offTrack: true`, the canopy fixes the recorder stored only
 * for the distance replay) are left out of every case: `track` is the line,
 * and a 30-50 m fix's altitude is worse than its position.
 */
export interface RunAltitude {
	/** The on-track points with `ele` holding the chosen series; the input itself when GPS `ele` is the series and no point is off-track. */
	track: TrackPoint[];
	/** The noise band the climb over `track` is gated on. */
	minDeltaM: number;
	/** True when the series is the anchored barometer. */
	barometric: boolean;
}

/**
 * The band phone GPS altitude is gated on when no barometer recorded the run.
 * GPS vertical error runs at roughly 1.5x the horizontal and wanders over
 * minutes rather than flickering per fix, and under tree cover the low
 * satellites that fix the vertical drop out first, so a 10-20 m vertical
 * error is routine. The 3 m route band integrates that wander as climb; 10 m
 * is the band Strava applies to devices without a barometer, and it costs
 * only rollers under 10 m, which GPS altitude cannot resolve anyway.
 */
export const ELEVATION_GAIN_GPS_MIN_DELTA_M = 10;

/** True when any point carries a finite barometric altitude. */
export function hasBarometricAltitude(track: TrackPoint[]): boolean {
	return track.some((p) => typeof p.baroEle === 'number' && Number.isFinite(p.baroEle));
}

export function runAltitude(
	stored: TrackPoint[],
	source: string | null | undefined,
): RunAltitude {
	const track = trackLine(stored);
	if (hasBarometricAltitude(track)) {
		return {
			track: track.map((p) => {
				const out: TrackPoint = { ...p };
				if (typeof p.baroEle === 'number' && Number.isFinite(p.baroEle)) out.ele = p.baroEle;
				else delete out.ele;
				return out;
			}),
			minDeltaM: ELEVATION_GAIN_MIN_DELTA_M,
			barometric: true,
		};
	}
	return {
		track,
		minDeltaM: source === 'app' ? ELEVATION_GAIN_GPS_MIN_DELTA_M : ELEVATION_GAIN_MIN_DELTA_M,
		barometric: false,
	};
}

/** The climb of a recorded run, over the series and band [runAltitude] picks. */
export function computeRunElevationGain(
	track: TrackPoint[],
	source: string | null | undefined,
): number {
	const alt = runAltitude(track, source);
	return computeElevationGain(alt.track, alt.minDeltaM);
}
