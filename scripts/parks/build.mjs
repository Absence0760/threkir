#!/usr/bin/env node
// Build every course of one park from its committed spec (`park.json`) and
// source snapshot (`snapshot.json`), writing one GeoJSON per course and the
// park's `manifest.json` — the reviewed input the operator load turns into
// `parks` / `park_courses` / `global_segments` rows and the official route.
// Offline and deterministic: the same spec and snapshot always produce the
// same bytes, which `--check` verifies.
//
// A course is refused (non-zero exit, nothing written) when its traced
// distance is more than 5 % off the park's published figure: either the spec
// names the wrong ways or the published figure means a different route, and
// both need a person to look before anything is loaded. A course whose line
// uses a way not open to people on foot (a social trail, a bike-only trail,
// `access=no` without a foot override) is refused the same way, and so is one
// whose line uses a way the park's `trail_review` has not marked designated
// after checking it against the land manager's own trail map.
//
// Where the start or end line the database's gate trigger will derive from the
// built points faces more than 10 degrees off the course at that end, the
// course's manifest entry carries a curated `start_gate` / `end_gate` there,
// which the load writes as a curator line. The line follows the route; the
// route is not reshaped to suit the trigger.
//
// Run:   node scripts/parks/build.mjs scripts/parks/catalogue/us-va/pocahontas
// Check: node scripts/parks/build.mjs --check scripts/parks/catalogue/us-va/pocahontas

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	PUBLISHED_DISTANCE_TOLERANCE,
	RACE_COURSE_SHAPES,
	RACE_DISTANCES_M,
	assertFootAccess,
	assertTrailReview,
	curatedGates,
	distanceDeviation,
	elevationGainM,
	assertViaEndsAtTrailEnd,
	lapCourse,
	linearCourse,
	pathLengthM,
	checkpointPositionsM,
	placeCheckpoints,
	round6,
	simplify,
	toPoints,
	traceLoop,
	traceVia,
	trimToDistance,
} from './lib/course_geometry.mjs';
import { SHARED_USES } from './lib/catalogue_payload.mjs';
import { parseRelease } from './lib/catalogue_release.mjs';
import { readIfExists } from './lib/read_if_exists.mjs';
import { buildRouteGuide } from './lib/route_guide.mjs';
import { assertNoThirdPartyMarks } from './lib/third_party_marks.mjs';

const METERS_PER_MILE = 1609.344;

/** Below a metre the course line is GPS-noise scale; above it a switchback starts to flatten. */
const SIMPLIFY_EPSILON_M = 1;

/**
 * @param {string} dir
 * @returns {Map<string, string>} output path -> contents
 */
export function buildPark(dir) {
	const spec = JSON.parse(fs.readFileSync(path.join(dir, 'park.json'), 'utf8'));
	assertNoThirdPartyMarks(spec, path.join(dir, 'park.json'));
	const release = parseRelease(spec.release, path.join(dir, 'park.json'));
	const snapshot = JSON.parse(fs.readFileSync(path.join(dir, 'snapshot.json'), 'utf8'));
	/** @type {Map<string, string>} */
	const outputs = new Map();
	const courses = [];

	for (const course of spec.courses) {
		if (course.course_shape !== 'loop') {
			throw new Error(`${course.slug}: a trail course is a loop, got ${course.course_shape}; a linear course goes under race_courses`);
		}
		const ways = course.osm_ways.map((/** @type {number} */ id) => {
			const way = snapshot.ways[String(id)];
			if (!way) throw new Error(`${course.slug}: way ${id} is not in the snapshot; re-run fetch_snapshot.mjs`);
			return way;
		});
		const sequence = traceLoop({
			ways,
			nodes: snapshot.nodes,
			start: course.start_node,
			direction: course.direction,
		});
		footAccessOrThrow(course.slug, sequence, ways, spec.trail_review);
		const fords = trailReviewOrThrow(course.slug, sequence, ways, spec.trail_review);
		const raw = toPoints(sequence, snapshot.nodes);
		const distanceM = pathLengthM(raw);
		const publishedM = course.published.distance_mi * METERS_PER_MILE;
		const deviation = distanceDeviation(distanceM, publishedM);
		if (Math.abs(deviation) > PUBLISHED_DISTANCE_TOLERANCE) {
			throw new Error(
				`${course.slug}: traced ${(distanceM / METERS_PER_MILE).toFixed(2)} mi is ${(deviation * 100).toFixed(1)} % off the published ${course.published.distance_mi} mi`,
			);
		}
		const gainM = Math.round(elevationGainM(raw));
		const checkpointAtM = checkpointPositionsOrThrow(course.slug, distanceM, course.checkpoint_count, course.checkpoint_at_m);
		const checkpoints = placeCheckpoints(raw, checkpointAtM);
		const waypoints = simplify(raw, SIMPLIFY_EPSILON_M).map((p) => ({
			lat: round6(p.lat),
			lng: round6(p.lng),
			ele: p.ele ?? null,
		}));
		const gates = curatedGatesOrThrow(course.slug, waypoints);
		const guide = routeGuideOrThrow(course.slug, course.route_guide, {
			sequence,
			nodes: snapshot.nodes,
			ways,
			allWays: Object.values(snapshot.ways),
			lengthM: distanceM,
			checkpointAtM,
			laps: null,
			water: snapshot.water,
		});

		const geojson = {
			type: 'FeatureCollection',
			features: [
				{
					type: 'Feature',
					properties: { kind: 'course', park: spec.park.slug, course: course.slug, name: course.name },
					geometry: {
						type: 'LineString',
						coordinates: waypoints.map((p) => (p.ele == null ? [p.lng, p.lat] : [p.lng, p.lat, p.ele])),
					},
				},
				{
					type: 'Feature',
					properties: { kind: 'start_finish' },
					geometry: { type: 'Point', coordinates: [waypoints[0].lng, waypoints[0].lat] },
				},
				...checkpoints.map((c, i) => ({
					type: 'Feature',
					properties: { kind: 'checkpoint', order: i + 1 },
					geometry: { type: 'Point', coordinates: [c.lng, c.lat] },
				})),
			],
		};
		outputs.set(path.join(dir, `${course.slug}.geojson`), `${JSON.stringify(geojson, null, 1)}\n`);

		courses.push({
			slug: course.slug,
			name: course.name,
			course_shape: course.course_shape,
			direction: course.direction,
			surface: course.surface,
			difficulty: course.difficulty,
			...sharedUseOrThrow(course),
			...(fords.length > 0 ? { fords } : {}),
			geometry_source: 'osm',
			source_ref: course.osm_ways.map((/** @type {number} */ id) => `way/${id}`).join(','),
			source_checked_at: snapshot.fetched_at,
			geojson: `${course.slug}.geojson`,
			distance_m: Math.round(distanceM),
			elevation_m: gainM,
			published_distance_m: Math.round(publishedM),
			published_deviation_pct: Math.round(deviation * 1000) / 10,
			published_source: course.published.source,
			checkpoints,
			...gates,
			waypoint_count: waypoints.length,
			...guide,
		});
	}

	const raceCourses = [];
	for (const race of spec.race_courses ?? []) {
		const targetM = RACE_DISTANCES_M[/** @type {keyof typeof RACE_DISTANCES_M} */ (race.race_distance)];
		if (targetM === undefined) throw new Error(`${race.slug}: unknown race distance ${race.race_distance}`);
		const ways = race.osm_ways.map((/** @type {number} */ id) => {
			const way = snapshot.ways[String(id)];
			if (!way) throw new Error(`${race.slug}: way ${id} is not in the snapshot; re-run fetch_snapshot.mjs`);
			return way;
		});
		if (!RACE_COURSE_SHAPES.includes(race.course_shape)) {
			throw new Error(`${race.slug}: course_shape ${race.course_shape} is not one of ${RACE_COURSE_SHAPES.join(', ')}`);
		}
		if (race.course_shape !== 'loop') {
			const built = buildLinearRace(spec, snapshot, race, ways, targetM);
			outputs.set(path.join(dir, `${race.slug}.geojson`), built.geojson);
			raceCourses.push(built.entry);
			continue;
		}
		const leadIn = traceVia({ ways, nodes: snapshot.nodes, via: race.lead_in_via });
		const loop = traceVia({ ways, nodes: snapshot.nodes, via: race.loop_via });
		const sequence = lapCourse({ leadIn, loop, laps: race.laps });
		footAccessOrThrow(race.slug, sequence, ways, spec.trail_review);
		const fords = trailReviewOrThrow(race.slug, sequence, ways, spec.trail_review);
		const full = toPoints(sequence, snapshot.nodes);
		const leadInM = pathLengthM(toPoints(leadIn, snapshot.nodes));
		const lapM = pathLengthM(toPoints(loop, snapshot.nodes));
		const { points: raw, trimEachEndM } = trimToDistance(full, targetM, leadInM);
		const gainM = Math.round(elevationGainM(raw));
		const checkpointAtM = checkpointPositionsOrThrow(race.slug, pathLengthM(raw), race.checkpoints_per_lap * race.laps, undefined);
		const checkpoints = placeCheckpoints(raw, checkpointAtM);
		const waypoints = simplify(raw, SIMPLIFY_EPSILON_M).map((p) => ({
			lat: round6(p.lat),
			lng: round6(p.lng),
			ele: p.ele == null ? null : Math.round(p.ele * 10) / 10,
		}));
		const gates = curatedGatesOrThrow(race.slug, waypoints);
		const guide = routeGuideOrThrow(race.slug, race.route_guide, {
			sequence,
			nodes: snapshot.nodes,
			ways,
			allWays: Object.values(snapshot.ways),
			offsetM: trimEachEndM,
			lengthM: pathLengthM(raw),
			checkpointAtM,
			laps: { count: race.laps, firstStartM: leadInM, lapM },
			water: snapshot.water,
		});
		const startFinish = { lat: waypoints[0].lat, lng: waypoints[0].lng };

		const geojson = {
			type: 'FeatureCollection',
			features: [
				{
					type: 'Feature',
					properties: {
						kind: 'race_course',
						park: spec.park.slug,
						course: race.slug,
						name: race.name,
						race_distance: race.race_distance,
						laps: race.laps,
					},
					geometry: {
						type: 'LineString',
						coordinates: waypoints.map((p) => (p.ele == null ? [p.lng, p.lat] : [p.lng, p.lat, p.ele])),
					},
				},
				{
					type: 'Feature',
					properties: { kind: 'start_finish' },
					geometry: { type: 'Point', coordinates: [startFinish.lng, startFinish.lat] },
				},
				...checkpoints.map((c, i) => ({
					type: 'Feature',
					properties: { kind: 'checkpoint', order: i + 1 },
					geometry: { type: 'Point', coordinates: [c.lng, c.lat] },
				})),
			],
		};
		outputs.set(path.join(dir, `${race.slug}.geojson`), `${JSON.stringify(geojson, null, 1)}\n`);

		raceCourses.push({
			slug: race.slug,
			name: race.name,
			race_distance: race.race_distance,
			course_shape: race.course_shape,
			distance_m: Math.round(pathLengthM(raw) * 10) / 10,
			laps: race.laps,
			lap_m: Math.round(lapM * 10) / 10,
			lead_in_m: Math.round(leadInM * 10) / 10,
			start_line_from_lead_in_start_m: Math.round(trimEachEndM * 10) / 10,
			start_finish: startFinish,
			surface: race.surface,
			...sharedUseOrThrow(race),
			...(fords.length > 0 ? { fords } : {}),
			geometry_source: 'osm',
			source_ref: race.osm_ways.map((/** @type {number} */ id) => `way/${id}`).join(','),
			source_checked_at: snapshot.fetched_at,
			geojson: `${race.slug}.geojson`,
			elevation_m: gainM,
			checkpoints,
			...gates,
			waypoint_count: waypoints.length,
			...guide,
		});
	}

	const manifest = {
		park: spec.park,
		release,
		attribution: '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP',
		snapshot_fetched_at: snapshot.fetched_at,
		courses,
		...(raceCourses.length > 0 ? { race_courses: raceCourses } : {}),
	};
	assertNoThirdPartyMarks(manifest, path.join(dir, 'manifest.json'));
	outputs.set(path.join(dir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
	return outputs;
}

/**
 * A point-to-point or out-and-back race course: exactly the race distance
 * along the trail the via nodes pin, with no laps. An out-and-back's
 * checkpoints sit on the way out only, evenly spaced, the last exactly on the
 * turn: the way back passes the same places, so a second set would sit on top
 * of the first and add nothing, and the turn is what stops a runner who turns
 * early from being timed.
 *
 * @param {any} spec
 * @param {any} snapshot
 * @param {any} race
 * @param {import('./lib/course_geometry.mjs').SnapshotWay[]} ways
 * @param {number} targetM
 */
function buildLinearRace(spec, snapshot, race, ways, targetM) {
	const fail = (/** @type {unknown} */ err) => new Error(`${race.slug}: ${/** @type {Error} */ (err).message}`);
	if (race.laps != null) throw new Error(`${race.slug}: a ${race.course_shape} course has no laps`);
	if (!Number.isInteger(race.checkpoint_count) || race.checkpoint_count < 1) {
		throw new Error(`${race.slug}: checkpoint_count must be a whole number of at least 1`);
	}
	/** @type {ReturnType<typeof linearCourse>} */
	let cut;
	try {
		cut = linearCourse({
			ways,
			nodes: snapshot.nodes,
			via: race.via,
			shape: race.course_shape,
			distanceM: targetM,
			anchor: race.anchor,
			offsetM: race.offset_m ?? 0,
		});
	} catch (err) {
		throw fail(err);
	}
	if (race.via_ends_at_trail_end === true) {
		try {
			assertViaEndsAtTrailEnd(cut.fullSequence, ways);
		} catch (err) {
			throw fail(err);
		}
	}
	footAccessOrThrow(race.slug, cut.sequence, cut.ways, spec.trail_review);
	const fords = trailReviewOrThrow(race.slug, cut.sequence, cut.ways, spec.trail_review);
	const raw = toPoints(cut.sequence, cut.nodes);
	const lengthM = pathLengthM(raw);
	if (Math.abs(lengthM - targetM) > 0.5) throw new Error(`${race.slug}: built ${lengthM.toFixed(1)} m, not ${targetM} m`);
	const gainM = Math.round(elevationGainM(raw));
	const checkpointAtM =
		race.course_shape === 'out_and_back'
			? Array.from({ length: race.checkpoint_count }, (_, i) => (lengthM / 2) * ((i + 1) / race.checkpoint_count))
			: checkpointPositionsOrThrow(race.slug, lengthM, race.checkpoint_count, undefined);
	const checkpoints = placeCheckpoints(raw, checkpointAtM);
	const waypoints = simplify(raw, SIMPLIFY_EPSILON_M).map((p) => ({
		lat: round6(p.lat),
		lng: round6(p.lng),
		ele: p.ele == null ? null : Math.round(p.ele * 10) / 10,
	}));
	const gates = curatedGatesOrThrow(race.slug, waypoints);
	const cutIds = new Set(cut.ways.map((w) => w.id));
	const guide = routeGuideOrThrow(race.slug, race.route_guide, {
		sequence: cut.sequence,
		nodes: cut.nodes,
		ways: cut.ways,
		allWays: [...cut.ways, ...Object.values(snapshot.ways).filter((w) => !cutIds.has(/** @type {any} */ (w).id))],
		lengthM,
		checkpointAtM,
		laps: null,
		loop: false,
		water: snapshot.water,
	});
	const start = { lat: waypoints[0].lat, lng: waypoints[0].lng };
	const last = waypoints[waypoints.length - 1];
	const finish = { lat: last.lat, lng: last.lng };
	const ends =
		race.course_shape === 'out_and_back'
			? [{ type: 'Feature', properties: { kind: 'start_finish' }, geometry: { type: 'Point', coordinates: [start.lng, start.lat] } }]
			: [
					{ type: 'Feature', properties: { kind: 'start' }, geometry: { type: 'Point', coordinates: [start.lng, start.lat] } },
					{ type: 'Feature', properties: { kind: 'finish' }, geometry: { type: 'Point', coordinates: [finish.lng, finish.lat] } },
				];
	const geojson = {
		type: 'FeatureCollection',
		features: [
			{
				type: 'Feature',
				properties: {
					kind: 'race_course',
					park: spec.park.slug,
					course: race.slug,
					name: race.name,
					race_distance: race.race_distance,
					course_shape: race.course_shape,
				},
				geometry: {
					type: 'LineString',
					coordinates: waypoints.map((p) => (p.ele == null ? [p.lng, p.lat] : [p.lng, p.lat, p.ele])),
				},
			},
			...ends,
			...checkpoints.map((c, i) => ({
				type: 'Feature',
				properties: { kind: 'checkpoint', order: i + 1 },
				geometry: { type: 'Point', coordinates: [c.lng, c.lat] },
			})),
		],
	};
	return {
		geojson: `${JSON.stringify(geojson, null, 1)}\n`,
		entry: {
			slug: race.slug,
			name: race.name,
			race_distance: race.race_distance,
			course_shape: race.course_shape,
			distance_m: Math.round(lengthM * 10) / 10,
			...(race.course_shape === 'out_and_back' ? { start_finish: start, turn_at_m: Math.round(lengthM / 2 * 10) / 10 } : { start, finish }),
			surface: race.surface,
			...sharedUseOrThrow(race),
			...(fords.length > 0 ? { fords } : {}),
			geometry_source: 'osm',
			source_ref: race.osm_ways.map((/** @type {number} */ id) => `way/${id}`).join(','),
			source_checked_at: snapshot.fetched_at,
			geojson: `${race.slug}.geojson`,
			elevation_m: gainM,
			checkpoints,
			...gates,
			waypoint_count: waypoints.length,
			...guide,
		},
	};
}

/**
 * @param {string} slug
 * @param {number[]} sequence
 * @param {import('./lib/course_geometry.mjs').SnapshotWay[]} ways
 * @param {import('./lib/course_geometry.mjs').TrailReview | undefined} review
 */
function footAccessOrThrow(slug, sequence, ways, review) {
	try {
		assertFootAccess(sequence, ways, review?.foot_confirmed);
	} catch (err) {
		throw new Error(`${slug}: ${/** @type {Error} */ (err).message}`);
	}
}

/**
 * @param {string} slug
 * @param {number[]} sequence
 * @param {import('./lib/course_geometry.mjs').SnapshotWay[]} ways
 * @param {import('./lib/course_geometry.mjs').TrailReview | undefined} review
 */
function trailReviewOrThrow(slug, sequence, ways, review) {
	try {
		return assertTrailReview(sequence, ways, review);
	} catch (err) {
		throw new Error(`${slug}: ${/** @type {Error} */ (err).message}`);
	}
}

const DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * A course's `shared_use`, when the spec gives one: a vocabulary key naming
 * when an organised group uses the paths, which each client renders as a
 * give-way note naming no one.
 *
 * @param {{ slug: string, shared_use?: unknown }} course
 */
function sharedUseOrThrow(course) {
	if (course.shared_use == null) return {};
	if (typeof course.shared_use !== 'string' || !SHARED_USES.includes(course.shared_use)) {
		throw new Error(`${course.slug}: shared_use ${JSON.stringify(course.shared_use)} is not one of ${SHARED_USES.join(', ')}`);
	}
	return { shared_use: course.shared_use };
}

/**
 * A course's route guide and the date a person last checked it on the
 * ground, as its manifest entry carries them. `spec` is the course's
 * hand-written `route_guide` in `park.json`: an optional `getting_there`
 * note in English and `ground_checked_at`, which only the person who walked
 * the guide sets.
 *
 * @param {string} slug
 * @param {{ getting_there?: string, ground_checked_at?: string | null } | undefined} spec
 * @param {Omit<import('./lib/route_guide.mjs').GuideInput, 'lang' | 'gettingThere'>} input
 */
function routeGuideOrThrow(slug, spec, input) {
	const checkedAt = spec?.ground_checked_at ?? null;
	if (checkedAt !== null && !DATE.test(checkedAt)) {
		throw new Error(`${slug}: route_guide.ground_checked_at must be YYYY-MM-DD, got ${checkedAt}`);
	}
	try {
		return {
			route_guide: buildRouteGuide({ ...input, lang: 'en', gettingThere: spec?.getting_there ?? null }),
			route_guide_checked_at: checkedAt,
		};
	} catch (err) {
		throw new Error(`${slug}: ${/** @type {Error} */ (err).message}`);
	}
}

/**
 * @param {string} slug
 * @param {number} totalM
 * @param {number} count
 * @param {number[] | undefined} atM
 */
function checkpointPositionsOrThrow(slug, totalM, count, atM) {
	try {
		return checkpointPositionsM(totalM, count, atM);
	} catch (err) {
		throw new Error(`${slug}: ${/** @type {Error} */ (err).message}`);
	}
}

/**
 * @param {string} slug
 * @param {import('./lib/course_geometry.mjs').LatLng[]} waypoints
 */
function curatedGatesOrThrow(slug, waypoints) {
	try {
		return curatedGates(waypoints);
	} catch (err) {
		throw new Error(`${slug}: ${/** @type {Error} */ (err).message}`);
	}
}

function main() {
	const args = process.argv.slice(2);
	const check = args.includes('--check');
	const dirs = args.filter((a) => a !== '--check');
	if (dirs.length === 0) {
		console.error('usage: node scripts/parks/build.mjs [--check] <catalogue/park dir>...');
		process.exit(2);
	}
	let stale = 0;
	for (const dir of dirs) {
		for (const [file, contents] of buildPark(dir)) {
			const current = readIfExists(file);
			if (current === contents) continue;
			if (check) {
				console.error(`${file} is stale; run node scripts/parks/build.mjs ${dir}`);
				stale++;
			} else {
				fs.writeFileSync(file, contents);
				console.log(`wrote ${file}`);
			}
		}
	}
	if (stale > 0) process.exit(1);
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) main();
