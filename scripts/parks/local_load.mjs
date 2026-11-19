#!/usr/bin/env node
// Prints the SQL that loads every committed park, staged ones included, into a
// LOCAL stack as the official club (decisions § 2590). bin/seed-demo.sh pipes
// it to psql before the demo dataset; it connects to nothing itself. Never run
// its output anywhere but a local stack: production loads through sync.mjs.
//
// Run: node scripts/parks/local_load.mjs > local_catalogue.sql

import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

import { readPayload } from './load.mjs';
import { CATALOGUE_ROOT, PUBLISHER_FILE, findParkDirs } from './sync.mjs';
import { localCatalogueSql } from './lib/catalogue_local.mjs';
import { parsePublisher } from './lib/catalogue_sync.mjs';
import { stageScript } from '../prod_sync/lib/stages.mjs';

/** @param {{ root?: string, publisherFile?: string }} [opts] */
export function localLoadScript({ root = CATALOGUE_ROOT, publisherFile = PUBLISHER_FILE } = {}) {
	const publisher = parsePublisher(JSON.parse(fs.readFileSync(publisherFile, 'utf8')));
	const payloads = findParkDirs(root).map((dir) => readPayload(dir));
	return {
		payloads,
		script: stageScript(localCatalogueSql(payloads, publisher), { dryRun: false }),
	};
}

function main() {
	try {
		if (process.argv.length > 2) throw new Error('usage: node scripts/parks/local_load.mjs');
		const { payloads, script } = localLoadScript();
		process.stdout.write(script);
		const courses = payloads.reduce((n, p) => n + p.courses.length, 0);
		console.error(`${payloads.length} park(s), ${courses} course(s): ${payloads.map((p) => p.park.slug).join(', ')}`);
	} catch (err) {
		console.error(err instanceof Error ? err.message : String(err));
		process.exit(2);
	}
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) main();
