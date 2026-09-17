import type { TrackPoint } from '../types';
import { elevationSeries } from '../runs/key_stats';
import { minMax } from '../util/min_max';

export interface RouteElevation {
	/** The route row's stored total ascent — the only climb figure a route page states. */
	gain: number;
	/** The profile drawn from the waypoints, 1:1 with them, or null when there is none to draw. */
	profile: number[] | null;
	min: number | null;
	max: number | null;
	/** Total descent, or null when it cannot be stated consistently with `gain`. */
	loss: number | null;
}

/**
 * The elevation a route page reports, from one source for the climb.
 *
 * A route row's `elevation_m` was measured when the route was saved, over the
 * densest data there was: the raw GPS track behind a saved run
 * (`computeElevationGain`, which is documented to read a hill as flat over a
 * simplified polyline), the full GPX, or the builder's sampled terrain. Its
 * `waypoints` are not that data. A run saved as a route keeps an
 * RDP-simplified line, and a non-owner sees a privacy-clipped one, so a climb
 * summed over them states a second, smaller number for the same route — which
 * is how one page came to read `ELEVATION GAIN 320 m` above `GAIN 100 m`.
 *
 * The waypoints still draw the profile, and its extremes are the chart's own.
 * Descent has no stored figure, so it is stated through the identity every
 * climb and descent over one line obey — descent = climb − (end − start) —
 * using the stored climb and the profile's endpoints, which simplification
 * keeps. Summing the simplified line instead would under-read the descent
 * exactly as it under-read the climb. When the two sources disagree so badly
 * that the identity goes negative, no descent is stated at all.
 */
export function routeElevation(storedGainM: number, waypoints: TrackPoint[]): RouteElevation {
	const gain = Math.round(storedGainM);
	const series = elevationSeries(waypoints);
	const extent = series ? minMax(series) : null;
	if (!series || !extent || extent.max === extent.min) {
		return { gain, profile: null, min: null, max: null, loss: null };
	}
	const net = series[series.length - 1] - series[0];
	const loss = Math.round(storedGainM - net);
	return {
		gain,
		profile: series,
		min: Math.round(extent.min),
		max: Math.round(extent.max),
		loss: loss >= 0 ? loss : null,
	};
}
