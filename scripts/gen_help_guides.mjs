#!/usr/bin/env node
// Writes the per-locale JSON copies of the in-app help guides.
//
// The guides are authored once, as TypeScript: the English guide at
// apps/web/src/lib/help/guides/<id>.ts and its translations at
// apps/web/src/lib/help/translations/<locale>/<id>.ts (docs/features/help.md).
// The Flutter apps cannot read those, and the web fetches a translation
// rather than bundling all six, so this loads every guide and translation and
// writes one JSON array per locale, each guide already in that locale (or in
// English, with `lang: "en"`, where it has no translation):
//
//   apps/mobile_android/assets/help/guides.<locale>.json   every locale
//   apps/mobile_ios/assets/help/guides.<locale>.json       byte-identical
//   apps/web/static/help-guides/guides.<locale>.json       every locale but en,
//                                                          which web bundles
//
// Guide and translation files import nothing but types, so Node loads them
// directly with its built-in type stripping; no tsx, no install. Each array is
// sorted by category then id, each guide's keys in the order the contract
// lists them, so a re-run is byte-stable and a diff shows only what changed.
//
//   node scripts/gen_help_guides.mjs           rewrite every file
//   node scripts/gen_help_guides.mjs --check   exit 1 if any is stale (CI)

import { mkdirSync, readFileSync, readdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const HELP_DIR = join(REPO_ROOT, 'apps', 'web', 'src', 'lib', 'help');
export const GUIDES_DIR = join(HELP_DIR, 'guides');
export const TRANSLATIONS_DIR = join(HELP_DIR, 'translations');
export const OUTPUT_DIRS = {
	android: join(REPO_ROOT, 'apps', 'mobile_android', 'assets', 'help'),
	ios: join(REPO_ROOT, 'apps', 'mobile_ios', 'assets', 'help'),
	web: join(REPO_ROOT, 'apps', 'web', 'static', 'help-guides'),
};

/** @type {{ SUPPORTED_LOCALES: readonly string[], DEFAULT_LOCALE: string }} */
const localeModule = await import(pathToFileURL(join(REPO_ROOT, 'apps', 'web', 'src', 'lib', 'i18n', 'locale.ts')).href);
/** @type {{ localizeGuide: (guide: object, translation: object | undefined, lang: string) => Record<string, unknown> }} */
const translateModule = await import(pathToFileURL(join(HELP_DIR, 'translate.ts')).href);

export const SOURCE_LOCALE = localeModule.DEFAULT_LOCALE;
export const LOCALES = [...localeModule.SUPPORTED_LOCALES];
export const TRANSLATED_LOCALES = LOCALES.filter((l) => l !== SOURCE_LOCALE);

export const GUIDE_FILE = /^[a-z0-9]+(?:-[a-z0-9]+)*\.ts$/;
const OUTPUT_FILE = /^guides\.[A-Za-z-]+\.json$/;
const GUIDE_KEYS = [
	'id',
	'lang',
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

/**
 * @param {string} dir
 * @param {string} exportName
 * @returns {Promise<{ file: string, value: Record<string, unknown> | undefined }[]>}
 */
async function loadDir(dir, exportName) {
	const files = readdirSync(dir)
		.filter((name) => GUIDE_FILE.test(name))
		.sort();
	const out = [];
	for (const file of files) {
		const mod = await import(pathToFileURL(join(dir, file)).href);
		const value = mod[exportName];
		out.push({ file, value: value && typeof value === 'object' ? value : undefined });
	}
	return out;
}

/** @returns {Promise<Record<string, unknown>[]>} */
export async function loadGuides() {
	const guides = [];
	for (const { file, value } of await loadDir(GUIDES_DIR, 'guide')) {
		if (!value) throw new Error(`${file} does not export \`guide\``);
		guides.push(value);
	}
	return guides;
}

/**
 * Every translation file, by locale directory, including any the
 * translation guard would refuse (an unknown locale, a missing export).
 *
 * @returns {Promise<{ locale: string, file: string, translation: Record<string, unknown> | undefined }[]>}
 */
export async function loadTranslations() {
	/** @type {string[]} */
	let locales = [];
	try {
		locales = readdirSync(TRANSLATIONS_DIR, { withFileTypes: true })
			.filter((e) => e.isDirectory())
			.map((e) => e.name)
			.sort();
	} catch {
		return [];
	}
	const out = [];
	for (const locale of locales) {
		for (const { file, value } of await loadDir(join(TRANSLATIONS_DIR, locale), 'translation')) {
			out.push({ locale, file, translation: value });
		}
	}
	return out;
}

/**
 * The guides in `lang`, as one JSON array.
 *
 * @param {readonly Record<string, unknown>[]} guides
 * @param {readonly { locale: string, translation: Record<string, unknown> | undefined }[]} [translations]
 * @param {string} [lang]
 * @returns {string}
 */
export function renderJson(guides, translations = [], lang = SOURCE_LOCALE) {
	/** @type {Map<unknown, Record<string, unknown>>} */
	const mine = new Map();
	for (const t of translations) if (t.locale === lang && t.translation) mine.set(t.translation.id, t.translation);
	const key = (/** @type {Record<string, unknown>} */ g) => `${g.category}\u0000${g.id}`;
	const sorted = [...guides].sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0));
	const localized = sorted.map((g) => translateModule.localizeGuide(g, mine.get(g.id), lang));
	return JSON.stringify(localized.map(canonical), null, 2) + '\n';
}

/**
 * Every file this generator owns, with the content it should hold.
 *
 * @param {readonly Record<string, unknown>[]} guides
 * @param {readonly { locale: string, translation: Record<string, unknown> | undefined }[]} translations
 * @returns {Map<string, string>}
 */
export function renderAll(guides, translations) {
	/** @type {Map<string, string>} */
	const out = new Map();
	for (const locale of LOCALES) {
		const json = renderJson(guides, translations, locale);
		const name = `guides.${locale}.json`;
		out.set(join(OUTPUT_DIRS.android, name), json);
		out.set(join(OUTPUT_DIRS.ios, name), json);
		if (locale !== SOURCE_LOCALE) out.set(join(OUTPUT_DIRS.web, name), json);
	}
	return out;
}

/**
 * The owned files whose content differs from `expected`, plus any
 * `guides.*.json` in an output directory that `expected` does not name.
 *
 * @param {Map<string, string>} expected
 * @returns {string[]}
 */
export function staleOutputs(expected) {
	const stale = [];
	for (const [path, content] of expected) {
		let current;
		try {
			current = readFileSync(path, 'utf8');
		} catch {
			current = undefined;
		}
		if (current !== content) stale.push(path);
	}
	for (const dir of Object.values(OUTPUT_DIRS)) {
		let names = [];
		try {
			names = readdirSync(dir);
		} catch {
			continue;
		}
		for (const name of names) {
			const path = join(dir, name);
			if (OUTPUT_FILE.test(name) && !expected.has(path)) stale.push(path);
		}
	}
	return stale;
}

async function main() {
	const expected = renderAll(await loadGuides(), await loadTranslations());
	if (process.argv.includes('--check')) {
		const stale = staleOutputs(expected);
		if (stale.length > 0) {
			for (const path of stale) console.error(`stale: ${path.slice(REPO_ROOT.length + 1)}`);
			console.error('Run `node scripts/gen_help_guides.mjs` (or `pnpm gen:help-guides`) and commit every file it writes or removes.');
			process.exit(1);
		}
		return;
	}
	for (const path of staleOutputs(expected)) if (!expected.has(path)) unlinkSync(path);
	for (const [path, content] of expected) {
		mkdirSync(dirname(path), { recursive: true });
		writeFileSync(path, content);
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	await main();
}
