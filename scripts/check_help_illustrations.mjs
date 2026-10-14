#!/usr/bin/env node
// Guard: the help-guide illustrations are text-free, theme-painted diagrams,
// and every one is used (docs/features/help.md § Illustrations).
//
// Each file at apps/web/src/lib/help/illustrations/<id>.svg is shown inline on
// web and through flutter_svg on the phones, in every locale and both themes.
// So this fails a file that:
//   - holds anything but the allowed shape elements and painting attributes:
//     a <text> (words nobody translates), <script>, <foreignObject>, <image>,
//     <style>, an href, an event handler or a url(...) reference;
//   - paints a colour outside the token set (currentColor, none and the
//     placeholders in apps/web/src/lib/help/illustration.ts);
//   - has no viewBox, a fixed width / height, or is over the size budget;
//   - no guide references, or whose name is not a kebab-case id;
// and a guide `illustration` block that names no file or has an empty alt.
// Alt-text markup and translation are checked by help_guides_guard.test.ts and
// scripts/check_help_translations.mjs.
//
//   node scripts/check_help_illustrations.mjs

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

import { HELP_DIR, REPO_ROOT, loadGuides } from './gen_help_guides.mjs';

export const ILLUSTRATIONS_DIR = join(HELP_DIR, 'illustrations');

/** @type {{ illustrationProblems: (source: string) => string[], ILLUSTRATION_ID: RegExp }} */
const illustrationModule = await import(pathToFileURL(join(HELP_DIR, 'illustration.ts')).href);

/**
 * Every illustration block in the guides, with where it is.
 *
 * @param {readonly Record<string, unknown>[]} guides
 * @returns {{ where: string, id: unknown, alt: unknown }[]}
 */
export function illustrationBlocks(guides) {
	/** @type {{ where: string, id: unknown, alt: unknown }[]} */
	const out = [];
	for (const guide of guides) {
		const sections = /** @type {{ heading: string, blocks: Record<string, unknown>[] }[]} */ (guide.sections ?? []);
		sections.forEach((section, si) =>
			section.blocks.forEach((block, bi) => {
				if (block.type === 'illustration') {
					out.push({ where: `guides/${guide.id}.ts › section ${si + 1} block ${bi + 1}`, id: block.id, alt: block.alt });
				}
			}),
		);
	}
	return out;
}

/**
 * One message per problem; empty when every file is clean and every block
 * and file match up.
 *
 * @param {{ guides: readonly Record<string, unknown>[], files: readonly { name: string, source: string }[] }} input
 * @returns {string[]}
 */
export function illustrationGuardProblems({ guides, files }) {
	const problems = [];
	const ids = new Set();
	for (const { name, source } of files) {
		const where = `illustrations/${name}`;
		if (!name.endsWith('.svg') || !illustrationModule.ILLUSTRATION_ID.test(name.slice(0, -4))) {
			problems.push(`${where}: only <kebab-case-id>.svg files belong here`);
			continue;
		}
		ids.add(name.slice(0, -4));
		for (const p of illustrationModule.illustrationProblems(source)) problems.push(`${where}: ${p}`);
	}
	const used = new Set();
	for (const { where, id, alt } of illustrationBlocks(guides)) {
		if (typeof id !== 'string' || !ids.has(id)) problems.push(`${where}: illustration "${String(id)}" has no illustrations/${String(id)}.svg`);
		else used.add(id);
		if (typeof alt !== 'string' || alt.trim() === '') problems.push(`${where}: an illustration needs alt text`);
	}
	for (const id of ids) {
		if (!used.has(id)) problems.push(`illustrations/${id}.svg: no guide references it (add an illustration block, or delete the file)`);
	}
	return problems;
}

/** @returns {{ name: string, source: string }[]} */
export function loadIllustrationFiles() {
	let names = [];
	try {
		names = readdirSync(ILLUSTRATIONS_DIR).sort();
	} catch {
		return [];
	}
	return names.map((name) => ({ name, source: readFileSync(join(ILLUSTRATIONS_DIR, name), 'utf8') }));
}

async function main() {
	const problems = illustrationGuardProblems({ guides: await loadGuides(), files: loadIllustrationFiles() });
	if (problems.length > 0) {
		for (const p of problems) console.error(p);
		console.error(
			`\n${problems.length} problem(s) in ${ILLUSTRATIONS_DIR.slice(REPO_ROOT.length + 1)}. See docs/features/help.md § Illustrations.`,
		);
		process.exit(1);
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	await main();
}
