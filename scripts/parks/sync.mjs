#!/usr/bin/env node
// The park catalogue sync (issue #1349, decisions § 2429): every committed
// `catalogue/<region>/<park>/manifest.json`, loaded through
// `private.load_park_catalogue` as the official club in `publisher.json`, by
// the account `private.resolve_club_publisher` picks when it runs, with the
// backfill flag on (the function queues one only for a created course or
// changed matching geometry).
//
// The release runs this as the first stage of `scripts/prod_sync/run.mjs`
// ("Sync production state" in release-backend.yml). Run on its own it prints
// the whole transaction to stdout and connects to nothing, which is the
// manual fallback: pipe it to psql on the service-role connection.
//
// Run: node scripts/parks/sync.mjs [--dry-run] > sync.sql

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { readPayload, readRelease } from './load.mjs';
import { catalogueSyncSql, parkDirsFromManifests, parsePublisher, splitByRelease } from './lib/catalogue_sync.mjs';
import { stageScript } from '../prod_sync/lib/stages.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const CATALOGUE_ROOT = path.join(HERE, 'catalogue');
export const PUBLISHER_FILE = path.join(HERE, 'publisher.json');

/** @param {string} root */
export function findParkDirs(root) {
	/** @type {string[]} */
	const manifests = [];
	for (const region of fs.readdirSync(root, { withFileTypes: true })) {
		if (!region.isDirectory()) continue;
		for (const park of fs.readdirSync(path.join(root, region.name), { withFileTypes: true })) {
			if (park.isDirectory() && fs.existsSync(path.join(root, region.name, park.name, 'manifest.json'))) {
				manifests.push(`${region.name}/${park.name}/manifest.json`);
			}
		}
	}
	return parkDirsFromManifests(manifests).map((dir) => path.join(root, dir));
}

/**
 * The stage the production sync runs. Every park is validated; a staged one
 * (decisions § 2460) is reported `staged` and never loaded.
 *
 * @param {{ root?: string, publisherFile?: string }} [opts]
 */
export function parkCatalogueStage({ root = CATALOGUE_ROOT, publisherFile = PUBLISHER_FILE } = {}) {
	const publisher = parsePublisher(JSON.parse(fs.readFileSync(publisherFile, 'utf8')));
	const { live, staged } = splitByRelease(
		findParkDirs(root).map((dir) => ({ payload: readPayload(dir), release: readRelease(dir) })),
	);
	/** @param {number} n */
	const courses = (n) => `${n} course${n === 1 ? '' : 's'}`;
	const loaded = `${live.length} park(s): ${live.map((p) => `${p.park.slug} (${courses(p.courses.length)})`).join(', ') || 'none'}`;
	const held = staged.map((s) => `${s.park} (${courses(s.courses.length)}): ${s.reason}`);
	return {
		id: 'park-catalogue',
		title: 'Park catalogue',
		sql: catalogueSyncSql(live, publisher, staged),
		note: held.length > 0 ? `${loaded}. Staged, not loaded: ${held.join('; ')}` : loaded,
	};
}

function main() {
	try {
		const args = process.argv.slice(2);
		const unknown = args.filter((a) => a !== '--dry-run');
		if (unknown.length > 0) throw new Error(`unknown argument ${unknown[0]}\nusage: node scripts/parks/sync.mjs [--dry-run]`);
		const stage = parkCatalogueStage();
		process.stdout.write(stageScript(stage.sql, { dryRun: args.includes('--dry-run') }));
		console.error(stage.note);
	} catch (err) {
		console.error(err instanceof Error ? err.message : String(err));
		process.exit(2);
	}
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) main();
