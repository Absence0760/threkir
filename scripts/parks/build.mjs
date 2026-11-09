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
// Run:   node scripts/parks/build.mjs scripts/parks/catalogue/us-va/pocahontas
// Check: node scripts/parks/build.mjs --check scripts/parks/catalogue/us-va/pocahontas

import fs from 'node:fs';
import path from 'node:path';

import {
	PUBLISHED_DISTANCE_TOLERANCE,
	RACE_DISTANCES_M,
	assertFootAccess,
	assertTrailReview,
	distanceDeviation,
	elevationGainM,
	lapCourse,
	pathLengthM,
	placeCheckpoints,
	round6,
	simplify,
	toPoints,
	traceLoop,
	traceVia,
	trimToDistance,
} from './lib/course_geometry.mjs';
import { readIfExists } from './lib/read_if_exists.mjs';

const METERS_PER_MILE = 1609.344;

/** Below a metre the course line is GPS-noise scale; above it a switchback starts to flatten. */
const SIMPLIFY_EPSILON_M = 1;

/**
 * @param {string} dir
 * @returns {Map<string, string>} output path -> contents
 */
export function buildPark(dir) {
	const spec = JSON.parse(fs.readFileSync(path.join(dir, 'park.json'), 'utf8'));
	const snapshot = JSON.parse(fs.readFileSync(path.join(dir, 'snapshot.json'), 'utf8'));
	/** @type {Map<string, string>} */
	const outputs = new Map();
	const courses = [];

	for (const course of spec.courses) {
		if (course.course_shape !== 'loop') {
			throw new Error(`${course.slug}: only loop courses are built so far, got ${course.course_shape}`);
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
		footAccessOrThrow(course.slug, sequence, ways);
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
		const checkpoints = placeCheckpoints(raw, course.checkpoint_count);
		const waypoints = simplify(raw, SIMPLIFY_EPSILON_M).map((p) => ({
			lat: round6(p.lat),
			lng: round6(p.lng),
			ele: p.ele ?? null,
		}));

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
			waypoint_count: waypoints.length,
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
		const leadIn = traceVia({ ways, nodes: snapshot.nodes, via: race.lead_in_via });
		const loop = traceVia({ ways, nodes: snapshot.nodes, via: race.loop_via });
		const sequence = lapCourse({ leadIn, loop, laps: race.laps });
		footAccessOrThrow(race.slug, sequence, ways);
		const fords = trailReviewOrThrow(race.slug, sequence, ways, spec.trail_review);
		const full = toPoints(sequence, snapshot.nodes);
		const leadInM = pathLengthM(toPoints(leadIn, snapshot.nodes));
		const lapM = pathLengthM(toPoints(loop, snapshot.nodes));
		const { points: raw, trimEachEndM } = trimToDistance(full, targetM, leadInM);
		const gainM = Math.round(elevationGainM(raw));
		const checkpoints = placeCheckpoints(raw, race.checkpoints_per_lap * race.laps);
		const waypoints = simplify(raw, SIMPLIFY_EPSILON_M).map((p) => ({
			lat: round6(p.lat),
			lng: round6(p.lng),
			ele: p.ele == null ? null : Math.round(p.ele * 10) / 10,
		}));
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
			distance_m: Math.round(pathLengthM(raw) * 10) / 10,
			laps: race.laps,
			lap_m: Math.round(lapM * 10) / 10,
			lead_in_m: Math.round(leadInM * 10) / 10,
			start_line_from_lead_in_start_m: Math.round(trimEachEndM * 10) / 10,
			start_finish: startFinish,
			surface: race.surface,
			...(fords.length > 0 ? { fords } : {}),
			geometry_source: 'osm',
			source_ref: race.osm_ways.map((/** @type {number} */ id) => `way/${id}`).join(','),
			source_checked_at: snapshot.fetched_at,
			geojson: `${race.slug}.geojson`,
			elevation_m: gainM,
			checkpoints,
			waypoint_count: waypoints.length,
		});
	}

	const manifest = {
		park: spec.park,
		attribution: '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP',
		snapshot_fetched_at: snapshot.fetched_at,
		courses,
		...(raceCourses.length > 0 ? { race_courses: raceCourses } : {}),
	};
	outputs.set(path.join(dir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
	return outputs;
}

/**
 * @param {string} slug
 * @param {number[]} sequence
 * @param {import('./lib/course_geometry.mjs').SnapshotWay[]} ways
 */
function footAccessOrThrow(slug, sequence, ways) {
	try {
		assertFootAccess(sequence, ways);
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

if (import.meta.url === `file://${process.argv[1]}`) main();
