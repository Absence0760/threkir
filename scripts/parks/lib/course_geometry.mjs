// Pure geometry for the park-course pipeline (issue #1313, phase 3): turn the
// OSM ways a course spec names into one ordered, oriented course line, then
// measure it, place its checkpoints and check it against the park's own
// published distance. No I/O here, so `build.mjs` is deterministic and every
// rule is unit-tested in `course_geometry.test.mjs`.

/** @typedef {{ lat: number, lon: number, ele?: number | null }} SnapshotNode */
/** @typedef {{ id: number, nodes: number[] }} SnapshotWay */
/** @typedef {{ lat: number, lng: number, ele?: number | null }} LatLng */

const EARTH_RADIUS_M = 6371008.8;

/**
 * Mirrors `ELEVATION_GAIN_MIN_DELTA_M` in apps/web/src/lib/routes/route_simplify.ts,
 * so a course's gain is counted the way a saved route's is.
 */
export const ELEVATION_GAIN_MIN_DELTA_M = 3;

/** The issue's acceptance bar: within 5 % of the park's published figure. */
export const PUBLISHED_DISTANCE_TOLERANCE = 0.05;

/**
 * @param {{ lat: number, lng: number }} a
 * @param {{ lat: number, lng: number }} b
 */
export function haversineM(a, b) {
	const toRad = Math.PI / 180;
	const dLat = (b.lat - a.lat) * toRad;
	const dLng = (b.lng - a.lng) * toRad;
	const h =
		Math.sin(dLat / 2) ** 2 +
		Math.cos(a.lat * toRad) * Math.cos(b.lat * toRad) * Math.sin(dLng / 2) ** 2;
	return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

/** @param {LatLng[]} points */
export function pathLengthM(points) {
	let total = 0;
	for (let i = 1; i < points.length; i++) total += haversineM(points[i - 1], points[i]);
	return total;
}

/**
 * @param {SnapshotWay[]} ways
 * @returns {Map<number, Set<number>>}
 */
function adjacency(ways) {
	/** @type {Map<number, Set<number>>} */
	const adj = new Map();
	const link = (/** @type {number} */ a, /** @type {number} */ b) => {
		if (!adj.has(a)) adj.set(a, new Set());
		/** @type {Set<number>} */ (adj.get(a)).add(b);
	};
	for (const way of ways) {
		for (let i = 1; i < way.nodes.length; i++) {
			const a = way.nodes[i - 1];
			const b = way.nodes[i];
			if (a === b) continue;
			link(a, b);
			link(b, a);
		}
	}
	return adj;
}

/**
 * Signed area of a closed ring in degrees², positive when the ring runs
 * counterclockwise on a north-up map.
 *
 * @param {number[]} ring
 * @param {Record<string, SnapshotNode>} nodes
 */
function signedArea(ring, nodes) {
	let sum = 0;
	for (let i = 0; i < ring.length; i++) {
		const p = nodes[String(ring[i])];
		const q = nodes[String(ring[(i + 1) % ring.length])];
		sum += p.lon * q.lat - q.lon * p.lat;
	}
	return sum / 2;
}

/**
 * The node sequence of a loop course: from `start`, out along the spur (if
 * the start is off the loop, e.g. at a trailhead), once around the loop in
 * `direction`, and back down the spur to `start`.
 *
 * The named ways must form exactly ONE cycle once dead ends (piers, spurs to
 * overlooks) are pruned, and the start must reach it along a single path.
 * Anything else is ambiguous, and an ambiguous course is refused rather than
 * guessed: the spec then has to name fewer ways.
 *
 * @param {{
 *   ways: SnapshotWay[],
 *   nodes: Record<string, SnapshotNode>,
 *   start: number,
 *   direction: 'clockwise' | 'counterclockwise',
 * }} input
 * @returns {number[]}
 */
export function traceLoop({ ways, nodes, start, direction }) {
	const adj = adjacency(ways);
	if (!adj.has(start)) throw new Error(`start node ${start} is not on any named way`);

	/** @type {Map<number, Set<number>>} */
	const core = new Map([...adj].map(([k, v]) => [k, new Set(v)]));
	let pruned = true;
	while (pruned) {
		pruned = false;
		for (const [k, v] of core) {
			if (v.size < 2) {
				for (const n of v) core.get(n)?.delete(k);
				core.delete(k);
				pruned = true;
			}
		}
	}
	if (core.size === 0) throw new Error('the named ways form no loop');
	const branching = [...core].filter(([, v]) => v.size !== 2).map(([k]) => k);
	if (branching.length > 0) {
		throw new Error(
			`the named ways form more than one loop (junction nodes ${branching.join(', ')}); name only the ways of one loop`,
		);
	}

	/** @type {Map<number, number | null>} */
	const prev = new Map([[start, null]]);
	const queue = [start];
	/** @type {number | null} */
	let junction = core.has(start) ? start : null;
	while (junction === null && queue.length > 0) {
		const u = /** @type {number} */ (queue.shift());
		for (const v of /** @type {Set<number>} */ (adj.get(u))) {
			if (prev.has(v)) continue;
			prev.set(v, u);
			if (core.has(v)) {
				junction = v;
				break;
			}
			queue.push(v);
		}
	}
	if (junction === null) throw new Error(`start node ${start} does not reach the loop`);

	/** @type {number[]} */
	const spur = [];
	for (let n = /** @type {number | null} */ (junction); n !== null; n = prev.get(n) ?? null) {
		spur.unshift(n);
	}

	const ring = [junction];
	let before = junction;
	let current = [.../** @type {Set<number>} */ (core.get(junction))][0];
	while (current !== junction) {
		ring.push(current);
		const next = [.../** @type {Set<number>} */ (core.get(current))].find((n) => n !== before);
		before = current;
		current = /** @type {number} */ (next);
	}
	const isCounterclockwise = signedArea(ring, nodes) > 0;
	if (isCounterclockwise !== (direction === 'counterclockwise')) {
		ring.splice(1, ring.length - 1, ...ring.slice(1).reverse());
	}

	return [...spur.slice(0, -1), ...ring, junction, ...spur.slice(0, -1).reverse()];
}

/**
 * @param {number[]} sequence
 * @param {Record<string, SnapshotNode>} nodes
 * @returns {LatLng[]}
 */
export function toPoints(sequence, nodes) {
	return sequence.map((id) => {
		const n = nodes[String(id)];
		if (!n) throw new Error(`node ${id} is missing from the snapshot`);
		return { lat: n.lat, lng: n.lon, ele: n.ele ?? null };
	});
}

/**
 * Hysteresis gain over the RAW line, same rule as the web's
 * `computeElevationGain`: a change smaller than the band is noise.
 *
 * @param {LatLng[]} points
 */
export function elevationGainM(points, minDeltaM = ELEVATION_GAIN_MIN_DELTA_M) {
	let gain = 0;
	/** @type {number | null} */
	let ref = null;
	for (const p of points) {
		if (p.ele == null) continue;
		if (ref === null) {
			ref = p.ele;
			continue;
		}
		const delta = p.ele - ref;
		if (delta >= minDeltaM) {
			gain += delta;
			ref = p.ele;
		} else if (delta <= -minDeltaM) {
			ref = p.ele;
		}
	}
	return gain;
}

/**
 * Ramer-Douglas-Peucker in a local equirectangular projection. Elevation is
 * carried on the kept points; gain must be measured before this runs.
 *
 * @param {LatLng[]} points
 * @param {number} epsilonM
 * @returns {LatLng[]}
 */
export function simplify(points, epsilonM) {
	if (points.length < 3) return [...points];
	const lat0 = (points.reduce((s, p) => s + p.lat, 0) / points.length) * (Math.PI / 180);
	const xy = points.map((p) => [
		p.lng * (Math.PI / 180) * Math.cos(lat0) * EARTH_RADIUS_M,
		p.lat * (Math.PI / 180) * EARTH_RADIUS_M,
	]);
	const keep = new Array(points.length).fill(false);
	keep[0] = true;
	keep[points.length - 1] = true;
	/** @type {Array<[number, number]>} */
	const stack = [[0, points.length - 1]];
	while (stack.length > 0) {
		const [lo, hi] = /** @type {[number, number]} */ (stack.pop());
		const [ax, ay] = xy[lo];
		const [bx, by] = xy[hi];
		const dx = bx - ax;
		const dy = by - ay;
		const len2 = dx * dx + dy * dy;
		let worst = -1;
		let worstDist = 0;
		for (let i = lo + 1; i < hi; i++) {
			const [px, py] = xy[i];
			const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
			const d = Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
			if (d > worstDist) {
				worstDist = d;
				worst = i;
			}
		}
		if (worst !== -1 && worstDist > epsilonM) {
			keep[worst] = true;
			stack.push([lo, worst], [worst, hi]);
		}
	}
	return points.filter((_, i) => keep[i]);
}

/**
 * Evenly spaced points along the course, by distance, excluding the start
 * and finish (the matcher already requires those). With three, a loop's
 * runner must pass the quarter, half and three-quarter marks in order, so no
 * cut across the middle earns a time.
 *
 * @param {LatLng[]} points
 * @param {number} count
 * @returns {Array<{ lat: number, lng: number }>}
 */
export function placeCheckpoints(points, count) {
	const total = pathLengthM(points);
	/** @type {Array<{ lat: number, lng: number }>} */
	const out = [];
	let walked = 0;
	let i = 1;
	for (let k = 1; k <= count; k++) {
		const target = (total * k) / (count + 1);
		while (i < points.length) {
			const step = haversineM(points[i - 1], points[i]);
			if (walked + step >= target) {
				const t = step === 0 ? 0 : (target - walked) / step;
				out.push({
					lat: round6(points[i - 1].lat + t * (points[i].lat - points[i - 1].lat)),
					lng: round6(points[i - 1].lng + t * (points[i].lng - points[i - 1].lng)),
				});
				break;
			}
			walked += step;
			i++;
		}
	}
	return out;
}

/**
 * @param {number} measuredM
 * @param {number} publishedM
 */
export function distanceDeviation(measuredM, publishedM) {
	return (measuredM - publishedM) / publishedM;
}

/** @param {number} x */
export function round6(x) {
	return Math.round(x * 1e6) / 1e6;
}
