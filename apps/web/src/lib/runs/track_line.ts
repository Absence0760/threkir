// Where the run line, a route match or a hop-sum along the line places a
// stored track fix: the GPS distance smoother's position when the saved track
// carries both halves of it (docs/features/gps_distance.md § Waypoint fields),
// else the raw fix. Never an estimator input: the estimator always takes the
// raw `lat` / `lng`. Mirrors `Waypoint.lineLat` / `lineLng` in
// packages/core_models/lib/src/waypoint.dart.

export type LinePointSource = {
	lat: number;
	lng: number;
	smoothedLat?: number | null;
	smoothedLng?: number | null;
};

function finite(v: unknown): v is number {
	return typeof v === 'number' && Number.isFinite(v);
}

/** Whether the fix carries a usable smoothed position. */
export function hasSmoothedPosition(p: LinePointSource): boolean {
	return finite(p.smoothedLat) && finite(p.smoothedLng);
}

export function lineLat(p: LinePointSource): number {
	return hasSmoothedPosition(p) ? (p.smoothedLat as number) : p.lat;
}

export function lineLng(p: LinePointSource): number {
	return hasSmoothedPosition(p) ? (p.smoothedLng as number) : p.lng;
}

/** `[lng, lat]` of the line position, the GeoJSON / MapLibre order. */
export function lineLngLat(p: LinePointSource): [number, number] {
	return hasSmoothedPosition(p)
		? [p.smoothedLng as number, p.smoothedLat as number]
		: [p.lng, p.lat];
}

/** The fix with its line position as `lat` / `lng`, for helpers that read only those. */
export function toLinePoint<T extends LinePointSource>(p: T): T {
	return hasSmoothedPosition(p) ? { ...p, lat: p.smoothedLat as number, lng: p.smoothedLng as number } : p;
}
