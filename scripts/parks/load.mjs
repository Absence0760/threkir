#!/usr/bin/env node
// Print the SQL that loads one park's built catalogue into the database
// (issue #1342, decisions § 2423). Reads the park's `manifest.json` and course
// GeoJSON, validates them, and writes ONE statement to stdout calling
// `private.load_park_catalogue`. It connects to nothing: the operator runs the
// statement as the service role (Studio's SQL editor, or psql on the
// service-role connection), which creates or updates the park, every course's
// catalogue segment, its park_courses row and its official route.
//
// Run: node scripts/parks/load.mjs scripts/parks/catalogue/us-va/pocahontas \
//        --club-id <official club uuid> --author-id <club owner/admin uuid> [--enqueue-backfill] > load.sql

import fs from 'node:fs';
import path from 'node:path';

import { cataloguePayload, loadSql } from './lib/catalogue_payload.mjs';

const USAGE =
	'usage: node scripts/parks/load.mjs <catalogue/park dir> --club-id <uuid> --author-id <uuid> [--enqueue-backfill]';

/**
 * @param {string[]} args
 * @returns {{ dir: string, clubId: string, authorId: string, enqueueBackfill: boolean }}
 */
export function parseArgs(args) {
	/** @type {string[]} */
	const positional = [];
	/** @type {Record<string, string>} */
	const values = {};
	let enqueueBackfill = false;
	for (let i = 0; i < args.length; i++) {
		const arg = args[i];
		if (arg === '--enqueue-backfill') enqueueBackfill = true;
		else if (arg === '--club-id' || arg === '--author-id') {
			const value = args[++i];
			if (value === undefined || value.startsWith('--')) throw new Error(`${arg} needs a value\n${USAGE}`);
			values[arg] = value;
		} else if (arg.startsWith('--')) throw new Error(`unknown option ${arg}\n${USAGE}`);
		else positional.push(arg);
	}
	if (positional.length !== 1 || !values['--club-id'] || !values['--author-id']) throw new Error(USAGE);
	return { dir: positional[0], clubId: values['--club-id'], authorId: values['--author-id'], enqueueBackfill };
}

/** @param {string} dir */
export function readPayload(dir) {
	const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
	return cataloguePayload(manifest, (file) => {
		if (typeof file !== 'string' || file !== path.basename(file)) {
			throw new Error(`course GeoJSON ${file} must be a file name inside ${dir}`);
		}
		return JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
	});
}

function main() {
	try {
		const { dir, clubId, authorId, enqueueBackfill } = parseArgs(process.argv.slice(2));
		const payload = readPayload(dir);
		process.stdout.write(loadSql(payload, { clubId, authorId, enqueueBackfill }));
		console.error(
			`${payload.park.slug}: ${payload.courses.length} courses (${payload.courses.map((c) => c.slug).join(', ')})`,
		);
	} catch (err) {
		console.error(err instanceof Error ? err.message : String(err));
		process.exit(2);
	}
}

if (import.meta.url === `file://${process.argv[1]}`) main();
