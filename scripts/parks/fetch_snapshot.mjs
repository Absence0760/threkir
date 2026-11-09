#!/usr/bin/env node
// Fetch the source data a park's courses are built from, and write it to the
// park's committed `snapshot.json`: every OSM way the spec names (with its
// nodes) and a USGS 3DEP elevation for each node. `build.mjs` then runs
// offline against the snapshot, so a later OSM edit or an elevation-service
// change never moves a course silently; re-running this is a deliberate,
// reviewed step whose diff shows exactly what changed upstream.
//
// Sources (issue #1313 § Getting the geometry):
//   - OSM API 0.6 `way/{id}/full` (ODbL, © OpenStreetMap contributors). One
//     request per way, well inside the API usage policy for an occasional run.
//   - USGS Elevation Point Query Service (3DEP, US public domain). US only;
//     a park elsewhere needs another source before it can be built.
//
// Run: node scripts/parks/fetch_snapshot.mjs scripts/parks/catalogue/us-va/pocahontas

import fs from 'node:fs';
import path from 'node:path';

import { parseWayFull } from './lib/osm_response.mjs';
import { readIfExists } from './lib/read_if_exists.mjs';

const USER_AGENT = 'threkir-park-courses/1.0 (+https://github.com/Absence0760/threkir)';
const OSM_API = 'https://api.openstreetmap.org/api/0.6';
const EPQS = 'https://epqs.nationalmap.gov/v1/json';
const ELEVATION_CONCURRENCY = 4;
const REQUEST_TIMEOUT_MS = 30_000;

/** @param {string} url */
async function getJson(url) {
	for (let attempt = 1; ; attempt++) {
		/** @type {Response | null} */
		let res = null;
		let text = '';
		try {
			// Without a deadline one stalled EPQS connection hangs the whole run.
			res = await fetch(url, {
				headers: { 'User-Agent': USER_AGENT },
				signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
			});
			// EPQS sometimes answers 200 with an empty body under load; that is
			// a transient failure, not data.
			text = res.ok ? await res.text() : '';
		} catch (err) {
			if (attempt >= 5) throw new Error(`${url} -> ${err}`);
		}
		if (res?.ok && text.trim() !== '') return JSON.parse(text);
		if (res && (attempt >= 5 || (!res.ok && res.status < 500 && res.status !== 429))) {
			throw new Error(`${url} -> HTTP ${res.status}${res.ok ? ' with an empty body' : ''}`);
		}
		await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
	}
}

/**
 * @param {number} lat
 * @param {number} lon
 * @returns {Promise<number>}
 */
async function elevationM(lat, lon) {
	const body = await getJson(`${EPQS}?x=${lon}&y=${lat}&wkid=4326&units=Meters&includeDate=false`);
	const value = Number(body?.value);
	// EPQS answers -1000000 for a point outside its coverage.
	if (!Number.isFinite(value) || value < -500) {
		throw new Error(`no USGS elevation at ${lat},${lon} (got ${JSON.stringify(body?.value)})`);
	}
	return Math.round(value * 10) / 10;
}

async function main() {
	const dir = process.argv[2];
	if (!dir) {
		console.error('usage: node scripts/parks/fetch_snapshot.mjs <catalogue/park dir>');
		process.exit(2);
	}
	const spec = JSON.parse(fs.readFileSync(path.join(dir, 'park.json'), 'utf8'));
	const snapshotPath = path.join(dir, 'snapshot.json');
	/** @type {Record<string, { lat: number, lon: number, ele?: number }>} */
	const previous = JSON.parse(readIfExists(snapshotPath) ?? '{"nodes":{}}').nodes;

	/** @type {Set<number>} */
	const wayIds = new Set();
	for (const course of [...spec.courses, ...(spec.race_courses ?? [])]) {
		for (const id of course.osm_ways) wayIds.add(id);
	}

	/** @type {Record<string, { id: number, version: number, tags: Record<string, string>, nodes: number[] }>} */
	const ways = {};
	/** @type {Record<string, { lat: number, lon: number, ele?: number }>} */
	const nodes = {};
	for (const id of [...wayIds].sort((a, b) => a - b)) {
		const parsed = parseWayFull(await getJson(`${OSM_API}/way/${id}/full.json`), id);
		ways[String(id)] = parsed.way;
		Object.assign(nodes, parsed.nodes);
	}

	/** @type {Array<{ lat: number, lon: number, ele?: number }>} */
	const missing = [];
	for (const [id, node] of Object.entries(nodes)) {
		const old = previous[id];
		// Reuse an elevation only for a node that has not moved.
		if (old && old.lat === node.lat && old.lon === node.lon && old.ele != null) {
			node.ele = old.ele;
		} else {
			missing.push(node);
		}
	}
	// EPQS takes several seconds a point, so a few run at once; more than
	// that only gets throttled.
	const queue = [...missing];
	await Promise.all(
		Array.from({ length: ELEVATION_CONCURRENCY }, async () => {
			for (let node = queue.shift(); node; node = queue.shift()) {
				node.ele = await elevationM(node.lat, node.lon);
			}
		}),
	);
	const fetched = missing.length;

	const sortedNodes = Object.fromEntries(
		Object.entries(nodes).sort(([a], [b]) => Number(a) - Number(b)),
	);
	const snapshot = {
		fetched_at: new Date().toISOString().slice(0, 10),
		sources: {
			geometry: 'OpenStreetMap API 0.6, © OpenStreetMap contributors, ODbL 1.0',
			elevation: 'USGS 3D Elevation Program, Elevation Point Query Service (public domain)',
		},
		ways,
		nodes: sortedNodes,
	};
	fs.writeFileSync(snapshotPath, `${JSON.stringify(snapshot, null, 1)}\n`);
	console.log(
		`${snapshotPath}: ${Object.keys(ways).length} ways, ${Object.keys(nodes).length} nodes, ${fetched} elevations fetched`,
	);
}

await main();
