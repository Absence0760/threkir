#!/usr/bin/env node
// The official content catalogue sync (issue #1190, decisions § 2446): every
// committed item under `catalogue/<kind>/<slug>.json`, loaded through
// `private.load_official_catalogue` as the official club in
// scripts/parks/publisher.json, by the account
// `private.resolve_club_publisher` picks when it runs.
//
// The release runs this as a stage of scripts/prod_sync/run.mjs ("Sync
// production state" in release-backend.yml), after the prod config stages so a
// flag flipped in the same release (official_race_courses) is the one the
// load reads. Run on its own it prints the whole transaction to stdout and
// connects to nothing, which is the manual fallback: pipe it to psql on the
// service-role connection.
//
// Run: node scripts/official/sync.mjs [--dry-run] > official.sql

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { KINDS, catalogueNote, checkCatalogue, officialCatalogueSql } from './lib/official_catalogue.mjs';
import { parsePublisher } from '../parks/lib/catalogue_sync.mjs';
import { PUBLISHER_FILE } from '../parks/sync.mjs';
import { stageScript } from '../prod_sync/lib/stages.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const CATALOGUE_ROOT = path.join(HERE, 'catalogue');

/**
 * Every `<kind>/<slug>.json` under the root, sorted by file name so the load
 * order is stable. Every kind needs its directory (an empty kind keeps a
 * `.gitkeep`), so a checkout missing one is refused rather than read as an
 * empty list the load would retire everything from; a file whose name is not
 * its slug is refused, so a rename cannot load a second copy.
 *
 * @param {string} root
 * @returns {import('./lib/official_catalogue.mjs').Catalogue}
 */
export function readCatalogue(root = CATALOGUE_ROOT) {
	/** @type {any} */
	const catalogue = {};
	for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
		if (entry.isDirectory() && !(/** @type {readonly string[]} */ (KINDS)).includes(entry.name)) {
			throw new Error(`catalogue/${entry.name} is not a kind (${KINDS.join(', ')})`);
		}
	}
	for (const kind of KINDS) {
		const dir = path.join(root, kind);
		if (!fs.existsSync(dir)) throw new Error(`catalogue/${kind} is missing; an empty kind keeps a .gitkeep`);
		const files = fs.readdirSync(dir).filter((f) => !f.startsWith('.')).sort();
		catalogue[kind] = files.map((file) => {
			if (!file.endsWith('.json')) throw new Error(`catalogue/${kind}/${file} is not a .json item`);
			const item = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
			if (`${item.slug}.json` !== file) {
				throw new Error(`catalogue/${kind}/${file} holds the slug ${item.slug}; name the file <slug>.json`);
			}
			return item;
		});
	}
	return checkCatalogue(catalogue);
}

/**
 * The stage the production sync runs.
 *
 * @param {{ root?: string, publisherFile?: string }} [opts]
 */
export function officialCatalogueStage({ root = CATALOGUE_ROOT, publisherFile = PUBLISHER_FILE } = {}) {
	const publisher = parsePublisher(JSON.parse(fs.readFileSync(publisherFile, 'utf8')));
	const catalogue = readCatalogue(root);
	return {
		id: 'official-catalogue',
		title: 'Official content catalogue',
		sql: officialCatalogueSql(catalogue, publisher),
		note: catalogueNote(catalogue),
	};
}

function main() {
	try {
		const args = process.argv.slice(2);
		const unknown = args.filter((a) => a !== '--dry-run');
		if (unknown.length > 0) throw new Error(`unknown argument ${unknown[0]}\nusage: node scripts/official/sync.mjs [--dry-run]`);
		const stage = officialCatalogueStage();
		process.stdout.write(stageScript(stage.sql, { dryRun: args.includes('--dry-run') }));
		console.error(stage.note);
	} catch (err) {
		console.error(err instanceof Error ? err.message : String(err));
		process.exit(2);
	}
}

if (import.meta.url === `file://${process.argv[1]}`) main();
