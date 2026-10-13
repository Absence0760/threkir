#!/usr/bin/env node
// Writes the mobile apps' copy of the in-app help guides.
//
// The guides are authored once, as TypeScript, under
// apps/web/src/lib/help/guides/<id>.ts (docs/features/help.md). The Flutter
// apps cannot read those, so this loads every guide file and writes the same
// data as JSON to both twins:
//
//   apps/mobile_android/assets/help/guides.en.json
//   apps/mobile_ios/assets/help/guides.en.json      (byte-identical)
//
// A guide file imports nothing but types, so Node loads it directly with its
// built-in type stripping; no tsx, no install. Output is a JSON array sorted
// by category then id, each guide's keys in the order the contract lists
// them, so a re-run is byte-stable and a diff shows only what changed.
//
//   node scripts/gen_help_guides.mjs           rewrite both files
//   node scripts/gen_help_guides.mjs --check   exit 1 if either is stale (CI)

import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const GUIDES_DIR = join(REPO_ROOT, 'apps', 'web', 'src', 'lib', 'help', 'guides');
export const OUTPUTS = [
	join(REPO_ROOT, 'apps', 'mobile_android', 'assets', 'help', 'guides.en.json'),
	join(REPO_ROOT, 'apps', 'mobile_ios', 'assets', 'help', 'guides.en.json'),
];

const GUIDE_FILE = /^[a-z0-9]+(?:-[a-z0-9]+)*\.ts$/;
const GUIDE_KEYS = [
	'id',
	'title',
	'summary',
	'kind',
	'category',
	'audience',
	'requires',
	'platforms',
	'routes',
	'sections',
	'related',
];
const BLOCK_KEYS = ['type', 'tone', 'text', 'items'];

/**
 * @param {Record<string, unknown>} value
 * @param {readonly string[]} keys
 * @returns {Record<string, unknown>}
 */
function pick(value, keys) {
	/** @type {Record<string, unknown>} */
	const out = {};
	for (const key of keys) if (value[key] !== undefined) out[key] = value[key];
	return out;
}

/**
 * @param {Record<string, unknown>} guide
 * @returns {Record<string, unknown>}
 */
function canonical(guide) {
	const out = pick(guide, GUIDE_KEYS);
	const sections = /** @type {{ heading: string, blocks: Record<string, unknown>[] }[]} */ (guide.sections ?? []);
	out.sections = sections.map((s) => ({ heading: s.heading, blocks: s.blocks.map((b) => pick(b, BLOCK_KEYS)) }));
	return out;
}

/** @returns {Promise<Record<string, unknown>[]>} */
export async function loadGuides() {
	const files = readdirSync(GUIDES_DIR)
		.filter((name) => GUIDE_FILE.test(name))
		.sort();
	/** @type {Record<string, unknown>[]} */
	const guides = [];
	for (const file of files) {
		const mod = await import(pathToFileURL(join(GUIDES_DIR, file)).href);
		if (!mod.guide || typeof mod.guide !== 'object') {
			throw new Error(`${file} does not export \`guide\``);
		}
		guides.push(mod.guide);
	}
	return guides;
}

/**
 * @param {readonly Record<string, unknown>[]} guides
 * @returns {string}
 */
export function renderJson(guides) {
	const key = (/** @type {Record<string, unknown>} */ g) => `${g.category}\u0000${g.id}`;
	const sorted = [...guides].sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0));
	return JSON.stringify(sorted.map(canonical), null, 2) + '\n';
}

/** @returns {string[]} the outputs whose content differs from `expected` */
export function staleOutputs(/** @type {string} */ expected) {
	return OUTPUTS.filter((path) => {
		try {
			return readFileSync(path, 'utf8') !== expected;
		} catch {
			return true;
		}
	});
}

async function main() {
	const json = renderJson(await loadGuides());
	if (process.argv.includes('--check')) {
		const stale = staleOutputs(json);
		if (stale.length > 0) {
			for (const path of stale) console.error(`stale: ${path.slice(REPO_ROOT.length + 1)}`);
			console.error('Run `node scripts/gen_help_guides.mjs` (or `pnpm gen:help-guides`) and commit both files.');
			process.exit(1);
		}
		return;
	}
	for (const path of OUTPUTS) {
		mkdirSync(dirname(path), { recursive: true });
		writeFileSync(path, json);
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	await main();
}
