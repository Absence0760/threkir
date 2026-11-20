// The go-live gate (decisions § 2600): whether a built park may load into
// production, decided by machine checks alone. Nobody walks a course before it
// opens; a park whose every course passes every check is `live`, and one with
// any failure is `staged` with the failing checks as its reason. Real runs
// check the course after it opens (the attempts sweep, park_courses.md
// § Reports and closures).
//
// Fail-closed throughout: a check whose input is missing from the snapshot
// (a park fetched before `road_crossings` or `course_ends` existed, or a
// course end that moved since `course_ends` was fetched) fails, so missing
// data can only keep a park out, never let one in.
//
// Every limit is a named constant here, justified in decisions § 2600 from
// what the committed parks measure.

import { JOIN_MAX_M, ROAD_CONNECTOR_MAX_M, footAccessRefusal, haversineM, roadConnectorRuns, toPoints, walkedWays } from './course_geometry.mjs';
import { publicParking } from './course_ends.mjs';
import { MAX_STAGED_REASON_LENGTH } from './catalogue_release.mjs';
import { roadCrossingAt } from './road_crossings.mjs';
import { endReport } from './road_proximity.mjs';

/** Bumped when a check or a limit changes, so a manifest says which gate passed it. */
export const GATE_VERSION = 1;

/** Road classes a course may never cross at grade, with or without a signal (their `_link` ramps too). */
export const MAJOR_ROAD_CLASSES = Object.freeze(['motorway', 'trunk']);
/** Road classes a course may cross at grade only at a traffic signal (`roadCrossingAt`'s `signal`). */
export const SIGNAL_ROAD_CLASSES = Object.freeze(['primary']);
/** The share of a course's length it may run along road connectors, all stretches together. */
export const ROAD_SHARE_MAX = 0.15;
/** The share of one lap (or of a whole loop or point-to-point course) that may re-run ground the same lap already covered. */
export const BACKTRACK_MAX = 0.15;
/** The most laps a lapped race course may take, by distance. */
export const MAX_LAPS = Object.freeze({ '5k': 1, '10k': 2, half: 3, marathon: 3, '50k': 3, '50mi': 3, '100k': 3 });
/** From the marathon up, each lap must be at least this long. */
export const LONG_LAP_MIN_M = 14000;
/** The race distances `LONG_LAP_MIN_M` applies to. */
export const LONG_DISTANCES = Object.freeze(['marathon', '50k', '50mi', '100k']);
/** The farthest a start (or a point-to-point finish) may be from a public car park, in a straight line. */
export const PARKING_MAX_M = 800;
/** A fetched `course_ends` entry describes a course end only when it was fetched within this distance of it. */
export const END_MATCH_M = 10;

export const GATE_CHECKS = Object.freeze([
	'source_data',
	'foot_access',
	'major_road_crossing',
	'road_connector',
	'road_share',
	'join_gap',
	'backtrack',
	'laps',
	'parking',
	'end_runout',
]);

/**
 * @typedef {import('./course_geometry.mjs').SnapshotWay} SnapshotWay
 * @typedef {import('./course_geometry.mjs').SnapshotNode} SnapshotNode
 * @typedef {import('./course_geometry.mjs').TrailReview} TrailReview
 * @typedef {{ lat: number, lng: number }} LatLng
 * @typedef {{ check: string, detail: string }} GateFailure
 * @typedef {{
 *   shape: 'loop' | 'out_and_back' | 'point_to_point',
 *   raceDistance: string | null,
 *   laps: number | null,
 *   lapM: number | null,
 *   sequence: number[],
 *   lapSequence: number[] | null,
 *   nodes: Record<string, SnapshotNode>,
 *   ways: SnapshotWay[],
 *   line: LatLng[],
 *   review: TrailReview | undefined,
 *   snapshot: { road_crossings?: { nodes?: Record<string, any> }, course_ends?: { ends?: import('./course_ends.mjs').CourseEnd[] } },
 * }} GateInput
 */

/**
 * Every distinct start and finish of a park's course lines, in first-seen
 * order. A loop or out-and-back gives one point, a point-to-point two.
 *
 * @param {LatLng[][]} lines
 * @returns {LatLng[]}
 */
export function courseEndPoints(lines) {
	/** @type {LatLng[]} */
	const out = [];
	for (const line of lines) {
		for (const p of [line[0], line[line.length - 1]]) {
			if (!out.some((q) => haversineM(p, q) < 1)) out.push({ lat: p.lat, lng: p.lng });
		}
	}
	return out;
}

/**
 * The share of `sequence`'s length that runs over an edge it already ran,
 * either way: 0 for a simple loop, 0.5 for a pure out-and-back.
 *
 * @param {number[]} sequence
 * @param {Record<string, SnapshotNode>} nodes
 */
export function backtrackShare(sequence, nodes) {
	const seen = new Set();
	let total = 0;
	let repeated = 0;
	for (let i = 1; i < sequence.length; i++) {
		const a = nodes[String(sequence[i - 1])];
		const b = nodes[String(sequence[i])];
		const m = haversineM({ lat: a.lat, lng: a.lon }, { lat: b.lat, lng: b.lon });
		const key = sequence[i - 1] < sequence[i] ? `${sequence[i - 1]}-${sequence[i]}` : `${sequence[i]}-${sequence[i - 1]}`;
		if (seen.has(key)) repeated += m;
		else seen.add(key);
		total += m;
	}
	return total === 0 ? 0 : repeated / total;
}

/**
 * Every at-grade road crossing along `sequence`, read with the route guide's
 * own rule (`roadCrossingAt`, decisions § 2594): a crossing where both of the
 * course's edges are on a bridge or in a tunnel is not at grade.
 *
 * @param {number[]} sequence
 * @param {Record<string, SnapshotNode>} nodes
 * @param {SnapshotWay[]} ways
 * @param {Record<string, any>} crossingNodes the snapshot's `road_crossings.nodes`
 * @returns {Array<{ node: number, name: string | null, signal: boolean, highway: string }>}
 */
export function atGradeCrossings(sequence, nodes, ways, crossingNodes) {
	/** @type {Map<string, SnapshotWay>} */
	const byEdge = new Map();
	for (const way of ways) {
		for (let i = 1; i < way.nodes.length; i++) {
			const [a, b] = [way.nodes[i - 1], way.nodes[i]];
			byEdge.set(a < b ? `${a}-${b}` : `${b}-${a}`, way);
		}
	}
	const edgeWay = (/** @type {number} */ i) => {
		const [a, b] = [sequence[i - 1], sequence[i]];
		return byEdge.get(a < b ? `${a}-${b}` : `${b}-${a}`);
	};
	const graded = (/** @type {SnapshotWay | undefined} */ w) => {
		const t = w?.tags ?? {};
		return (t.bridge !== undefined && t.bridge !== 'no') || (t.tunnel !== undefined && t.tunnel !== 'no');
	};
	const at = (/** @type {number} */ k) => {
		const n = nodes[String(sequence[k])];
		return { id: sequence[k], lat: n.lat, lon: n.lon };
	};
	const out = [];
	for (let i = 1; i < sequence.length - 1; i++) {
		const entry = crossingNodes[String(sequence[i])];
		if (!entry || (graded(edgeWay(i)) && graded(edgeWay(i + 1)))) continue;
		const hit = roadCrossingAt(entry, at(i), at(i - 1), at(i + 1));
		if (hit) out.push({ node: sequence[i], ...hit });
	}
	return out;
}

/**
 * The fetched surroundings of a course end, or null when `course_ends` has
 * none within `END_MATCH_M` of it.
 *
 * @param {LatLng} p
 * @param {import('./course_ends.mjs').CourseEnd[]} ends
 */
function endAt(p, ends) {
	let best = null;
	let bestM = Infinity;
	for (const e of ends) {
		const m = haversineM(p, e);
		if (m < bestM) {
			best = e;
			bestM = m;
		}
	}
	return bestM <= END_MATCH_M ? best : null;
}

/**
 * Every failing check for one built course. An empty list means it may go live.
 *
 * @param {GateInput} input
 * @returns {GateFailure[]}
 */
export function gateCourse(input) {
	/** @type {GateFailure[]} */
	const failures = [];
	const fail = (/** @type {string} */ check, /** @type {string} */ detail) => failures.push({ check, detail });
	const { sequence, nodes, ways, review, snapshot } = input;
	const lengthM = lineLengthM(sequence, nodes);

	// Foot access: the build's own refusal rule, read here so a refused way
	// stages the park and says why instead of only stopping the build.
	const footConfirmed = review?.foot_confirmed ?? {};
	const refused = walkedWays(sequence, ways)
		.map((way) => ({ way, reason: footAccessRefusal(way.tags ?? {}) }))
		.filter((r) => r.reason !== null && !(r.reason === 'highway=cycleway' && String(r.way.id) in footConfirmed));
	for (const r of refused) fail('foot_access', `way ${r.way.id} is closed to people on foot (${r.reason})`);

	const crossingNodes = snapshot.road_crossings?.nodes;
	if (!crossingNodes || typeof crossingNodes !== 'object') {
		fail('source_data', 'the snapshot has no road_crossings; run fetch_snapshot.mjs --road-crossings-only');
	} else {
		/** @type {Map<string, { name: string, highway: string, banned: boolean, count: number }>} */
		const major = new Map();
		for (const c of atGradeCrossings(sequence, nodes, ways, crossingNodes)) {
			const banned = MAJOR_ROAD_CLASSES.includes(c.highway);
			if (!banned && !(SIGNAL_ROAD_CLASSES.includes(c.highway) && !c.signal)) continue;
			const name = c.name ?? `an unnamed ${c.highway} road`;
			const k = `${name}|${c.highway}|${banned}`;
			const seen = major.get(k);
			if (seen) seen.count++;
			else major.set(k, { name, highway: c.highway, banned, count: 1 });
		}
		for (const m of major.values()) {
			const times = m.count > 1 ? ` ${m.count} times` : '';
			fail('major_road_crossing', `crosses ${m.name} (${m.highway}) at grade${m.banned ? '' : ' with no traffic signal'}${times}`);
		}
	}

	const runs = roadConnectorRuns(sequence, nodes, ways, Object.keys(review?.road_connectors ?? {}).map(Number));
	for (const r of runs.filter((x) => x.lengthM > ROAD_CONNECTOR_MAX_M)) {
		fail('road_connector', `runs ${Math.round(r.lengthM)} m along ${r.name ?? 'a road'} in one go, over ${ROAD_CONNECTOR_MAX_M} m`);
	}
	const roadM = runs.reduce((sum, r) => sum + r.lengthM, 0);
	if (lengthM > 0 && roadM / lengthM > ROAD_SHARE_MAX) {
		fail('road_share', `${pct(roadM / lengthM)} of the course is road, over ${pct(ROAD_SHARE_MAX)}`);
	}

	if (input.shape !== 'out_and_back') {
		const lap = input.lapSequence ?? sequence;
		const share = backtrackShare(lap, nodes);
		if (share > BACKTRACK_MAX) {
			fail('backtrack', `${input.lapSequence ? 'each lap' : 'the course'} re-runs ${pct(share)} of itself, over ${pct(BACKTRACK_MAX)}`);
		}
	}

	if (input.raceDistance !== null && input.laps !== null) {
		const max = MAX_LAPS[/** @type {keyof typeof MAX_LAPS} */ (input.raceDistance)];
		if (max === undefined) fail('laps', `no lap limit is set for ${input.raceDistance}`);
		else if (input.laps > max) fail('laps', `${input.laps} laps, over the ${max} a ${input.raceDistance} may take`);
		if (LONG_DISTANCES.includes(input.raceDistance) && (input.lapM ?? 0) < LONG_LAP_MIN_M) {
			fail('laps', `a ${Math.round(input.lapM ?? 0)} m lap, under the ${LONG_LAP_MIN_M} m a ${input.raceDistance} lap must be`);
		}
	}

	const walkedIds = new Set(walkedWays(sequence, ways).map((w) => w.id));
	const ends = snapshot.course_ends?.ends;
	if (!Array.isArray(ends)) {
		fail('source_data', 'the snapshot has no course_ends; build, run fetch_snapshot.mjs --course-ends-only, build again');
	} else {
		const line = input.line;
		/** @type {Array<{ which: 'start' | 'finish', needsParking: boolean }>} */
		const checks = [{ which: 'start', needsParking: true }];
		if (input.shape === 'point_to_point') checks.push({ which: 'finish', needsParking: true });
		else checks.push({ which: 'finish', needsParking: false });
		for (const { which, needsParking } of checks) {
			const p = which === 'start' ? line[0] : line[line.length - 1];
			const end = endAt(p, ends);
			if (!end) {
				fail('source_data', `no course_ends entry within ${END_MATCH_M} m of the ${which}; run fetch_snapshot.mjs --course-ends-only`);
				continue;
			}
			if (needsParking) {
				const nearest = end.parking.filter(publicParking)[0];
				if (!nearest || nearest.m > PARKING_MAX_M) {
					fail('parking', `no public car park within ${PARKING_MAX_M} m of the ${which}${nearest ? ` (nearest ${nearest.m} m)` : ''}`);
				}
			}
			// A road the course itself runs along at this end was designated
			// (or listed as a connector) on review, so running out along it is
			// the course, not traffic: Swift Creek's longer courses start on the
			// boat-ramp lot's access road. Only a road the course does not use
			// can be run out onto.
			const report = endReport(line, which, end.roads.filter((r) => !walkedIds.has(r.id)));
			if (report.review && report.atRunout) {
				fail('end_runout', `the ${which} runs out onto ${report.atRunout.road.name ?? `an unnamed ${report.atRunout.road.highway} road`}`);
			}
		}
	}
	return failures;
}

/**
 * Failures that belong to the park rather than one course: every
 * `trail_review.joins` entry must be within `JOIN_MAX_M`.
 *
 * @param {Array<{ nodes: number[], gapM: number }>} joins from `joinWays`
 * @returns {GateFailure[]}
 */
export function gateParkJoins(joins) {
	return joins
		.filter((j) => j.gapM > JOIN_MAX_M)
		.map((j) => ({ check: 'join_gap', detail: `join ${j.nodes.join('-')} spans ${j.gapM.toFixed(1)} m, over ${JOIN_MAX_M} m` }));
}

/**
 * The park's release from its gate results: live when nothing failed, else
 * staged with a reason naming each failing course and check, within the
 * release's 500 characters.
 *
 * @param {GateFailure[]} parkFailures
 * @param {Array<{ slug: string, failures: GateFailure[] }>} courses
 * @returns {import('./catalogue_release.mjs').Release}
 */
export function releaseFromGate(parkFailures, courses) {
	const failing = courses.filter((c) => c.failures.length > 0);
	if (parkFailures.length === 0 && failing.length === 0) return { status: 'live' };
	const parts = [
		...(parkFailures.length > 0 ? [`park: ${[...new Set(parkFailures.map((f) => f.check))].join(', ')}`] : []),
		...failing.map((c) => `${c.slug}: ${[...new Set(c.failures.map((f) => f.check))].join(', ')}`),
	];
	const head = 'Go-live gate failed: ';
	const tail = '. Details in the manifest gate_failures.';
	let kept = parts.length;
	const reason = () =>
		`${head}${parts.slice(0, kept).join('; ')}${kept < parts.length ? `; and ${parts.length - kept} more` : ''}${tail}`;
	while (kept > 1 && reason().length > MAX_STAGED_REASON_LENGTH) kept--;
	return { status: 'staged', reason: reason().slice(0, MAX_STAGED_REASON_LENGTH) };
}

/**
 * @param {number[]} sequence
 * @param {Record<string, SnapshotNode>} nodes
 */
function lineLengthM(sequence, nodes) {
	const pts = toPoints(sequence, nodes);
	let m = 0;
	for (let i = 1; i < pts.length; i++) m += haversineM(pts[i - 1], pts[i]);
	return m;
}

/** @param {number} x */
function pct(x) {
	return `${Math.round(x * 1000) / 10} %`;
}
