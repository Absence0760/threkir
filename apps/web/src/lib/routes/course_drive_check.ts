import { osrmProxyFetch } from './routing';
import {
	MAPS_WAYPOINT_CAP,
	planDriveLegs,
	undrivableStretches,
	type CourseStretch,
	type DrivePoint
} from './course_drive';

/**
 * Which stretches of the course a Maps app will not follow
 * (docs/features/course_drive.md, gotcha 4): each nine-stop leg is routed
 * through the OSRM proxy's `car` profile and the joined result is compared with
 * the course. Null when the check could not run (the proxy is signed-in only,
 * and a failed or refused call proves nothing), so the caller says it could not
 * check rather than implying the course is drivable.
 */
export async function checkDrivable(
	line: readonly DrivePoint[],
	signal?: AbortSignal
): Promise<CourseStretch[] | null> {
	const legs = planDriveLegs(line, MAPS_WAYPOINT_CAP.google);
	if (legs.length === 0) return null;
	const routed: DrivePoint[] = [];
	for (const leg of legs) {
		const coords = [leg.start, ...leg.via, leg.end]
			.map((s) => `${s.lng.toFixed(6)},${s.lat.toFixed(6)}`)
			.join(';');
		try {
			const res = await osrmProxyFetch(
				`/route/v1/car/${coords}?overview=full&geometries=geojson`,
				{ signal }
			);
			if (!res.ok) return null;
			const body = (await res.json()) as {
				routes?: { geometry?: { coordinates?: unknown } }[];
			};
			const pts = body.routes?.[0]?.geometry?.coordinates;
			if (!Array.isArray(pts)) return null;
			for (const c of pts) {
				if (Array.isArray(c) && Number.isFinite(c[0]) && Number.isFinite(c[1])) {
					routed.push({ lat: c[1] as number, lng: c[0] as number });
				}
			}
		} catch (e) {
			if (signal?.aborted) return null;
			console.warn('course drive check failed', e);
			return null;
		}
	}
	return undrivableStretches(line, routed);
}
