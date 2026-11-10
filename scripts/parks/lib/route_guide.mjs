// The route guide of a park course (issue #1344, decisions § 2448): an ordered
// list of structured steps a newcomer can follow, derived from what the
// pipeline already holds — the OSM ways in course order and their names, the
// junctions where the named trail changes, the bridges and fords, the surface,
// the climbs in the elevation profile, the checkpoints and the laps.
//
// Steps are data, not prose: every client renders them through its own i18n
// templates (web `parks/route_guide.ts`, mobile `route_guide.dart`), so a
// guide reads in every locale without a translated copy per course. Names are
// OSM's, verbatim. Nothing here invents a landmark: a step the data cannot
// name carries only its turn and its distance.
//
// Pure and deterministic, like the rest of `lib/`; `build.mjs` writes the
// result into `manifest.json` and `--check` compares it.

import { haversineM } from './course_geometry.mjs';

/** @typedef {import('./course_geometry.mjs').SnapshotNode} SnapshotNode */
/** @typedef {import('./course_geometry.mjs').SnapshotWay} SnapshotWay */

export const ROUTE_GUIDE_VERSION = 1;

export const STEP_KINDS = Object.freeze([
	'start',
	'direction',
	'lap',
	'junction',
	'crossing',
	'surface',
	'climb',
	'checkpoint',
	'finish',
]);
export const TURNS = Object.freeze(['left', 'right', 'straight']);
export const ROTATIONS = Object.freeze(['clockwise', 'counterclockwise']);
export const SIDES = Object.freeze(['left', 'right']);
export const WAY_KINDS = Object.freeze(['fire_road', 'road', 'path']);
export const SURFACES = Object.freeze(['paved', 'gravel', 'dirt', 'unpaved', 'boardwalk']);
export const CROSSINGS = Object.freeze(['bridge', 'ford']);

/** Bearings are measured over this much line either side of a junction. */
export const TURN_LOOK_M = 25;
/** A heading change smaller than this is "straight on". */
export const STRAIGHT_TOLERANCE_DEG = 30;
/**
 * A run of trail shorter than this between two runs of one trail (an unnamed
 * bridge way, a short split) is not a junction.
 */
export const SHORT_RUN_M = 40;
/** A surface stretch shorter than this is not worth a step. */
export const SURFACE_MIN_RUN_M = 150;
/** Elevation hysteresis for climb detection, as in `elevationGainM`'s band but wider. */
export const CLIMB_BAND_M = 4;
/** A rise is a climb when it gains at least this much ... */
export const CLIMB_MIN_GAIN_M = 12;
/** ... at an average grade of at least this. */
export const CLIMB_MIN_GRADE = 0.035;
/** Two bridges this close together are one crossing. */
export const CROSSING_MERGE_M = 30;
/** A lap-2+ step within this of its lap-1 twin is a repeat. */
export const LAP_MATCH_M = 15;
/** The most characters of an OSM name a step carries. */
export const MAX_NAME_LENGTH = 120;
/** The most characters of a getting-there note. */
export const MAX_GETTING_THERE_LENGTH = 500;
/** The most steps a guide may hold; mirrors the CHECK constraint. */
export const MAX_STEPS = 200;

/** @param {string} a @param {string} b */
function edgeKey(a, b) {
	return a < b ? `${a}-${b}` : `${b}-${a}`;
}

/**
 * Initial great-circle bearing, degrees clockwise from north.
 *
 * @param {{ lat: number, lng: number }} a
 * @param {{ lat: number, lng: number }} b
 */
export function bearingDeg(a, b) {
	const toRad = Math.PI / 180;
	const y = Math.sin((b.lng - a.lng) * toRad) * Math.cos(b.lat * toRad);
	const x =
		Math.cos(a.lat * toRad) * Math.sin(b.lat * toRad) -
		Math.sin(a.lat * toRad) * Math.cos(b.lat * toRad) * Math.cos((b.lng - a.lng) * toRad);
	return ((Math.atan2(y, x) / toRad) % 360 + 360) % 360;
}

/**
 * Which way a runner turns at `points[i]`: the heading over the `lookM` of
 * line before it against the heading over the `lookM` after it.
 *
 * @param {{ lat: number, lng: number }[]} points
 * @param {number[]} cum metres along the line at each point
 * @param {number} i
 * @param {number} [lookM]
 * @returns {'left' | 'right' | 'straight'}
 */
export function turnAt(points, cum, i, lookM = TURN_LOOK_M) {
	let a = i;
	while (a > 0 && cum[i] - cum[a] < lookM) a--;
	let b = i;
	while (b < points.length - 1 && cum[b] - cum[i] < lookM) b++;
	if (a === i || b === i) return 'straight';
	const delta = ((bearingDeg(points[i], points[b]) - bearingDeg(points[a], points[i]) + 540) % 360) - 180;
	if (Math.abs(delta) < STRAIGHT_TOLERANCE_DEG) return 'straight';
	return delta > 0 ? 'right' : 'left';
}

/**
 * The surface class a way's OSM tags give, or null when they say nothing
 * (the previous stretch's surface then carries on).
 *
 * @param {Record<string, string>} tags
 * @returns {string | null}
 */
export function surfaceClass(tags) {
	switch (tags.surface) {
		case 'asphalt':
		case 'paved':
		case 'concrete':
		case 'paving_stones':
			return 'paved';
		case 'gravel':
		case 'fine_gravel':
		case 'compacted':
		case 'pebblestone':
			return 'gravel';
		case 'dirt':
		case 'ground':
		case 'earth':
			return 'dirt';
		case 'unpaved':
			return 'unpaved';
		case 'wood':
			return 'boardwalk';
		default:
			return null;
	}
}

/**
 * How an unnamed way reads in a guide: a fire road, a park road, or a path.
 *
 * @param {Record<string, string>} tags
 * @returns {'fire_road' | 'road' | 'path'}
 */
export function wayKind(tags) {
	if (tags.highway === 'track') return 'fire_road';
	if (tags.highway === 'service' || tags.highway === 'unclassified' || tags.highway === 'residential') {
		return 'road';
	}
	return 'path';
}

/**
 * Whether a closed ring of `{lat, lng}` runs clockwise (seen from above, north up).
 *
 * @param {{ lat: number, lng: number }[]} ring
 * @returns {'clockwise' | 'counterclockwise'}
 */
export function rotationOf(ring) {
	let sum = 0;
	for (let i = 0; i < ring.length; i++) {
		const p = ring[i];
		const q = ring[(i + 1) % ring.length];
		sum += p.lng * q.lat - q.lng * p.lat;
	}
	return sum > 0 ? 'counterclockwise' : 'clockwise';
}

/**
 * @param {{ lat: number, lng: number }} p
 * @param {{ lat: number, lng: number }[]} ring
 */
export function pointInRing(p, ring) {
	let inside = false;
	for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
		const a = ring[i];
		const b = ring[j];
		if (a.lat > p.lat !== b.lat > p.lat && p.lng < ((b.lng - a.lng) * (p.lat - a.lat)) / (b.lat - a.lat) + a.lng) {
			inside = !inside;
		}
	}
	return inside;
}

/**
 * The named water feature a loop runs around, and the side it is on, when
 * the snapshot holds one whose every vertex lies inside the loop. A loop's
 * interior is on a clockwise runner's right. Null when there is none: the
 * guide then says only which way round, never a landmark it cannot name.
 *
 * @param {{ lat: number, lng: number }[]} ring
 * @param {'clockwise' | 'counterclockwise'} rotation
 * @param {Array<{ name?: string, ring: { lat: number, lon: number }[] }>} water
 * @returns {{ keep_on: 'left' | 'right', landmark: string } | null}
 */
export function loopLandmark(ring, rotation, water) {
	for (const feature of water) {
		const name = typeof feature.name === 'string' ? feature.name.trim() : '';
		if (!name || !Array.isArray(feature.ring) || feature.ring.length < 3) continue;
		if (feature.ring.every((v) => pointInRing({ lat: v.lat, lng: v.lon }, ring))) {
			return { keep_on: rotation === 'clockwise' ? 'right' : 'left', landmark: name.slice(0, MAX_NAME_LENGTH) };
		}
	}
	return null;
}

/**
 * Up legs of the elevation profile that clear the climb threshold, by the
 * same hysteresis idea as `elevationGainM`: a dip smaller than the band does
 * not end a climb.
 *
 * @param {{ ele?: number | null }[]} points
 * @param {number[]} cum
 * @returns {Array<{ from: number, to: number, gainM: number }>} point indices
 */
export function climbs(points, cum) {
	/** @type {Array<{ from: number, to: number, gainM: number }>} */
	const out = [];
	let trough = -1;
	let peak = -1;
	const flush = () => {
		if (trough < 0 || peak <= trough) return;
		const gain = /** @type {number} */ (points[peak].ele) - /** @type {number} */ (points[trough].ele);
		const length = cum[peak] - cum[trough];
		if (gain >= CLIMB_MIN_GAIN_M && length > 0 && gain / length >= CLIMB_MIN_GRADE) {
			out.push({ from: trough, to: peak, gainM: gain });
		}
	};
	for (let i = 0; i < points.length; i++) {
		const ele = points[i].ele;
		if (ele == null) continue;
		if (trough < 0) {
			trough = i;
			peak = i;
			continue;
		}
		if (ele > /** @type {number} */ (points[peak].ele)) peak = i;
		if (ele <= /** @type {number} */ (points[trough].ele) && peak === trough) {
			trough = i;
			peak = i;
		} else if (/** @type {number} */ (points[peak].ele) - ele >= CLIMB_BAND_M) {
			flush();
			trough = i;
			peak = i;
		}
	}
	flush();
	return out;
}

/**
 * @typedef {{ label: string, name: string | null, kind: 'fire_road' | 'road' | 'path', from: number, to: number }} Run
 * `from` / `to` are point indices; the run covers the edges between them.
 */

/**
 * @param {Run[]} runs
 * @param {number[]} cum
 */
function mergeShortRuns(runs, cum) {
	const len = (/** @type {Run} */ r) => cum[r.to] - cum[r.from];
	let out = [...runs];
	// A short run between two runs of one trail is part of that trail.
	for (let changed = true; changed; ) {
		changed = false;
		for (let i = 1; i < out.length - 1; i++) {
			if (len(out[i]) < SHORT_RUN_M && out[i - 1].label === out[i + 1].label) {
				out.splice(i - 1, 3, { ...out[i - 1], to: out[i + 1].to });
				changed = true;
				break;
			}
		}
	}
	// Any other short run joins the trail it leads onto.
	for (let changed = true; changed; ) {
		changed = false;
		for (let i = 0; i < out.length - 1; i++) {
			if (len(out[i]) < SHORT_RUN_M) {
				out.splice(i, 2, { ...out[i + 1], from: out[i].from });
				changed = true;
				break;
			}
		}
	}
	// Neighbours that now share a label are one run.
	return out.reduce((/** @type {Run[]} */ acc, r) => {
		const last = acc[acc.length - 1];
		if (last && last.label === r.label) last.to = r.to;
		else acc.push({ ...r });
		return acc;
	}, []);
}

/**
 * @typedef {{
 *   sequence: number[],
 *   nodes: Record<string, SnapshotNode>,
 *   ways: SnapshotWay[],
 *   allWays: SnapshotWay[],
 *   offsetM?: number,
 *   lengthM: number,
 *   checkpointCount: number,
 *   laps?: { count: number, firstStartM: number, lapM: number } | null,
 *   water?: Array<{ name?: string, ring: { lat: number, lon: number }[] }>,
 *   lang: string,
 *   gettingThere?: string | null,
 * }} GuideInput
 *
 * `sequence` is the full traced node path; `offsetM` is how far along it the
 * published course starts (a race course's trimmed lead-in) and `lengthM` how
 * long the published course is. `laps.firstStartM` is where lap 1 starts on
 * the full path. Steps of laps 2..N repeat lap 1's, so only the lap marker
 * and the checkpoints are written for them.
 */

/**
 * @param {GuideInput} input
 */
export function buildRouteGuide(input) {
	const { sequence, nodes, ways, allWays, lengthM, checkpointCount, lang } = input;
	const offsetM = input.offsetM ?? 0;
	const points = sequence.map((id) => {
		const n = nodes[String(id)];
		if (!n) throw new Error(`node ${id} is missing from the snapshot`);
		return { lat: n.lat, lng: n.lon, ele: n.ele ?? null };
	});
	/** @type {number[]} */
	const cum = [0];
	for (let i = 1; i < points.length; i++) cum.push(cum[i - 1] + haversineM(points[i - 1], points[i]));

	/** @type {Map<string, SnapshotWay[]>} */
	const byEdge = new Map();
	for (const way of ways) {
		for (let i = 1; i < way.nodes.length; i++) {
			const key = edgeKey(String(way.nodes[i - 1]), String(way.nodes[i]));
			const list = byEdge.get(key);
			if (list) list.push(way);
			else byEdge.set(key, [way]);
		}
	}
	/** @type {Map<number, Set<number>>} */
	const degree = new Map();
	for (const way of allWays) {
		for (let i = 0; i < way.nodes.length; i++) {
			const n = way.nodes[i];
			if (!degree.has(n)) degree.set(n, new Set());
			const set = /** @type {Set<number>} */ (degree.get(n));
			if (i > 0) set.add(way.nodes[i - 1]);
			if (i < way.nodes.length - 1) set.add(way.nodes[i + 1]);
		}
	}

	/** @type {(SnapshotWay | null)[]} edge i runs from point i to point i + 1 */
	const edgeWay = [];
	for (let i = 1; i < sequence.length; i++) {
		const candidates = byEdge.get(edgeKey(String(sequence[i - 1]), String(sequence[i]))) ?? [];
		const named = candidates.filter((w) => w.tags?.name);
		const pick = [...(named.length > 0 ? named : candidates)].sort((a, b) => a.id - b.id)[0] ?? null;
		edgeWay.push(pick);
	}

	/** @type {Run[]} */
	let runs = [];
	for (let i = 0; i < edgeWay.length; i++) {
		const tags = edgeWay[i]?.tags ?? {};
		const name = tags.name?.trim() ? tags.name.trim().slice(0, MAX_NAME_LENGTH) : null;
		const label = name ? `name:${name.toLowerCase()}` : `way:${edgeWay[i]?.id ?? 'none'}`;
		const last = runs[runs.length - 1];
		if (last && last.label === label) last.to = i + 1;
		else runs.push({ label, name, kind: wayKind(tags), from: i, to: i + 1 });
	}
	runs = mergeShortRuns(runs, cum);

	/** @type {Array<Record<string, unknown> & { kind: string, at: number }>} */
	const raw = [];
	for (let r = 1; r < runs.length; r++) {
		const prev = runs[r - 1];
		const run = runs[r];
		const i = run.from;
		const turn = turnAt(points, cum, i);
		if (!run.name && !prev.name) {
			const branching = (degree.get(sequence[i])?.size ?? 0) >= 3;
			if (!branching || turn === 'straight') continue;
		}
		raw.push({
			kind: 'junction',
			at: cum[i],
			turn,
			...(run.name ? { name: run.name } : { way: run.kind }),
		});
	}

	/** @type {{ at: number, crossing: string }[]} */
	const crossings = [];
	for (let i = 0; i < edgeWay.length; i++) {
		const tags = edgeWay[i]?.tags ?? {};
		const crossing = tags.ford === 'yes' ? 'ford' : tags.bridge === 'yes' ? 'bridge' : null;
		if (!crossing) continue;
		const prevTags = i > 0 ? (edgeWay[i - 1]?.tags ?? {}) : {};
		if (edgeWay[i] === edgeWay[i - 1] && (prevTags.ford === 'yes' || prevTags.bridge === 'yes')) continue;
		const last = crossings[crossings.length - 1];
		if (last && last.crossing === crossing && cum[i] - last.at < CROSSING_MERGE_M) continue;
		crossings.push({ at: cum[i], crossing });
	}
	for (const c of crossings) raw.push({ kind: 'crossing', at: c.at, crossing: c.crossing });

	// An untagged way carries the surface before it (the first known one at
	// the start); a stretch shorter than SURFACE_MIN_RUN_M joins the one before.
	/** @type {(string | null)[]} */
	// A bridge is its own crossing step, so its deck says nothing about the trail.
	const edgeSurface = edgeWay.map((w) =>
		w?.tags?.bridge === 'yes' || w?.tags?.ford === 'yes' ? null : surfaceClass(w?.tags ?? {}),
	);
	const firstKnown = edgeSurface.find((s) => s !== null) ?? null;
	/** @type {{ from: number, to: number, surface: string | null }[]} */
	let surfaceRuns = [];
	for (let i = 0; i < edgeSurface.length; i++) {
		const last = surfaceRuns[surfaceRuns.length - 1];
		const s = edgeSurface[i] ?? last?.surface ?? firstKnown;
		if (last && last.surface === s) last.to = i + 1;
		else surfaceRuns.push({ from: i, to: i + 1, surface: s });
	}
	surfaceRuns = surfaceRuns.reduce((/** @type {typeof surfaceRuns} */ acc, r) => {
		const last = acc[acc.length - 1];
		if (last && (last.surface === r.surface || cum[r.to] - cum[r.from] < SURFACE_MIN_RUN_M)) last.to = r.to;
		else acc.push({ ...r });
		return acc;
	}, []);
	for (let k = 1; k < surfaceRuns.length; k++) {
		raw.push({ kind: 'surface', at: cum[surfaceRuns[k].from], surface: surfaceRuns[k].surface });
	}

	for (const c of climbs(points, cum)) {
		raw.push({
			kind: 'climb',
			at: cum[c.from],
			gain_m: Math.round(c.gainM),
			length_m: Math.round((cum[c.to] - cum[c.from]) / 10) * 10,
		});
	}

	// Shift onto the published course and keep what lies on it. A step in
	// laps 2..N that lap 1 already has at the same place is left out, so a
	// lapped guide reads lap 1 once; what differs (the turn off the loop on
	// the last lap) is kept.
	const laps = input.laps ?? null;
	const lapM = laps?.lapM ?? 0;
	const lapOf = (/** @type {number} */ at) =>
		laps && laps.count > 1 && at >= laps.firstStartM + lapM
			? Math.min(laps.count, Math.floor((at - laps.firstStartM) / lapM) + 1)
			: 1;
	const sameStep = (/** @type {Record<string, unknown>} */ a, /** @type {Record<string, unknown>} */ b) => {
		const { at: _a, ...ra } = a;
		const { at: _b, ...rb } = b;
		return JSON.stringify(ra) === JSON.stringify(rb);
	};
	/** @type {Array<Record<string, unknown> & { kind: string, at_m: number }>} */
	const steps = [];
	for (const s of raw) {
		const lap = lapOf(s.at);
		if (lap > 1) {
			const repeats = raw.some(
				(o) => o !== s && lapOf(o.at) < lap && sameStep(o, s) && Math.abs(s.at - o.at - (lap - lapOf(o.at)) * lapM) <= LAP_MATCH_M,
			);
			if (repeats) continue;
		}
		const at = s.at - offsetM;
		if (at < 0 || at >= lengthM) continue;
		const { at: _drop, ...rest } = s;
		steps.push({ ...rest, kind: s.kind, at_m: Math.round(at) });
	}

	const firstRun = runs.find((r) => cum[r.to] > offsetM) ?? runs[0];
	steps.push({
		kind: 'start',
		at_m: 0,
		...(firstRun?.name ? { name: firstRun.name } : { way: firstRun?.kind ?? 'path' }),
	});
	const ring = points.filter((_, i) => cum[i] >= offsetM && cum[i] <= offsetM + lengthM);
	if (ring.length >= 3) {
		const rotation = rotationOf(ring);
		const landmark = loopLandmark(ring, rotation, input.water ?? []);
		steps.push({ kind: 'direction', at_m: 0, rotation, ...(landmark ?? {}) });
	}
	if (laps && laps.count > 1) {
		for (let k = 2; k <= laps.count; k++) {
			steps.push({
				kind: 'lap',
				at_m: Math.round(laps.firstStartM + (k - 1) * laps.lapM - offsetM),
				lap: k,
				of: laps.count,
			});
		}
	}
	for (let k = 1; k <= checkpointCount; k++) {
		steps.push({ kind: 'checkpoint', at_m: Math.round((lengthM * k) / (checkpointCount + 1)), order: k, of: checkpointCount });
	}
	steps.push({ kind: 'finish', at_m: Math.round(lengthM) });

	const rank = (/** @type {string} */ k) => STEP_KINDS.indexOf(k);
	steps.sort((a, b) => a.at_m - b.at_m || rank(a.kind) - rank(b.kind));
	if (steps.length > MAX_STEPS) throw new Error(`the route guide has ${steps.length} steps, over ${MAX_STEPS}`);

	const gettingThere = input.gettingThere?.trim() || null;
	if (gettingThere && gettingThere.length > MAX_GETTING_THERE_LENGTH) {
		throw new Error(`getting_there is longer than ${MAX_GETTING_THERE_LENGTH} characters`);
	}
	return {
		version: ROUTE_GUIDE_VERSION,
		lang,
		...(gettingThere ? { getting_there: gettingThere } : {}),
		steps,
	};
}
