// Pure geometry for the park-course pipeline (issue #1313, phase 3): turn the
// OSM ways a course spec names into one ordered, oriented course line, then
// measure it, place its checkpoints and check it against the park's own
// published distance. No I/O here, so `build.mjs` is deterministic and every
// rule is unit-tested in `course_geometry.test.mjs`.

/** @typedef {{ lat: number, lon: number, ele?: number | null }} SnapshotNode */
/** @typedef {{ id: number, nodes: number[], tags?: Record<string, string> }} SnapshotWay */
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
 * Why a way is not open to people on foot, as the tags that say so, or null
 * when it is. A course over a social trail or a bike-only trail sends runners
 * where the land manager forbids them (Virginia state parks: 4VAC5-30-274).
 * `foot=yes` or `foot=designated` overrides a general `access=no`, which is
 * how OSM marks a foot-only trail.
 *
 * @param {Record<string, string>} tags
 * @returns {string | null}
 */
export function footAccessRefusal(tags) {
	const footOpen = tags.foot === 'yes' || tags.foot === 'designated';
	/** @type {string[]} */
	const reasons = [];
	if (tags.informal === 'yes') reasons.push('informal=yes');
	if (tags.foot === 'no' || tags.foot === 'private') reasons.push(`foot=${tags.foot}`);
	if (!footOpen && (tags.access === 'no' || tags.access === 'private')) reasons.push(`access=${tags.access}`);
	if (!footOpen && tags.highway === 'cycleway') reasons.push('highway=cycleway');
	if (!footOpen && tags.mtb === 'designated') reasons.push('mtb=designated');
	if (tags.bicycle === 'designated' && tags.foot === 'no') reasons.push('bicycle=designated');
	return reasons.length > 0 ? reasons.join(', ') : null;
}

/**
 * Refuse a traced course whose line runs along any way that is not open on
 * foot. Only the ways the sequence actually walks are checked, so a listed
 * way the trace never uses (a pruned spur) does not block the course.
 *
 * @param {number[]} sequence
 * @param {SnapshotWay[]} ways
 */
export function assertFootAccess(sequence, ways) {
	/** @type {Map<string, SnapshotWay[]>} */
	const byEdge = new Map();
	for (const way of ways) {
		for (let i = 1; i < way.nodes.length; i++) {
			const key = edgeKey(way.nodes[i - 1], way.nodes[i]);
			const list = byEdge.get(key);
			if (list) list.push(way);
			else byEdge.set(key, [way]);
		}
	}
	/** @type {Set<SnapshotWay>} */
	const walked = new Set();
	for (let i = 1; i < sequence.length; i++) {
		for (const way of byEdge.get(edgeKey(sequence[i - 1], sequence[i])) ?? []) walked.add(way);
	}
	const refused = [...walked]
		.map((way) => ({ way, reason: footAccessRefusal(way.tags ?? {}) }))
		.filter((r) => r.reason !== null)
		.sort((a, b) => a.way.id - b.way.id);
	if (refused.length > 0) {
		throw new Error(
			`the course runs on way(s) not open to people on foot: ${refused
				.map(({ way, reason }) => `way ${way.id} (${reason})`)
				.join('; ')}; reroute it onto designated trails`,
		);
	}
}

/**
 * @param {number} a
 * @param {number} b
 */
function edgeKey(a, b) {
	return a < b ? `${a}-${b}` : `${b}-${a}`;
}

/** Race distances in metres, by the slug a race course spec names. */
export const RACE_DISTANCES_M = Object.freeze({
	'5k': 5000,
	'10k': 10000,
	half: 21097.5,
	marathon: 42195,
	'50k': 50000,
});

/**
 * The node path through `via`, in order, along the named ways only: the
 * shortest path between each consecutive pair. A race course reuses parts of
 * long OSM ways that branch everywhere, so unlike `traceLoop` it cannot be
 * "the one cycle these ways form"; the spec pins the route with via nodes
 * instead, close enough together that each hop has one obvious path.
 *
 * @param {{ ways: SnapshotWay[], nodes: Record<string, SnapshotNode>, via: number[] }} input
 * @returns {number[]}
 */
export function traceVia({ ways, nodes, via }) {
	if (via.length < 2) throw new Error('a via route needs at least two nodes');
	const adj = adjacency(ways);
	const pos = (/** @type {number} */ id) => {
		const n = nodes[String(id)];
		if (!n) throw new Error(`node ${id} is missing from the snapshot`);
		return { lat: n.lat, lng: n.lon };
	};
	/** @type {number[]} */
	const out = [via[0]];
	for (let i = 1; i < via.length; i++) {
		const from = via[i - 1];
		const to = via[i];
		if (from === to) continue;
		if (!adj.has(from)) throw new Error(`via node ${from} is not on any named way`);
		if (!adj.has(to)) throw new Error(`via node ${to} is not on any named way`);
		/** @type {Map<number, number>} */
		const dist = new Map([[from, 0]]);
		/** @type {Map<number, number>} */
		const prev = new Map();
		const done = new Set();
		// The graphs here are a few hundred nodes, so a linear-scan frontier is fine.
		const frontier = new Set([from]);
		while (frontier.size > 0) {
			let u = -1;
			let best = Infinity;
			for (const n of frontier) {
				const d = /** @type {number} */ (dist.get(n));
				if (d < best) {
					best = d;
					u = n;
				}
			}
			frontier.delete(u);
			if (u === to) break;
			done.add(u);
			for (const v of /** @type {Set<number>} */ (adj.get(u))) {
				if (done.has(v)) continue;
				const nd = best + haversineM(pos(u), pos(v));
				if (nd < (dist.get(v) ?? Infinity)) {
					dist.set(v, nd);
					prev.set(v, u);
					frontier.add(v);
				}
			}
		}
		if (!dist.has(to)) throw new Error(`via node ${to} is not reachable from ${from} along the named ways`);
		/** @type {number[]} */
		const hop = [];
		for (let n = to; n !== from; n = /** @type {number} */ (prev.get(n))) hop.unshift(n);
		out.push(...hop);
	}
	return out;
}

/**
 * A lap race: out along the lead-in, `laps` times round the loop, and back
 * along the lead-in. `loop` starts and ends on the node where the lead-in
 * meets it.
 *
 * @param {{ leadIn: number[], loop: number[], laps: number }} input
 * @returns {number[]}
 */
export function lapCourse({ leadIn, loop, laps }) {
	if (!Number.isInteger(laps) || laps < 1) throw new Error(`laps must be a positive integer, got ${laps}`);
	const junction = leadIn[leadIn.length - 1];
	if (loop[0] !== junction || loop[loop.length - 1] !== junction) {
		throw new Error(`the loop must start and end where the lead-in ends (node ${junction})`);
	}
	/** @type {number[]} */
	const out = [...leadIn];
	for (let i = 0; i < laps; i++) out.push(...loop.slice(1));
	out.push(...leadIn.slice(0, -1).reverse());
	return out;
}

/**
 * Mirrors `c_along` in `private.course_end_bearing` (migration
 * 20271116002390): the global segment gate trigger aims each line at the
 * point this far along the course. `course_geometry.test.mjs` reads the
 * migration and fails when the two disagree.
 */
export const GATE_BEARING_LOOK_AHEAD_M = 25;

/**
 * How close a race course's start line may sit to the loop. Any closer and the
 * trigger's look-ahead point lands on the loop, so the line is skewed off the
 * lead-in (the half's came out 56 degrees off at 9 m).
 */
export const START_LINE_MIN_FROM_LOOP_M = GATE_BEARING_LOOK_AHEAD_M + 5;

/**
 * The polyline between `fromM` and `toM` metres along `points`, with the cut
 * ends interpolated.
 *
 * @param {LatLng[]} points
 * @param {number} fromM
 * @param {number} toM
 * @returns {LatLng[]}
 */
export function slice(points, fromM, toM) {
	/** @type {LatLng[]} */
	const out = [];
	let walked = 0;
	for (let i = 1; i < points.length; i++) {
		const a = points[i - 1];
		const b = points[i];
		const step = haversineM(a, b);
		const at = (/** @type {number} */ m) => {
			const t = step === 0 ? 0 : (m - walked) / step;
			const ele = a.ele != null && b.ele != null ? a.ele + t * (b.ele - a.ele) : (a.ele ?? null);
			return { lat: a.lat + t * (b.lat - a.lat), lng: a.lng + t * (b.lng - a.lng), ele };
		};
		if (out.length === 0 && walked + step >= fromM) out.push(at(fromM));
		if (walked + step >= toM) {
			out.push(at(toM));
			return out;
		}
		if (out.length > 0) out.push(b);
		walked += step;
	}
	return out;
}

/**
 * Cut the same length off both ends of an out-and-back lead-in course so it
 * measures exactly `targetM`, which puts the shared start/finish line on the
 * lead-in. Refused when the course is already short, when the cut would
 * reach past the lead-in onto the loop (the start would then sit mid-lap), or
 * when it would leave the start line closer to the loop than
 * `START_LINE_MIN_FROM_LOOP_M`.
 *
 * @param {LatLng[]} points
 * @param {number} targetM
 * @param {number} leadInM
 * @returns {{ points: LatLng[], trimEachEndM: number }}
 */
export function trimToDistance(points, targetM, leadInM) {
	const total = pathLengthM(points);
	if (total < targetM) {
		throw new Error(`course is ${total.toFixed(1)} m, short of ${targetM} m; lengthen the lead-in`);
	}
	const trim = (total - targetM) / 2;
	if (trim > leadInM) {
		throw new Error(
			`course is ${(total - targetM).toFixed(1)} m too long; the start line would sit ${trim.toFixed(1)} m in, past the ${leadInM.toFixed(1)} m lead-in`,
		);
	}
	const fromLoopM = leadInM - trim;
	if (fromLoopM < START_LINE_MIN_FROM_LOOP_M) {
		throw new Error(
			`the start line would sit ${fromLoopM.toFixed(1)} m from the loop, under the ${START_LINE_MIN_FROM_LOOP_M} m the gate trigger needs to take its bearing on the lead-in; shorten the loop`,
		);
	}
	return { points: slice(points, trim, total - trim), trimEachEndM: trim };
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
