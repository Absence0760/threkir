// What surrounds each course end, so the go-live gate (`golive_gate.mjs`) can
// check a start or finish without a person standing there: the public car
// parks near it and the motor roads beside it.
//
// `fetch_snapshot.mjs --course-ends-only` asks Overpass once per park, for
// every start and finish in the built manifest, and writes the answer as the
// snapshot's `course_ends`. Like `road_crossings.mjs`, the parse rebuilds every
// field from a checked primitive, so a malformed response stops the fetch
// rather than landing in a reviewed file. The build then reads it offline.

import { MOTOR_ROADS, distanceToLineM } from './road_proximity.mjs';
import { haversineM } from './course_geometry.mjs';
import { isCoordinate, isPositiveInteger, isTagString } from './osm_response.mjs';

/** How far from a course end the fetch looks for a car park. */
export const PARKING_SEARCH_M = 1500;
/** How far from a course end the fetch keeps motor roads: past the 30 m runout plus a road's half-width. */
export const ROAD_SEARCH_M = 60;
/** The car parks kept per end, nearest first; the gate reads only the nearest. */
export const PARKING_KEPT = 3;
/**
 * Car park `access` values that do not let the public park there. `permit` is
 * not one: Virginia's state park lots are tagged `access=permit` for the
 * day-use parking pass any visitor can buy at the gate.
 */
export const PARKING_ACCESS_REFUSED = Object.freeze(['private', 'no', 'customers', 'delivery', 'employees']);

const PARKING_TAGS = Object.freeze(['amenity', 'access', 'name', 'fee', 'parking']);
const ROAD_TAGS = Object.freeze(['highway', 'name']);

/**
 * @typedef {{ lat: number, lng: number }} LatLng
 * @typedef {{ id: string, lat: number, lng: number, m: number, tags: Record<string, string> }} Parking
 * @typedef {{ id: number, name: string | null, highway: string, line: LatLng[] }} EndRoad
 * @typedef {{ lat: number, lng: number, parking: Parking[], roads: EndRoad[] }} CourseEnd
 */

/**
 * The Overpass query for every end: car parks within `PARKING_SEARCH_M`
 * (their centre, `out center`) and motor roads within `ROAD_SEARCH_M` (their
 * geometry, `out geom`).
 *
 * @param {LatLng[]} ends
 * @param {string} roadPattern the `highway` regular expression for motor roads
 */
export function courseEndsQuery(ends, roadPattern) {
	const around = (/** @type {number} */ r, /** @type {LatLng} */ p) => `(around:${r},${p.lat.toFixed(7)},${p.lng.toFixed(7)})`;
	return [
		'[out:json][timeout:180];',
		'(',
		...ends.map((p) => `  nwr${around(PARKING_SEARCH_M, p)}[amenity=parking];`),
		');',
		'out center tags;',
		'(',
		...ends.map((p) => `  way${around(ROAD_SEARCH_M, p)}[highway~"${roadPattern}"];`),
		');',
		'out geom tags;',
	].join('\n');
}

/**
 * @param {unknown} raw
 * @param {readonly string[]} keep
 * @param {string} what
 */
function checkedTags(raw, keep, what) {
	if (raw === undefined) return {};
	if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) throw new Error(`${what}: tags is not an object`);
	/** @type {Array<[string, string]>} */
	const out = [];
	for (const [key, value] of Object.entries(raw)) {
		if (!isTagString(key) || !isTagString(value)) throw new Error(`${what}: a tag is not a short string pair`);
		if (keep.includes(key)) out.push([key, value]);
	}
	out.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
	return Object.fromEntries(out);
}

/** @param {unknown} v @param {string} what */
function point(v, what) {
	const p = /** @type {{ lat?: unknown, lon?: unknown }} */ (v ?? {});
	if (!isCoordinate(p.lat, 90) || !isCoordinate(p.lon, 180)) throw new Error(`${what} has no valid coordinate`);
	return { lat: Math.round(p.lat * 1e7) / 1e7, lng: Math.round(p.lon * 1e7) / 1e7 };
}

/**
 * Each end's surroundings from the Overpass response to `courseEndsQuery`.
 *
 * @param {unknown} body
 * @param {LatLng[]} ends
 * @returns {CourseEnd[]}
 */
export function parseCourseEnds(body, ends) {
	const elements = /** @type {{ elements?: unknown }} */ (body ?? {}).elements;
	if (!Array.isArray(elements)) throw new Error('Overpass response has no elements array');
	/** @type {Array<{ id: string, at: LatLng, tags: Record<string, string> }>} */
	const parks = [];
	/** @type {EndRoad[]} */
	const roads = [];
	for (const raw of elements) {
		if (typeof raw !== 'object' || raw === null) throw new Error('an Overpass element is not an object');
		const el = /** @type {Record<string, any>} */ (raw);
		if (!['node', 'way', 'relation'].includes(el.type)) throw new Error(`unexpected Overpass element type ${JSON.stringify(el.type)}`);
		if (!isPositiveInteger(el.id)) throw new Error(`${el.type} id ${JSON.stringify(el.id)} is not a positive integer`);
		const what = `${el.type} ${el.id}`;
		if (el.tags?.amenity === 'parking') {
			const at = point(el.type === 'node' ? el : el.center, what);
			parks.push({ id: `${el.type}/${el.id}`, at, tags: checkedTags(el.tags, PARKING_TAGS, what) });
			continue;
		}
		if (el.type !== 'way') throw new Error(`${what} is neither a car park nor a road`);
		const tags = checkedTags(el.tags, ROAD_TAGS, what);
		const highway = (tags.highway ?? '').replace(/_link$/, '');
		if (!MOTOR_ROADS.includes(highway)) throw new Error(`${what} has highway ${JSON.stringify(tags.highway)}, not a motor road`);
		if (!Array.isArray(el.geometry) || el.geometry.length < 2) throw new Error(`${what} has no geometry`);
		roads.push({
			id: el.id,
			name: tags.name ?? null,
			highway: /** @type {string} */ (tags.highway),
			line: el.geometry.map((/** @type {unknown} */ g, /** @type {number} */ i) => point(g, `${what} point ${i}`)),
		});
	}
	const uniqueParks = [...new Map(parks.map((p) => [p.id, p])).values()];
	const uniqueRoads = [...new Map(roads.map((r) => [r.id, r])).values()].sort((a, b) => a.id - b.id);
	return ends.map((end) => ({
		lat: end.lat,
		lng: end.lng,
		parking: uniqueParks
			.map((p) => ({ id: p.id, lat: p.at.lat, lng: p.at.lng, m: Math.round(haversineM(end, p.at)), tags: p.tags }))
			.filter((p) => p.m <= PARKING_SEARCH_M)
			.sort((a, b) => a.m - b.m || (a.id < b.id ? -1 : 1))
			.slice(0, PARKING_KEPT),
		roads: uniqueRoads.filter((r) => distanceToLineM(end, r.line) <= ROAD_SEARCH_M),
	}));
}

/**
 * Whether the public may park at a car park, by its OSM `access`.
 *
 * @param {Parking} p
 */
export function publicParking(p) {
	return !PARKING_ACCESS_REFUSED.includes(p.tags.access ?? '');
}
