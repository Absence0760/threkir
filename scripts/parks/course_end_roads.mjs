#!/usr/bin/env node
// Review aid for step 6 of "Adding a course" (scripts/parks/README.md): for
// every course start and finish in a built park, the nearest motor road at
// the end itself and anywhere along its runout (the 30 m past a finish, or
// behind a start). A runout that reaches a roadway (within 3 m of its centre
// line) is marked REVIEW: look at it on the map, and move the end back along the trail (`offset_m`)
// if runners would finish into traffic. The Virginia Capital Trail's last node, 5 m from Colonial Parkway,
// was caught by eye (decisions § 2581).
//
// Network step, like fetch_snapshot.mjs: one OSM API 0.6 `map` request per
// distinct end, a ~150 m box. Reads the built manifest and GeoJSON.
//
// Run: node scripts/parks/course_end_roads.mjs scripts/parks/catalogue/<region>/<park>

import fs from 'node:fs';
import path from 'node:path';

import { REVIEW_WITHIN_M, RUNOUT_M, endReport } from './lib/road_proximity.mjs';

const USER_AGENT = 'threkir-park-courses/1.0 (+https://github.com/jaredhoward-dev/threkir)';
const OSM_API = 'https://api.openstreetmap.org/api/0.6';
const BOX_DEG = 0.0008;

/**
 * Roads in a small box around a point, from the OSM API's XML `map` call.
 *
 * @param {{ lat: number, lng: number }} p
 * @returns {Promise<import('./lib/road_proximity.mjs').Road[]>}
 */
async function roadsNear(p) {
	const bbox = [p.lng - BOX_DEG, p.lat - BOX_DEG, p.lng + BOX_DEG, p.lat + BOX_DEG].join(',');
	const res = await fetch(`${OSM_API}/map.json?bbox=${bbox}`, {
		headers: { 'User-Agent': USER_AGENT },
		signal: AbortSignal.timeout(60_000),
	});
	if (!res.ok) throw new Error(`OSM map ${bbox} -> HTTP ${res.status}`);
	const { elements } = /** @type {{ elements: any[] }} */ (await res.json());
	/** @type {Map<number, { lat: number, lng: number }>} */
	const nodes = new Map();
	for (const e of elements) if (e.type === 'node') nodes.set(e.id, { lat: e.lat, lng: e.lon });
	return elements
		.filter((e) => e.type === 'way' && e.tags?.highway)
		.map((e) => ({
			name: e.tags.name ?? null,
			highway: e.tags.highway,
			line: e.nodes.map((/** @type {number} */ id) => nodes.get(id)).filter(Boolean),
		}))
		.filter((r) => r.line.length >= 2);
}

/** @param {{ road: { name: string | null, highway: string }, m: number } | null} hit */
function describe(hit) {
	return hit ? `${Math.round(hit.m)} m ${hit.road.name ?? `(unnamed ${hit.road.highway})`}` : 'none nearby';
}

async function main() {
	const dir = process.argv[2];
	if (!dir) {
		console.error('usage: node scripts/parks/course_end_roads.mjs <catalogue/park dir>');
		process.exit(2);
	}
	const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
	let flagged = 0;
	for (const entry of [...(manifest.courses ?? []), ...(manifest.race_courses ?? [])]) {
		const gj = JSON.parse(fs.readFileSync(path.join(dir, entry.geojson), 'utf8'));
		const coords = gj.features.find((/** @type {any} */ f) => f.geometry.type === 'LineString').geometry.coordinates;
		const line = coords.map((/** @type {number[]} */ c) => ({ lat: c[1], lng: c[0] }));
		for (const which of /** @type {const} */ (['start', 'finish'])) {
			const end = which === 'start' ? line[0] : line[line.length - 1];
			const report = endReport(line, which, await roadsNear(end));
			if (report.review) flagged++;
			console.log(
				`${report.review ? 'REVIEW' : 'ok    '}  ${entry.slug} ${which}: at the line ${describe(report.atEnd)}; ` +
					`within ${RUNOUT_M} m ${which === 'start' ? 'behind' : 'past'} it ${describe(report.atRunout)}`,
			);
		}
	}
	console.log(`\n${flagged} end(s) whose runout reaches a roadway (within ${REVIEW_WITHIN_M} m of a road's centre line).`);
}

await main();
