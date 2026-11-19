// Pure: how close a course's start and finish come to a road a runner should
// not end up on. Read by scripts/parks/course_end_roads.mjs, a review aid
// for step 6 of "Adding a course" in scripts/parks/README.md.
//
// Distance alone cannot tell a finish beside a road from one that runs into
// it: most of the Virginia Capital Trail sits 8-12 m from Route 5, which is
// fine, while its last node sat 5 m from Colonial Parkway with the road
// straight ahead (decisions § 2581). So each end is also measured along where
// a runner actually goes: the runout past the finish, and the waiting area
// behind the start, `RUNOUT_M` along the direction of travel, flagged only when
// that stretch reaches a roadway.

/** How far past a finish a runner slows down, and behind a start they wait. */
export const RUNOUT_M = 30;

/** Road classes a runner should not run out onto. Footways, paths, cycleways and tracks are trails. */
export const MOTOR_ROADS = Object.freeze([
	'motorway',
	'trunk',
	'primary',
	'secondary',
	'tertiary',
	'unclassified',
	'residential',
	'service',
]);

/**
 * A runout stretch that comes this close to a road's centre line runs onto
 * the roadway. Not a wider band: a trail beside a highway sits 8-12 m from it
 * for kilometres (the Capital Trail and Route 5), and that is not the problem.
 */
export const REVIEW_WITHIN_M = 3;

const R = 6371008.8;
const rad = Math.PI / 180;

/**
 * @typedef {{ lat: number, lng: number }} LatLng
 * @typedef {{ name: string | null, highway: string, line: LatLng[] }} Road
 */

/**
 * The point `distM` from `p` on `bearingDeg` (local plane; exact enough at tens of metres).
 *
 * @param {LatLng} p
 * @param {number} bearingDeg
 * @param {number} distM
 * @returns {LatLng}
 */
export function offsetPoint(p, bearingDeg, distM) {
	const b = bearingDeg * rad;
	return {
		lat: p.lat + (distM * Math.cos(b)) / R / rad,
		lng: p.lng + (distM * Math.sin(b)) / (R * Math.cos(p.lat * rad)) / rad,
	};
}

/**
 * Compass bearing from `a` to `b`, degrees clockwise from north.
 *
 * @param {LatLng} a
 * @param {LatLng} b
 */
export function bearingDeg(a, b) {
	const dx = (b.lng - a.lng) * Math.cos(a.lat * rad);
	const dy = b.lat - a.lat;
	return ((Math.atan2(dx, dy) / rad) % 360 + 360) % 360;
}

/**
 * Metres from `p` to the nearest point of a polyline.
 *
 * @param {LatLng} p
 * @param {LatLng[]} line
 */
export function distanceToLineM(p, line) {
	const k = Math.cos(p.lat * rad) * R * rad;
	const m = R * rad;
	let best = Infinity;
	for (let i = 1; i < line.length; i++) {
		const ax = (line[i - 1].lng - p.lng) * k;
		const ay = (line[i - 1].lat - p.lat) * m;
		const bx = (line[i].lng - p.lng) * k;
		const by = (line[i].lat - p.lat) * m;
		const dx = bx - ax;
		const dy = by - ay;
		const len2 = dx * dx + dy * dy;
		const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / len2));
		best = Math.min(best, Math.hypot(ax + t * dx, ay + t * dy));
	}
	return best;
}

/**
 * The nearest motor road to `p`, or null when there is none in `roads`.
 *
 * @param {LatLng} p
 * @param {Road[]} roads
 * @returns {{ road: Road, m: number } | null}
 */
export function nearestRoad(p, roads) {
	/** @type {{ road: Road, m: number } | null} */
	let best = null;
	for (const road of roads) {
		if (!MOTOR_ROADS.includes(road.highway.replace(/_link$/, ''))) continue;
		const m = distanceToLineM(p, road.line);
		if (!best || m < best.m) best = { road, m };
	}
	return best;
}

/**
 * One course end, measured at the end itself and at its runout: `RUNOUT_M`
 * past a finish in the direction of travel, or behind a start against it.
 * `line` is the course line in running order.
 *
 * @param {LatLng[]} line
 * @param {'start' | 'finish'} which
 * @param {Road[]} roads
 */
export function endReport(line, which, roads) {
	const end = which === 'start' ? line[0] : line[line.length - 1];
	// The course's direction over its first or last 25 m, the same span the
	// database aims the end's timing line along.
	const ref = which === 'start' ? pointAlong(line, 25) : pointAlong([...line].reverse(), 25);
	const travel = which === 'start' ? bearingDeg(end, ref) : bearingDeg(ref, end);
	const away = which === 'start' ? travel + 180 : travel;
	const runout = offsetPoint(end, away, RUNOUT_M);
	const atEnd = nearestRoad(end, roads);
	// The closest the runout stretch comes to a road, sampled every metre, so
	// a road crossing between the line and the runout's far end is not missed.
	/** @type {{ road: Road, m: number } | null} */
	let atRunout = null;
	for (let d = 0; d <= RUNOUT_M; d++) {
		const hit = nearestRoad(offsetPoint(end, away, d), roads);
		if (hit && (!atRunout || hit.m < atRunout.m)) atRunout = hit;
	}
	return {
		which,
		end,
		runout,
		atEnd,
		atRunout,
		review: atRunout !== null && atRunout.m < REVIEW_WITHIN_M,
	};
}

/**
 * @param {LatLng[]} line
 * @param {number} m
 * @returns {LatLng}
 */
function pointAlong(line, m) {
	let walked = 0;
	for (let i = 1; i < line.length; i++) {
		const step = Math.hypot(
			(line[i].lng - line[i - 1].lng) * Math.cos(line[i - 1].lat * rad) * R * rad,
			(line[i].lat - line[i - 1].lat) * R * rad,
		);
		if (walked + step >= m) {
			const t = step === 0 ? 0 : (m - walked) / step;
			return { lat: line[i - 1].lat + t * (line[i].lat - line[i - 1].lat), lng: line[i - 1].lng + t * (line[i].lng - line[i - 1].lng) };
		}
		walked += step;
	}
	return line[line.length - 1];
}
