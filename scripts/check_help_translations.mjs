#!/usr/bin/env node
// Guard: a translated help guide is a translation of the English guide as it
// is NOW (docs/features/help.md § Translation, decisions § R7I18N-1).
//
// Each file at apps/web/src/lib/help/translations/<locale>/<id>.ts records, in
// `source`, a hash of the English text it was translated from. When the
// English guide changes, the hash no longer matches and this fails: a
// translation that silently kept describing the old screen would be worse
// than the English fallback a reader gets with no translation at all. Fix it
// by re-translating and recording the new hash, or by deleting the stale file
// so the guide falls back to English until it is translated again.
//
// Also failed: a translation of no guide, a directory that is not a
// translated locale, a file that does not export `translation` or imports
// anything but its type, and a translation whose sections and blocks do not
// line up with the guide's. Markup, links and lengths in translated text are
// checked by apps/web/src/lib/help/help_guides_guard.test.ts, which has the
// markup parser.
//
//   node scripts/check_help_translations.mjs              check (CI)
//   node scripts/check_help_translations.mjs --hash <id>  print a guide's current hash

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
 *   translatableText: (guide: object) => unknown,
 *   structureProblems: (guide: object, translation: object) => string[],
 * }}
 */
const translateModule = await import(pathToFileURL(join(HELP_DIR, 'translate.ts')).href);

export const ONLY_IMPORT = "import type { GuideTranslation } from '../../types';";
const HASH = /^[0-9a-f]{16}$/;

/**
 * The hash a translation of `guide` records: the first 16 hex digits of the
 * SHA-256 of the guide's translatable text.
 *
 * @param {object} guide
 * @returns {string}
 */
export function sourceHash(guide) {
	return createHash('sha256').update(JSON.stringify(translateModule.translatableText(guide))).digest('hex').slice(0, 16);
}

/**
 * @typedef {{ locale: string, file: string, translation: Record<string, unknown> | undefined, text?: string }} TranslationFile
 */

/**
 * One message per problem, each naming the file; empty when every
 * translation is current.
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
		for (const p of translateModule.structureProblems(guide, translation)) problems.push(`${where}: ${p}`);
		const current = sourceHash(guide);
		if (typeof translation.source !== 'string' || !HASH.test(translation.source)) {
			problems.push(`${where}: \`source\` must be the 16-hex-digit hash of the English text it translates (now ${current})`);
		} else if (translation.source !== current) {
			problems.push(
				`${where}: stale — guides/${id}.ts has changed since this was translated (recorded ${translation.source}, now ${current}). ` +
					`Re-translate the changed text and set source: '${current}', or delete this file so the guide falls back to English.`,
			);
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
		const guide = guides.find((g) => g.id === id);
		if (!guide) {
			console.error(`no guide "${id}" under apps/web/src/lib/help/guides`);
			process.exit(1);
		}
		console.log(sourceHash(guide));
		return;
	}
	const translations = (await loadTranslations()).map((t) => ({
		...t,
		text: readFileSync(join(TRANSLATIONS_DIR, t.locale, t.file), 'utf8'),
	}));
	const problems = translationProblems({ guides, translations, dirs: translationDirs() });
	if (problems.length > 0) {
		for (const p of problems) console.error(p);
		console.error(`\n${problems.length} problem(s) in ${TRANSLATIONS_DIR.slice(REPO_ROOT.length + 1)}. See docs/features/help.md § Translation.`);
		process.exit(1);
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	await main();
}
