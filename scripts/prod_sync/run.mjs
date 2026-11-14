#!/usr/bin/env node
// Sync production state (issue #1349, decisions § 2429): the "Sync production
// state" step of release-backend.yml. Runs every stage in STAGES against the
// database in SYNC_DB_URL, one transaction per stage, and writes what each did
// to stdout and to $GITHUB_STEP_SUMMARY. `--dry-run` rolls every stage back.
//
// apps/backend/scripts/sync-production-state.sh is the entry point: it builds
// SYNC_DB_URL and PGPASSWORD from the release's database secrets the way
// apply-pending-migrations.sh does, so this file never sees a password and
// never prints the connection string.
//
// To add a concern, add a stage: a function returning { id, title, sql, note? }
// whose SQL leaves exactly one result set (an `action` column, when it has
// one, is counted in the summary), or { id, title, run, note? } for one that
// needs several transactions or the Supabase CLI (lib/stages.mjs).
//
// After the park catalogue come the prod config stages (issue #1350,
// decisions § 2430): apps/backend/ops/prod_config.json's feature flags, Edge
// Function env toggles, web flags and cron URL entries, then the one-off
// tasks in apps/backend/ops/tasks/. The config is guarded before any stage
// runs.
//
// Then the PostgREST row cap check (decisions § 2531): read-only, it
// fails the release when production's db.max-rows is below the one
// config.toml pins, since the clients' keyset walk ends on a page shorter
// than that without a confirming read.
//
// The official content catalogue comes last (issue #1190, decisions § 2446),
// after the config, so a flag the same release turns on (official_race_courses)
// is the one its load reads.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

import { officialCatalogueStage } from '../official/sync.mjs';
import { parkCatalogueStage } from '../parks/sync.mjs';
import { prodConfigStages } from './config.mjs';
import { pinnedMaxRows, postgrestCapStage } from './lib/postgrest_cap.mjs';
import { runStages } from './lib/stages.mjs';

/** @type {(() => import('./lib/stages.mjs').Stage | import('./lib/stages.mjs').Stage[])[]} */
export const STAGES = [parkCatalogueStage, prodConfigStages, postgrestCapCheck, officialCatalogueStage];

export function postgrestCapCheck() {
	const config = fileURLToPath(new URL('../../apps/backend/supabase/config.toml', import.meta.url));
	const reader = fileURLToPath(new URL('./postgrest_max_rows.mjs', import.meta.url));
	return postgrestCapStage(pinnedMaxRows(fs.readFileSync(config, 'utf8')), reader);
}

function main() {
	const args = process.argv.slice(2);
	const unknown = args.filter((a) => a !== '--dry-run');
	if (unknown.length > 0) {
		console.error(`unknown argument ${unknown[0]}\nusage: SYNC_DB_URL=… node scripts/prod_sync/run.mjs [--dry-run]`);
		process.exit(2);
	}
	const dryRun = args.includes('--dry-run');
	const url = process.env.SYNC_DB_URL;
	if (!url) {
		console.error('SYNC_DB_URL is not set; run this through apps/backend/scripts/sync-production-state.sh');
		process.exit(2);
	}
	const summaryFile = process.env.GITHUB_STEP_SUMMARY;

	/** @param {string} markdown */
	const write = (markdown) => {
		process.stdout.write(markdown);
		if (summaryFile) fs.appendFileSync(summaryFile, markdown);
	};

	/** @param {string} script */
	const runSql = (script) => {
		const r = spawnSync('psql', [url, '-X', '-q', '--csv', '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
			input: script,
			encoding: 'utf8',
			maxBuffer: 64 * 1024 * 1024,
		});
		return { ok: r.status === 0, stdout: r.stdout ?? '', stderr: r.stderr || (r.error ? String(r.error) : '') };
	};

	/** @param {string} command @param {string[]} cmdArgs */
	const exec = (command, cmdArgs) => {
		const r = spawnSync(command, cmdArgs, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
		return { ok: r.status === 0, stdout: r.stdout ?? '', stderr: r.stderr || (r.error ? String(r.error) : '') };
	};

	let stages;
	try {
		stages = STAGES.flatMap((build) => build());
	} catch (err) {
		console.error(`::error::a sync stage could not be built: ${err instanceof Error ? err.message : String(err)}`);
		process.exit(1);
	}
	if (!runStages(stages, { dryRun, runSql, write, exec, env: process.env })) {
		console.error('::error::a production sync stage failed and was rolled back; the error is in the step summary above.');
		process.exit(1);
	}
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) main();
