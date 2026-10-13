#!/usr/bin/env node
// Guard: every string of a translated help guide translates the English
// string at the same place as it reads NOW (docs/features/help.md
// § Translation, decisions § 1871).
//
// Each file at apps/web/src/lib/help/translations/<locale>/<id>.ts records, in
// `sources`, a hash of the English each string was translated from, keyed by
// the string's path (`title`, `summary`, `s0.heading`, `s0.b1`, `s0.b1.i2`;
// see `translatableStrings` in apps/web/src/lib/help/translate.ts). When the
// English string changes, its hash no longer matches and this fails, naming
// that string and only that string: a translation that silently kept
// describing the old screen would be worse than the English fallback a reader
// gets with no translation at all. Fix it by re-translating the named strings
// and recording their new hashes, or by deleting the file so the guide falls
// back to English until it is translated again.
//
// Also failed: a translation of no guide, a directory that is not a
// translated locale, a file that does not export `translation` or imports
// anything but its type, a translation whose sections and blocks do not line
// up with the guide's, and a `sources` map missing a string or naming one the
// guide does not have. Markup, links and lengths in translated text are
// checked by apps/web/src/lib/help/help_guides_guard.test.ts, which has the
// markup parser.
//
//   node scripts/check_help_translations.mjs                     check (CI)
//   node scripts/check_help_translations.mjs --hash <id>         print a guide's `sources` map
//   node scripts/check_help_translations.mjs --hash <id> <path>  print one string's hash

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

import {
	GUIDE_FILE,
	HELP_DIR,
	REPO_ROOT,
	TRANSLATED_LOCALES,
	TRANSLATIONS_DIR,
	loadGuides,
	loadTranslations,
} from './gen_help_guides.mjs';

/**
 * @type {{
 *   translatableStrings: (guide: object) => [string, string][],
 *   describePath: (path: string) => string,
 *   structureProblems: (guide: object, translation: object) => string[],
 * }}
 */
const translateModule = await import(pathToFileURL(join(HELP_DIR, 'translate.ts')).href);

export const ONLY_IMPORT = "import type { GuideTranslation } from '../../types';";
const HASH = /^[0-9a-f]{16}$/;

/**
 * The hash a translation records for one English string: the first 16 hex
 * digits of its SHA-256.
 *
 * @param {string} text
 * @returns {string}
 */
export function stringHash(text) {
	return createHash('sha256').update(text).digest('hex').slice(0, 16);
}

/**
 * The `sources` map a current translation of `guide` records, in path order.
 *
 * @param {object} guide
 * @returns {Record<string, string>}
 */
export function sourceHashes(guide) {
	return Object.fromEntries(translateModule.translatableStrings(guide).map(([path, text]) => [path, stringHash(text)]));
}

const excerpt = (/** @type {string} */ text) => (text.length > 70 ? `${text.slice(0, 67)}...` : text);

/**
 * @typedef {{ locale: string, file: string, translation: Record<string, unknown> | undefined, text?: string }} TranslationFile
 */

/**
 * One message per problem, each naming the file and, for a stale string, the
 * string; empty when every translation is current.
 *
 * @param {{
 *   guides: readonly Record<string, unknown>[],
 *   translations: readonly TranslationFile[],
 *   locales?: readonly string[],
 *   dirs?: readonly string[],
 * }} input
 * @returns {string[]}
 */
export function translationProblems({ guides, translations, locales = TRANSLATED_LOCALES, dirs = [] }) {
	const problems = [];
	const byId = new Map(guides.map((g) => [g.id, g]));
	for (const dir of dirs) {
		if (!locales.includes(dir)) problems.push(`translations/${dir}/: not a translated locale (${locales.join(', ')})`);
	}
	for (const { locale, file, translation, text } of translations) {
		const where = `translations/${locale}/${file}`;
		if (!locales.includes(locale)) continue;
		if (!GUIDE_FILE.test(file)) {
			problems.push(`${where}: translation files are <guide-id>.ts`);
			continue;
		}
		if (text !== undefined) {
			const imports = text.split('\n').filter((line) => /^\s*import\b/.test(line));
			if (imports.length !== 1 || imports[0] !== ONLY_IMPORT) {
				problems.push(`${where}: the only import allowed is \`${ONLY_IMPORT}\``);
			}
		}
		if (!translation) {
			problems.push(`${where}: does not export \`translation\``);
			continue;
		}
		const id = file.replace(/\.ts$/, '');
		if (translation.id !== id) problems.push(`${where}: id "${translation.id}" does not match the file name`);
		const guide = byId.get(id);
		if (!guide) {
			problems.push(`${where}: there is no English guide "${id}" (guides/${id}.ts)`);
			continue;
		}
		const structure = translateModule.structureProblems(guide, translation);
		for (const p of structure) problems.push(`${where}: ${p}`);
		if (structure.length > 0) continue;
		const sources = translation.sources;
		if (!sources || typeof sources !== 'object' || Array.isArray(sources)) {
			problems.push(`${where}: \`sources\` must map each string's path to the hash of its English (node scripts/check_help_translations.mjs --hash ${id})`);
			continue;
		}
		const recorded = /** @type {Record<string, unknown>} */ (sources);
		const strings = translateModule.translatableStrings(guide);
		const paths = new Set(strings.map(([path]) => path));
		for (const [path, english] of strings) {
			const at = `${where} › ${path} (${translateModule.describePath(path)})`;
			const current = stringHash(english);
			const hash = recorded[path];
			if (typeof hash !== 'string' || !HASH.test(hash)) {
				problems.push(`${at}: no 16-hex-digit source hash (the English now hashes to ${current})`);
			} else if (hash !== current) {
				problems.push(
					`${at}: stale — the English changed since this was translated; it now reads "${excerpt(english)}" (recorded ${hash}, now ${current})`,
				);
			}
		}
		for (const path of Object.keys(recorded)) {
			if (!paths.has(path)) problems.push(`${where}: \`sources\` names ${path}, which the guide does not have`);
		}
	}
	return problems;
}

function translationDirs() {
	try {
		return readdirSync(TRANSLATIONS_DIR, { withFileTypes: true })
			.filter((e) => e.isDirectory())
			.map((e) => e.name);
	} catch {
		return [];
	}
}

async function main() {
	const guides = await loadGuides();
	const hashAt = process.argv.indexOf('--hash');
	if (hashAt !== -1) {
		const id = process.argv[hashAt + 1];
		const path = process.argv[hashAt + 2];
		const guide = guides.find((g) => g.id === id);
		if (!guide) {
			console.error(`no guide "${id}" under apps/web/src/lib/help/guides`);
			process.exit(1);
		}
		const hashes = sourceHashes(guide);
		if (path === undefined) {
			console.log(JSON.stringify(hashes, null, '\t'));
		} else if (path in hashes) {
			console.log(hashes[path]);
		} else {
			console.error(`guide "${id}" has no string at ${path}`);
			process.exit(1);
		}
		return;
	}
	const translations = (await loadTranslations()).map((t) => ({
		...t,
		text: readFileSync(join(TRANSLATIONS_DIR, t.locale, t.file), 'utf8'),
	}));
	const problems = translationProblems({ guides, translations, dirs: translationDirs() });
	if (problems.length > 0) {
		for (const p of problems) console.error(p);
		console.error(
			`\n${problems.length} problem(s) in ${TRANSLATIONS_DIR.slice(REPO_ROOT.length + 1)}. ` +
				'Re-translate each stale string and set its `sources` entry to the "now" hash, or delete the file so the guide falls back to English. ' +
				'See docs/features/help.md § Translation.',
		);
		process.exit(1);
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	await main();
}
