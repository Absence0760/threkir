import { haversineMetres } from '#lib/routes/nearest_track_point.ts';
import { courseDistanceScale } from '#lib/routes/official_distance.ts';

export const METRES_PER_MILE = 1609.344;

export interface DistanceMarkerProps {
	label: string;
	rank: number;
}

/// Which km / mile badges survive when the map is too zoomed out to show
/// them all: every 10th first, then every 5th, then the even ones, then the
/// rest. Lower ranks are placed first. Mirrors `distanceMarkerRank` in
/// `apps/mobile_android/lib/widgets/track_decorations.dart`.
export function distanceMarkerRank(label: number): number {
	if (label % 10 === 0) return 0;
	if (label % 5 === 0) return 1;
	if (label % 2 === 0) return 2;
	return 3;
}

/// Walk the polyline and emit a point at every [stepM] boundary, labelled
/// 1, 2, 3 … and ranked by `distanceMarkerRank`. When the authoritative
/// [totalDistanceM] is meaningfully greater than the polyline (sparse user
/// clicks / seed data), each marker's position along the polyline is scaled
/// by `polyline / real` so the count reflects the real distance. A route's
/// [officialDistanceM] wins over both, short or long, so km 42 of a traced
/// marathon sits where the race's sign does (`courseDistanceScale`). Mirrors
/// `computeDistanceMarkers` in `track_decorations.dart`.
export function computeDistanceMarkers(
	coords: [number, number][],
	stepM: number,
	totalDistanceM?: number | null,
	officialDistanceM?: number | null,
): GeoJSON.FeatureCollection<GeoJSON.Point, DistanceMarkerProps> {
	const features: GeoJSON.Feature<GeoJSON.Point, DistanceMarkerProps>[] = [];
	if (coords.length < 2) return { type: 'FeatureCollection', features };

	let polylineTotal = 0;
	for (let i = 1; i < coords.length; i++) {
		polylineTotal += haversineMetres(coords[i - 1], coords[i]);
	}
	const realTotal =
		totalDistanceM && totalDistanceM > polylineTotal * 1.1 ? totalDistanceM : polylineTotal;
	const scale =
		officialDistanceM != null && officialDistanceM > 0
			? 1 / courseDistanceScale(polylineTotal, officialDistanceM)
			: polylineTotal > 0
				? polylineTotal / realTotal
				: 1;

	let cumulative = 0;
	let nextMarker = stepM * scale;
	for (let i = 1; i < coords.length; i++) {
		const segmentM = haversineMetres(coords[i - 1], coords[i]);
		while (
			cumulative + segmentM >= nextMarker &&
			segmentM > 0 &&
			nextMarker <= polylineTotal + 0.5
		) {
			const t = (nextMarker - cumulative) / segmentM;
			const lng = coords[i - 1][0] + (coords[i][0] - coords[i - 1][0]) * t;
			const lat = coords[i - 1][1] + (coords[i][1] - coords[i - 1][1]) * t;
			const idx = Math.round(nextMarker / scale / stepM);
			features.push({
				type: 'Feature',
				geometry: { type: 'Point', coordinates: [lng, lat] },
				properties: { label: String(idx), rank: distanceMarkerRank(idx) },
			});
			nextMarker += stepM * scale;
		}
		cumulative += segmentM;
	}
	return { type: 'FeatureCollection', features };
}
