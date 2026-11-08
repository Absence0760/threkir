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
// both need a person to look before anything is loaded.
//
// Run:   node scripts/parks/build.mjs scripts/parks/catalogue/us-va/pocahontas
// Check: node scripts/parks/build.mjs --check scripts/parks/catalogue/us-va/pocahontas

import fs from 'node:fs';
import path from 'node:path';

import {
	PUBLISHED_DISTANCE_TOLERANCE,
	distanceDeviation,
	elevationGainM,
	pathLengthM,
	placeCheckpoints,
	round6,
	simplify,
	toPoints,
	traceLoop,
} from './lib/course_geometry.mjs';

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

	const manifest = {
		park: spec.park,
		attribution: '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP',
		snapshot_fetched_at: snapshot.fetched_at,
		courses,
	};
	outputs.set(path.join(dir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
	return outputs;
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
			const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
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
