#!/usr/bin/env node
// `npm run gen:types` / `gen:types:check`: generate apps/web/src/lib/database.types.ts
// from the local stack with the Supabase CLI version CI pins, not whatever
// CLI the workstation has.
//
// Why: `supabase gen types` formats its output differently across CLI
// versions. A newer local CLI (3.2.0) rewrote the whole 10k-line file instead
// of adding one column's three lines, and `gen:types:check` in CI (pinned
// 2.84.2) would have flagged every line. So this reads the pin from ci.yml,
// uses the installed CLI when it is that version, and otherwise runs the
// pinned one through `npx supabase@<pin>`. A CLI older than 2.108.0 cannot
// parse config.toml's `[local_smtp]` section, so it runs against a temporary
// copy of the config with the same rename CI applies
// (.github/actions/setup-supabase-cli/local_smtp_compat.sh).
//
// Run: node scripts/gen_types.mjs [--check]   (from apps/backend)

import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const BACKEND = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPO = path.resolve(BACKEND, '..', '..');
const CI = path.join(REPO, '.github', 'workflows', 'ci.yml');
const COMPAT = path.join(REPO, '.github', 'actions', 'setup-supabase-cli', 'local_smtp_compat.sh');
const TYPES = path.join(REPO, 'apps', 'web', 'src', 'lib', 'database.types.ts');

/**
 * The one Supabase CLI version ci.yml installs. Every `setup-supabase-cli`
 * step names its `version:`; they must agree, or there is no single pin to
 * match.
 *
 * @param {string} ciYml
 * @returns {string}
 */
export function pinnedCliVersion(ciYml) {
	const versions = new Set();
	const lines = ciYml.split('\n');
	lines.forEach((line, i) => {
		if (!line.includes('./.github/actions/setup-supabase-cli')) return;
		for (const next of lines.slice(i + 1, i + 8)) {
			const m = /^\s+version:\s*['"]?([\d.]+)['"]?\s*$/.exec(next);
			if (m) {
				versions.add(m[1]);
				break;
			}
		}
	});
	if (versions.size !== 1) {
		throw new Error(`ci.yml's setup-supabase-cli steps name ${versions.size === 0 ? 'no' : 'several'} CLI versions (${[...versions].join(', ')}); expected one pin`);
	}
	return /** @type {string} */ ([...versions][0]);
}

/**
 * Drop the CLI's non-type lines from its stdout, as the old one-liner did.
 *
 * @param {string} out
 */
export function stripCliNoise(out) {
	return out
		.split('\n')
		.filter((l) => !l.startsWith('Connecting to db') && !l.startsWith('{"_tag":"Error"'))
		.join('\n');
}

function installedVersion() {
	const r = spawnSync('supabase', ['--version'], { encoding: 'utf8' });
	return r.status === 0 ? r.stdout.trim() : null;
}

function main() {
	const check = process.argv.includes('--check');
	const pin = pinnedCliVersion(fs.readFileSync(CI, 'utf8'));
	const cli = installedVersion() === pin ? ['supabase'] : ['npx', '-y', `supabase@${pin}`];

	const workdir = fs.mkdtempSync(path.join(os.tmpdir(), 'gen-types-'));
	try {
		fs.mkdirSync(path.join(workdir, 'supabase'));
		const config = path.join(workdir, 'supabase', 'config.toml');
		fs.copyFileSync(path.join(BACKEND, 'supabase', 'config.toml'), config);
		// CI's setup-supabase-cli has already renamed the section in its
		// checkout; the compat script refuses a config with nothing to rename.
		if (/^\[local_smtp\]/m.test(fs.readFileSync(config, 'utf8'))) {
			execFileSync('bash', [COMPAT, pin, config], { stdio: ['ignore', 'ignore', 'inherit'] });
		}

		const [cmd, ...pre] = cli;
		const r = spawnSync(cmd, [...pre, 'gen', 'types', 'typescript', '--local', '--workdir', workdir], {
			encoding: 'utf8',
			maxBuffer: 64 * 1024 * 1024,
		});
		if (r.status !== 0) {
			process.stderr.write(r.stderr);
			throw new Error(`supabase ${pin} gen types failed (exit ${r.status}); is the local stack running?`);
		}
		const types = stripCliNoise(r.stdout);
		if (!check) {
			fs.writeFileSync(TYPES, types);
			console.error(`wrote ${path.relative(REPO, TYPES)} with Supabase CLI ${pin}`);
			return;
		}
		if (fs.readFileSync(TYPES, 'utf8') === types) return;
		const diff = spawnSync('diff', ['-u', TYPES, '-'], { input: types, encoding: 'utf8' });
		process.stdout.write(diff.stdout);
		process.exitCode = 1;
	} finally {
		fs.rmSync(workdir, { recursive: true, force: true });
	}
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) main();
