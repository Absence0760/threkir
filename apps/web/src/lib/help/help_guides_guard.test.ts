// Guard-rail for the in-app help guides (docs/features/help.md § Guards).
//
// A guide is data a reader acts on, and nothing about a page breaks when the
// guide describing it goes stale: a renamed route, a deleted guide another one
// links to, an unclosed `**` that renders as two asterisks. Every rule below is
// one of those, checked over the files on disk rather than the Vite-built
// index, so the unit suite (raw tsx) sees exactly what the build bundles and
// what scripts/gen_help_guides.mjs ships to the phone apps.
//
//   npx tsx --test src/lib/help/help_guides_guard.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

import { AUDIENCES, GUIDE_CATEGORIES, GUIDE_KINDS, PLATFORMS, REQUIREMENTS } from './catalogue';
import { markupProblems, parseMarkup, plainText, sectionId, type HelpToken } from './markup';
import type { Block, Guide, GuideTranslation } from './types';

const HELP_DIR = import.meta.dirname;
const GUIDES_DIR = join(HELP_DIR, 'guides');
const TRANSLATIONS_DIR = join(HELP_DIR, 'translations');
const SRC = resolve(HELP_DIR, '..', '..');
const ROUTES = join(SRC, 'routes');
const REPO_ROOT = resolve(SRC, '..', '..', '..');

const GUIDE_FILE = /^[a-z0-9]+(?:-[a-z0-9]+)*\.ts$/;
const KEBAB = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const PICTOGRAPH = /\p{Extended_Pictographic}/u;
const ONLY_IMPORT = "import type { Guide } from '../types';";

const files = readdirSync(GUIDES_DIR)
	.filter((name) => name.endsWith('.ts'))
	.sort();
const guides: { file: string; guide: Guide }[] = [];
for (const file of files) {
	const mod = (await import(pathToFileURL(join(GUIDES_DIR, file)).href)) as { guide?: Guide };
	if (mod.guide) guides.push({ file, guide: mod.guide });
}
const byId = new Map(guides.map(({ guide }) => [guide.id, guide]));

const translations: { locale: string; translation: GuideTranslation }[] = [];
for (const locale of existsSync(TRANSLATIONS_DIR) ? readdirSync(TRANSLATIONS_DIR).sort() : []) {
	for (const file of readdirSync(join(TRANSLATIONS_DIR, locale)).filter((f) => GUIDE_FILE.test(f)).sort()) {
		const mod = (await import(pathToFileURL(join(TRANSLATIONS_DIR, locale, file)).href)) as {
			translation?: GuideTranslation;
		};
		if (mod.translation) translations.push({ locale, translation: mod.translation });
	}
}

function blockTexts(block: Block): string[] {
	return block.type === 'steps' || block.type === 'list' ? block.items : [block.text];
}

/// Every string a guide renders through the markup parser, with where it is.
function markupStrings(g: Guide): { where: string; text: string }[] {
	return g.sections.flatMap((s) =>
		s.blocks.flatMap((b, i) => blockTexts(b).map((text) => ({ where: `${g.id} › ${s.heading} › block ${i}`, text }))),
	);
}

function routeExists(routeId: string): boolean {
	if (!routeId.startsWith('/')) return false;
	return existsSync(join(ROUTES, routeId.slice(1), '+page.svelte'));
}

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) svelteFiles(full, out);
		else if (entry.name.endsWith('.svelte')) out.push(full);
	}
	return out;
}

/// The attribute text of every `<Name ...>` tag in `source`. Walks the tag
/// rather than regex-matching to `>`, because an attribute expression such as
/// `onclick={() => x}` holds a `>` of its own.
function tagAttributes(source: string, name: string): string[] {
	const out: string[] = [];
	const open = new RegExp(`<${name}(?![\\w-])`, 'g');
	for (const match of source.matchAll(open)) {
		let depth = 0;
		let quote: string | null = null;
		let i = match.index + match[0].length;
		for (; i < source.length; i++) {
			const c = source[i];
			if (quote) {
				if (c === quote) quote = null;
			} else if (c === '"' || c === "'") {
				if (depth === 0) quote = c;
			} else if (c === '{') {
				depth++;
			} else if (c === '}') {
				depth--;
			} else if (c === '>' && depth === 0) {
				break;
			}
		}
		out.push(source.slice(match.index + match[0].length, i));
	}
	return out;
}

/// `name="literal"` from a tag's attributes: the literal, `null` when the
/// attribute is absent, or `undefined` when it is present but not a literal.
function literalAttribute(attributes: string, name: string): string | null | undefined {
	const literal = new RegExp(`(?:^|\\s)${name}="([^"{}]*)"`).exec(attributes);
	if (literal) return literal[1];
	return new RegExp(`(?:^|\\s)${name}(?:=|\\s|$)`).test(attributes) || new RegExp(`\\{${name}\\}`).test(attributes)
		? undefined
		: null;
}

test('the guides directory holds at least one guide, and only guide files', () => {
	assert.ok(guides.length > 0, 'no guides loaded');
	for (const file of files) {
		assert.match(file, GUIDE_FILE, `${file}: guide files are <kebab-case-id>.ts (no tests or helpers in guides/)`);
	}
	assert.equal(guides.length, files.length, 'every file in guides/ must export `guide`');
});

test("every guide's id equals its file name", () => {
	for (const { file, guide } of guides) {
		assert.match(guide.id, KEBAB, `${file}: id must be kebab-case`);
		assert.equal(`${guide.id}.ts`, file, `${file}: id "${guide.id}" does not match the file name`);
	}
});

test('a guide file imports nothing at run time', () => {
	for (const file of files) {
		const source = readFileSync(join(GUIDES_DIR, file), 'utf8');
		const imports = source.split('\n').filter((line) => /^\s*import\b/.test(line));
		assert.deepEqual(imports, [ONLY_IMPORT], `${file}: the only import allowed is \`${ONLY_IMPORT}\``);
	}
});

test('titles and summaries fit, and read as one plain sentence', () => {
	for (const { guide } of guides) {
		assert.ok(guide.title.trim().length > 0 && guide.title.length <= 70, `${guide.id}: title must be 1-70 chars`);
		assert.ok(
			guide.summary.trim().length > 0 && guide.summary.length <= 160,
			`${guide.id}: summary must be 1-160 chars (is ${guide.summary.length})`,
		);
		assert.doesNotMatch(guide.summary, /[.!?]\s+[A-Z]/, `${guide.id}: summary must be one sentence`);
		for (const value of [guide.title, guide.summary, ...guide.sections.map((s) => s.heading)]) {
			assert.equal(plainText(value), value, `${guide.id}: "${value}" may not carry markup (titles, summaries and headings are plain)`);
		}
	}
});

test('kinds, categories, audiences, requirements and platforms are known values', () => {
	const check = <T extends string>(id: string, field: string, values: readonly T[], known: readonly T[]) => {
		for (const v of values) assert.ok(known.includes(v), `${id}: unknown ${field} "${v}"`);
		assert.equal(new Set(values).size, values.length, `${id}: duplicate ${field}`);
	};
	for (const { guide } of guides) {
		check(guide.id, 'kind', [guide.kind], GUIDE_KINDS);
		check(guide.id, 'category', [guide.category], GUIDE_CATEGORIES);
		assert.ok(guide.audience.length > 0, `${guide.id}: audience is empty`);
		check(guide.id, 'audience', guide.audience, AUDIENCES);
		check(guide.id, 'requirement', guide.requires ?? [], REQUIREMENTS);
		assert.ok(guide.platforms.length > 0, `${guide.id}: platforms is empty`);
		check(guide.id, 'platform', guide.platforms, PLATFORMS);
	}
});

test('every guide has sections, every section has content, and headings are unique anchors', () => {
	for (const { guide } of guides) {
		assert.ok(guide.sections.length > 0, `${guide.id}: no sections`);
		const anchors = guide.sections.map((s) => sectionId(s.heading));
		for (const [i, a] of anchors.entries()) {
			assert.match(a, KEBAB, `${guide.id}: heading "${guide.sections[i]?.heading}" has no usable anchor`);
		}
		assert.equal(new Set(anchors).size, anchors.length, `${guide.id}: two section headings share an anchor`);
		for (const s of guide.sections) {
			assert.ok(s.blocks.length > 0, `${guide.id} › ${s.heading}: no blocks`);
			for (const b of s.blocks) {
				for (const text of blockTexts(b)) assert.ok(text.trim().length > 0, `${guide.id} › ${s.heading}: empty text`);
				if (b.type === 'steps' || b.type === 'list') assert.ok(b.items.length > 0, `${guide.id} › ${s.heading}: empty ${b.type}`);
			}
		}
	}
});

test('no stray or unknown markup, no HTML, no emoji', () => {
	const problems: string[] = [];
	for (const { guide } of guides) {
		for (const { where, text } of markupStrings(guide)) {
			for (const p of markupProblems(text)) problems.push(`${where}: ${p}`);
		}
		const everything = JSON.stringify(guide);
		if (PICTOGRAPH.test(everything)) problems.push(`${guide.id}: emoji in guide text`);
	}
	assert.deepEqual(problems, []);
});

test('every [[guide:]] link and related id resolves to another guide', () => {
	const broken: string[] = [];
	for (const { guide } of guides) {
		for (const { where, text } of markupStrings(guide)) {
			for (const t of parseMarkup(text)) {
				if (t.kind === 'guide' && !byId.has(t.id)) broken.push(`${where}: [[guide:${t.id}]]`);
			}
		}
		for (const r of guide.related ?? []) {
			if (!byId.has(r)) broken.push(`${guide.id}: related "${r}"`);
			if (r === guide.id) broken.push(`${guide.id}: related to itself`);
		}
		if (new Set(guide.related ?? []).size !== (guide.related ?? []).length) broken.push(`${guide.id}: duplicate related`);
	}
	assert.deepEqual(broken, []);
});

test('every [[route:]] link and routes entry is a real SvelteKit page', () => {
	const missing: string[] = [];
	for (const { guide } of guides) {
		for (const { where, text } of markupStrings(guide)) {
			for (const t of parseMarkup(text)) {
				if (t.kind === 'route' && !routeExists(t.routeId)) missing.push(`${where}: [[route:${t.routeId}]]`);
			}
		}
		for (const r of guide.routes ?? []) {
			if (!routeExists(r)) missing.push(`${guide.id}: routes "${r}"`);
		}
	}
	assert.deepEqual(missing, [], 'route ids must name a directory under apps/web/src/routes holding +page.svelte');
});

test('every HelpLink names a literal route that at least one guide covers', () => {
	const problems: string[] = [];
	for (const file of svelteFiles(SRC)) {
		const source = readFileSync(file, 'utf8');
		for (const attributes of tagAttributes(source, 'HelpLink')) {
			const route = literalAttribute(attributes, 'route');
			const where = relative(SRC, file);
			if (typeof route !== 'string') {
				problems.push(`${where}: <HelpLink> needs a literal route="..."`);
			} else if (!guides.some(({ guide }) => guide.routes?.includes(route))) {
				problems.push(`${where}: no guide lists "${route}" in its routes`);
			}
		}
	}
	assert.deepEqual(problems, []);
});

test('every InfoTip guide= names a guide that exists', () => {
	const problems: string[] = [];
	for (const file of svelteFiles(SRC)) {
		const source = readFileSync(file, 'utf8');
		for (const attributes of tagAttributes(source, 'InfoTip')) {
			const id = literalAttribute(attributes, 'guide');
			const where = relative(SRC, file);
			if (id === undefined) problems.push(`${where}: <InfoTip guide> must be a literal guide id`);
			else if (id !== null && !byId.has(id)) problems.push(`${where}: <InfoTip guide="${id}"> names no guide`);
		}
	}
	assert.deepEqual(problems, []);
});

test('tagAttributes reads past a `>` inside an attribute expression', () => {
	const src = '<InfoTip onclose={() => x > 1} guide="a" />\n<HelpLink route="/races"/>';
	assert.deepEqual(tagAttributes(src, 'InfoTip'), [' onclose={() => x > 1} guide="a" /']);
	assert.equal(literalAttribute(tagAttributes(src, 'InfoTip')[0] ?? '', 'guide'), 'a');
	assert.equal(literalAttribute(' route={r}', 'route'), undefined);
	assert.equal(literalAttribute(' label="x"', 'guide'), null);
	assert.deepEqual(tagAttributes(src, 'HelpLink'), [' route="/races"/']);
});

test('every per-locale guides.<locale>.json matches the guide and translation files', () => {
	try {
		execFileSync(process.execPath, [join(REPO_ROOT, 'scripts', 'gen_help_guides.mjs'), '--check'], {
			stdio: 'pipe',
		});
	} catch (e) {
		const err = e as { stderr?: Buffer };
		assert.fail(`the per-locale guide JSON is stale — run \`pnpm gen:help-guides\` and commit every file it writes.\n${err.stderr ?? ''}`);
	}
});

/// Each translated string beside the English string it translates.
function translatedPairs(t: GuideTranslation, g: Guide): { where: string; english: string; text: string }[] {
	const out: { where: string; english: string; text: string }[] = [];
	g.sections.forEach((section, si) => {
		section.blocks.forEach((block, bi) => {
			const theirs = t.sections[si]?.blocks[bi];
			if (!theirs) return;
			const english = blockTexts(block);
			blockTexts(theirs).forEach((text, i) =>
				out.push({ where: `section ${si + 1} block ${bi + 1}${english.length > 1 ? ` item ${i + 1}` : ''}`, english: english[i] ?? '', text }),
			);
		});
	});
	return out;
}

const linkTargets = (tokens: HelpToken[]) =>
	tokens.flatMap((t) => (t.kind === 'guide' ? [`guide:${t.id}`] : t.kind === 'route' ? [`route:${t.routeId}`] : []));
const strongCount = (tokens: HelpToken[]) => tokens.filter((t) => t.kind === 'strong').length;

test('translated titles, summaries and headings fit, read as one sentence, and carry no markup', () => {
	const problems: string[] = [];
	for (const { locale, translation: t } of translations) {
		const where = `translations/${locale}/${t.id}`;
		if (!(t.title.trim().length > 0 && t.title.length <= 80)) problems.push(`${where}: title must be 1-80 chars`);
		if (!(t.summary.trim().length > 0 && t.summary.length <= 200)) {
			problems.push(`${where}: summary must be 1-200 chars (is ${t.summary.length})`);
		}
		if (/[.!?]\s+\p{Lu}|[。！？](?!$)/u.test(t.summary)) problems.push(`${where}: summary must be one sentence`);
		for (const value of [t.title, t.summary, ...t.sections.map((s) => s.heading)]) {
			if (plainText(value) !== value) problems.push(`${where}: "${value}" may not carry markup`);
		}
		const anchors = t.sections.map((s) => sectionId(s.heading));
		if (anchors.some((a) => a === '')) problems.push(`${where}: a heading has no usable anchor`);
		if (new Set(anchors).size !== anchors.length) problems.push(`${where}: two section headings share an anchor`);
	}
	assert.deepEqual(problems, []);
});

test('translated text keeps the English markup: every link, in order, and every bold label', () => {
	const problems: string[] = [];
	for (const { locale, translation: t } of translations) {
		const g = byId.get(t.id);
		if (!g) continue;
		for (const { where, english, text } of translatedPairs(t, g)) {
			const at = `translations/${locale}/${t.id} › ${where}`;
			if (text.trim().length === 0) problems.push(`${at}: empty text`);
			for (const p of markupProblems(text)) problems.push(`${at}: ${p}`);
			const ours = parseMarkup(english);
			const theirs = parseMarkup(text);
			if (linkTargets(theirs).join(' ') !== linkTargets(ours).join(' ')) {
				problems.push(`${at}: links [${linkTargets(theirs).join(', ')}], the English has [${linkTargets(ours).join(', ')}]`);
			}
			if (strongCount(theirs) !== strongCount(ours)) {
				problems.push(`${at}: ${strongCount(theirs)} **labels**, the English has ${strongCount(ours)}`);
			}
		}
		if (PICTOGRAPH.test(JSON.stringify(t))) problems.push(`translations/${locale}/${t.id}: emoji in guide text`);
	}
	assert.deepEqual(problems, []);
});

test('no help-guide translation is stale or out of line with its guide', () => {
	try {
		execFileSync(process.execPath, [join(REPO_ROOT, 'scripts', 'check_help_translations.mjs')], { stdio: 'pipe' });
	} catch (e) {
		const err = e as { stderr?: Buffer };
		assert.fail(`scripts/check_help_translations.mjs failed:\n${err.stderr ?? ''}`);
	}
});
