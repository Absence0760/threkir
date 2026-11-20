// Where a course crosses a motor road at grade, so its route guide can say
// "cross Hunter Mill Road at the signal" (decisions § 2448's guide, issue
// #1344). The course snapshot holds only the ways a course walks, so a node
// it shares with a road is invisible there; `fetch_snapshot.mjs` adds the
// roads through the course's nodes as the snapshot's `road_crossings`, and
// this module turns them into crossings.
//
// Two halves, both pure:
//   - `parseRoadCrossings` checks an Overpass response and keeps, for each
//     course node a road passes through, that road's tags and its two
//     neighbouring nodes (the road's arms), plus how far along each arm a
//     traffic signal sits. Every field is rebuilt from a checked primitive,
//     like `osm_response.mjs`, so a bad response stops the run.
//   - `roadCrossingAt` decides whether the course, entering a node from one
//     neighbour and leaving to another, crosses a road there.
//
// The rule (README "Route guides"): a road counts when its `highway` class is
// one of `MOTOR_ROADS` and cars use it. A service road counts only when it has
// a name: an unnamed driveway or parking aisle is not something a runner can
// look for, and a guide naming every one would bury the roads that matter. A
// bridge or tunnel is not at grade. The course crosses the road when the
// road's arms lie on both sides of the course's path through the node; a road
// that ends at the trail, or one the course turns onto or off, is no crossing
// (a stretch run along a road is a `road` step, which is a different thing).

import { MOTOR_ROADS } from './road_proximity.mjs';
import { haversineM } from './course_geometry.mjs';
import { MAX_TAG_LENGTH, isCoordinate, isPositiveInteger, isTagString } from './osm_response.mjs';

/** A signal this far along the road from the crossing controls it: one mapped on the junction a few metres off. */
export const ROAD_SIGNAL_NEAR_M = 15;
/** How far along each arm the fetch looks for a signal; at least `ROAD_SIGNAL_NEAR_M`. */
export const SIGNAL_SEARCH_M = 20;
/** Service roads that are never announced, even when named. */
export const UNANNOUNCED_SERVICE = Object.freeze(['driveway', 'parking_aisle', 'drive-through', 'alley', 'emergency_access']);

/** Road tags the snapshot keeps; everything else is dropped at the fetch. */
const ROAD_TAGS = Object.freeze(['highway', 'name', 'service', 'bridge', 'tunnel', 'access', 'motor_vehicle', 'motorcar', 'area']);
/** Node tags the snapshot keeps: what says whether the crossing has a signal or markings. */
const NODE_TAGS = Object.freeze(['highway', 'crossing', 'crossing:signals', 'crossing:markings']);

/** The `highway` classes the fetch asks Overpass for, as one regular expression. */
export const ROAD_HIGHWAY_PATTERN = `^(${MOTOR_ROADS.join('|')})(_link)?$`;

/**
 * @typedef {{ node: number, lat: number, lon: number, signal_m?: number }} RoadArm
 * @typedef {{ id: number, tags: Record<string, string>, arms: RoadArm[] }} CrossingRoad
 * @typedef {{ tags: Record<string, string>, roads: CrossingRoad[] }} CrossingNode
 */

/** @param {string | undefined} v */
const isOn = (v) => v !== undefined && v !== 'no';

/**
 * Whether a road's tags make it one a runner is told they cross.
 *
 * @param {Record<string, string>} tags
 */
export function crossableRoad(tags) {
	const highway = (tags.highway ?? '').replace(/_link$/, '');
	if (!MOTOR_ROADS.includes(highway)) return false;
	if (isOn(tags.bridge) || isOn(tags.tunnel) || tags.area === 'yes') return false;
	if (tags.access === 'no' || tags.motor_vehicle === 'no' || tags.motorcar === 'no') return false;
	if (highway === 'service') {
		if (!tags.name?.trim()) return false;
		if (tags.service && UNANNOUNCED_SERVICE.includes(tags.service)) return false;
	}
	return true;
}

/**
 * Whether a node's own tags put a traffic signal on it.
 *
 * @param {Record<string, string>} tags
 */
export function signalAtNode(tags) {
	return tags.highway === 'traffic_signals' || tags.crossing === 'traffic_signals' || tags['crossing:signals'] === 'yes';
}

/**
 * @param {unknown} raw
 * @param {readonly string[]} keep
 * @param {string} what
 * @returns {Record<string, string>}
 */
function checkedTags(raw, keep, what) {
	if (raw === undefined) return {};
	if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) throw new Error(`${what}: tags is not an object`);
	/** @type {Array<[string, string]>} */
	const out = [];
	for (const [key, value] of Object.entries(raw)) {
		if (!isTagString(key) || !isTagString(value)) {
			throw new Error(`${what}: tag ${JSON.stringify(key).slice(0, 40)} is not a 1-${MAX_TAG_LENGTH} character string pair`);
		}
		if (keep.includes(key)) out.push([key, value]);
	}
	out.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
	return Object.fromEntries(out);
}

/**
 * The roads through each course node, from an Overpass `[out:json]` response
 * holding the road ways (`out body`) and every node of them (`out body`).
 * Keyed by node id, in id order; a node no road passes through is absent.
 *
 * @param {unknown} body
 * @param {Iterable<number>} courseNodeIds
 * @returns {Record<string, CrossingNode>}
 */
export function parseRoadCrossings(body, courseNodeIds) {
	const elements = /** @type {{ elements?: unknown }} */ (body ?? {}).elements;
	if (!Array.isArray(elements)) throw new Error('Overpass response has no elements array');
	/** @type {Map<number, { lat: number, lon: number, tags: Record<string, string> }>} */
	const nodes = new Map();
	/** @type {Array<{ id: number, nodes: number[], tags: Record<string, string> }>} */
	const ways = [];
	for (const raw of elements) {
		if (typeof raw !== 'object' || raw === null) throw new Error('an Overpass element is not an object');
		const el = /** @type {Record<string, unknown>} */ (raw);
		if (!isPositiveInteger(el.id)) throw new Error(`${el.type} id ${JSON.stringify(el.id)} is not a positive integer`);
		if (el.type === 'node') {
			if (!isCoordinate(el.lat, 90) || !isCoordinate(el.lon, 180)) throw new Error(`node ${el.id} has no valid coordinate`);
			nodes.set(el.id, { lat: el.lat, lon: el.lon, tags: checkedTags(el.tags, NODE_TAGS, `node ${el.id}`) });
		} else if (el.type === 'way') {
			if (!Array.isArray(el.nodes) || el.nodes.length < 2 || !el.nodes.every(isPositiveInteger)) {
				throw new Error(`way ${el.id}: its node list is not two or more positive integers`);
			}
			const tags = checkedTags(el.tags, ROAD_TAGS, `way ${el.id}`);
			if (!new RegExp(ROAD_HIGHWAY_PATTERN).test(tags.highway ?? '')) continue;
			ways.push({ id: el.id, nodes: [...el.nodes], tags });
		} else {
			throw new Error(`unexpected Overpass element type ${JSON.stringify(el.type)}`);
		}
	}
	const wanted = new Set(courseNodeIds);
	/** @type {Map<number, CrossingNode>} */
	const out = new Map();
	for (const way of ways.sort((a, b) => a.id - b.id)) {
		const missing = way.nodes.filter((id) => !nodes.has(id));
		if (missing.length) throw new Error(`way ${way.id}: response omits node(s) ${missing.slice(0, 5).join(', ')}`);
		const closed = way.nodes.length > 2 && way.nodes[0] === way.nodes[way.nodes.length - 1];
		const ring = closed ? way.nodes.slice(0, -1) : way.nodes;
		ring.forEach((id, k) => {
			if (!wanted.has(id)) return;
			const node = /** @type {{ lat: number, lon: number, tags: Record<string, string> }} */ (nodes.get(id));
			/** @type {RoadArm[]} */
			const arms = [];
			for (const dir of [-1, 1]) {
				const next = closed ? (k + dir + ring.length) % ring.length : k + dir;
				if (next < 0 || next >= ring.length || ring[next] === id) continue;
				const n = /** @type {{ lat: number, lon: number }} */ (nodes.get(ring[next]));
				/** @type {RoadArm} */
				const arm = { node: ring[next], lat: n.lat, lon: n.lon };
				let walked = 0;
				let prev = node;
				for (let j = next, steps = 0; steps < ring.length; steps++) {
					if (j < 0 || j >= ring.length) break;
					const here = /** @type {{ lat: number, lon: number, tags: Record<string, string> }} */ (nodes.get(ring[j]));
					walked += haversineM({ lat: prev.lat, lng: prev.lon }, { lat: here.lat, lng: here.lon });
					if (walked > SIGNAL_SEARCH_M || ring[j] === id) break;
					if (signalAtNode(here.tags)) {
						arm.signal_m = Math.round(walked);
						break;
					}
					prev = here;
					j = closed ? (j + dir + ring.length) % ring.length : j + dir;
				}
				arms.push(arm);
			}
			if (arms.length === 0) return;
			const entry = out.get(id) ?? { tags: node.tags, roads: [] };
			entry.roads.push({ id: way.id, tags: way.tags, arms });
			out.set(id, entry);
		});
	}
	return Object.fromEntries([...out.entries()].sort(([a], [b]) => a - b).map(([id, v]) => [String(id), v]));
}

/**
 * Compass bearing from `a` to `b` on a local plane, degrees clockwise from north.
 *
 * @param {{ lat: number, lon: number }} a
 * @param {{ lat: number, lon: number }} b
 */
function bearing(a, b) {
	const dx = (b.lon - a.lon) * Math.cos((a.lat * Math.PI) / 180);
	const dy = b.lat - a.lat;
	return ((Math.atan2(dx, dy) * 180) / Math.PI + 360) % 360;
}

/**
 * Whether `x` lies on the clockwise sweep from `from` to `to`.
 *
 * @param {number} from @param {number} to @param {number} x
 */
function clockwiseBetween(from, to, x) {
	const span = (to - from + 360) % 360;
	const at = (x - from + 360) % 360;
	return at > 0 && at < span;
}

/** @param {string} highway */
const classRank = (highway) => MOTOR_ROADS.indexOf(highway.replace(/_link$/, ''));

/**
 * The road the course crosses at a node, entering from `prev` and leaving to
 * `next`, or null when it crosses none there. `name` is the road's OSM name,
 * or null for an unnamed road; `signal` is whether OSM puts a traffic signal
 * on the crossing (on the node, or within `ROAD_SIGNAL_NEAR_M` along the road).
 *
 * @param {CrossingNode | undefined} entry the snapshot's `road_crossings.nodes[id]`
 * @param {{ lat: number, lon: number }} here
 * @param {{ id: number, lat: number, lon: number }} prev
 * @param {{ id: number, lat: number, lon: number }} next
 * @returns {{ name: string | null, signal: boolean } | null}
 */
export function roadCrossingAt(entry, here, prev, next) {
	if (!entry) return null;
	const inB = bearing(here, prev);
	const outB = bearing(here, next);
	/** @type {Map<string, { name: string | null, rank: number, id: number, sides: Set<boolean>, signal: boolean }>} */
	const groups = new Map();
	const sides = new Set();
	for (const road of entry.roads) {
		if (!crossableRoad(road.tags)) continue;
		// The course runs along this road here: it turns onto or off it, or follows it through.
		if (road.arms.some((a) => a.node === prev.id || a.node === next.id)) continue;
		const name = road.tags.name?.trim() || null;
		const key = name ? `name:${name.toLowerCase()}` : `way:${road.id}`;
		const g = groups.get(key) ?? { name, rank: classRank(road.tags.highway), id: road.id, sides: new Set(), signal: false };
		g.rank = Math.min(g.rank, classRank(road.tags.highway));
		g.id = Math.min(g.id, road.id);
		for (const arm of road.arms) {
			const side = clockwiseBetween(inB, outB, bearing(here, arm));
			g.sides.add(side);
			sides.add(side);
			if (arm.signal_m !== undefined && arm.signal_m <= ROAD_SIGNAL_NEAR_M) g.signal = true;
		}
		groups.set(key, g);
	}
	if (sides.size < 2) return null;
	const all = [...groups.values()];
	const spanning = all.filter((g) => g.sides.size === 2);
	const pick = [...(spanning.length > 0 ? spanning : all)].sort(
		(a, b) => Number(b.name !== null) - Number(a.name !== null) || a.rank - b.rank || a.id - b.id,
	)[0];
	const signal = signalAtNode(entry.tags) || (spanning.length > 0 ? pick.signal : all.some((g) => g.signal));
	return { name: pick.name, signal };
}
