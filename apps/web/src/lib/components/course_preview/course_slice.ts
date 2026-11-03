import { pointAtDistance, type FlyoverPath } from '#lib/routes/flyover_path.ts';

/// The stretch of the course between two distances as [lng, lat] pairs, with
/// interpolated ends, so a climb drawn over the line starts and stops exactly
/// where its numbers say rather than at the nearest recorded point.
export function sliceCourse(path: FlyoverPath, fromM: number, toM: number): [number, number][] {
	if (path.points.length < 2 || !(toM > fromM)) return [];
	const start = pointAtDistance(path, fromM);
	const end = pointAtDistance(path, toM);
	const out: [number, number][] = [[start.lng, start.lat]];
	for (let i = start.index + 1; i <= end.index; i++) {
		out.push([path.points[i].lng, path.points[i].lat]);
	}
	out.push([end.lng, end.lat]);
	return out;
}
