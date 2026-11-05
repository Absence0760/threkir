// A route's official (certified) distance against its traced length, issue
// #1291. A course traced on street centre lines measures long, so when the
// owner records the race's own distance every surface shows that figure and
// distance along the line is scaled by official / measured, putting km 42 where
// the race's sign stands. Mirrors `official_distance.dart`.

/// The tighter bound the edit form and the race-link prefill apply; the
/// column's CHECK holds only the hard range below, because `distance_m` moves
/// whenever the owner redraws the route (migration 20271108000010).
export const OFFICIAL_DISTANCE_MAX_DEVIATION = 0.1;

/// The column CHECK's ceiling, 1,000 km.
export const OFFICIAL_DISTANCE_MAX_M = 1_000_000;

function positive(v: number | null | undefined): v is number {
	return v != null && Number.isFinite(v) && v > 0;
}

/// The distance a route is shown as: the official one when set, the measured
/// one otherwise.
export function routeDisplayDistanceM(
	measuredM: number,
	officialM: number | null | undefined,
): number {
	return positive(officialM) ? officialM : measuredM;
}

/// Official metres per metre of drawn line. Multiply a distance measured along
/// the line by this to get the distance the race would call it; divide an
/// official distance by it to find where on the line it falls. 1 when either
/// figure is missing, so a route with no official distance is unchanged.
export function courseDistanceScale(
	lineLengthM: number,
	officialM: number | null | undefined,
): number {
	return positive(lineLengthM) && positive(officialM) ? officialM / lineLengthM : 1;
}

export type OfficialDistanceVerdict = 'ok' | 'outOfRange' | 'tooFar';

/// Whether [officialM] may be saved on a route measuring [measuredM]: positive,
/// within the column's ceiling, and within 10% of the measured distance.
export function officialDistanceVerdict(measuredM: number, officialM: number): OfficialDistanceVerdict {
	if (!positive(officialM) || officialM > OFFICIAL_DISTANCE_MAX_M) return 'outOfRange';
	if (!positive(measuredM)) return 'ok';
	return Math.abs(officialM - measuredM) <= measuredM * OFFICIAL_DISTANCE_MAX_DEVIATION
		? 'ok'
		: 'tooFar';
}
