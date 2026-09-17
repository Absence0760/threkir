// No derived metric reaches a runner without its definition (#902 §1 + §2,
// #905 workstream 6: "aspirational rules drift; enforced ones do not").
//
// The dashboard carried plain-English definitions for VO₂ max, CTL, ATL and
// TSB in all seven locales and still failed a new runner, because the copy
// sat in `title=` attributes: invisible on touch, unreachable by keyboard.
// Everywhere else the jargon had no definition at all. `<MetricLabel>` is the
// one way a registered name reaches the screen, and this file is what keeps
// it the one way. It reads `METRICS` from the registry itself, so there is no
// second list here to fall out of step with it.
//
// Five rules, each with a fixture proving it can fail:
//
//  1. A registered name or definition key is never spelled in a surface. The
//     component resolves both through the registry, so any literal use of the
//     key is a render that bypassed it — `title={m('dash.ctlTooltip')}` is
//     exactly how the four definitions went unseen.
//  2. A registered term is never typed straight into markup (`VDOT {n}`).
//  3. English copy that carries a term is the registered name, the
//     definition, a `{term}` sentence, or an exemption whose own string spells
//     the term out — and an exemption that stopped carrying the term fails.
//  4. A disclosure cannot sit where it breaks the control around it: inside a
//     `<button>` (the parser splits the outer one), a `<label>` (the button
//     becomes the label's control, stealing it from the input) or an
//     `aria-hidden` subtree (focusable but unannounced).
//  5. A `plain` label, used where no disclosure can go, is only allowed in a
//     file that also renders the interactive one, and every registered metric
//     is rendered somewhere.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { en } from '../i18n/locales/en';
import { stripComments } from '../core/strip_comments';
import { METRICS, TERM_PLACEHOLDER, nameKeys, type MetricEntry } from './metric_registry';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, '..', '..');
const SURFACE_ROOTS = [join(SRC, 'routes'), join(SRC, 'lib', 'components')];

const ENTRIES = Object.entries(METRICS) as [string, MetricEntry][];
const EN = en as Record<string, string>;

function surfaceFiles(): string[] {
	const out: string[] = [];
	const walk = (dir: string) => {
		for (const e of readdirSync(dir, { withFileTypes: true })) {
			const full = join(dir, e.name);
			if (e.isDirectory()) walk(full);
			else if (/\.(svelte|ts)$/.test(e.name) && !e.name.endsWith('.test.ts')) out.push(full);
		}
	};
	for (const root of SURFACE_ROOTS) walk(root);
	return out;
}

function lineAt(source: string, index: number): number {
	return source.slice(0, index).split('\n').length;
}

/** Characters replaced by spaces, newlines kept, so offsets stay the file's own. */
function blank(text: string): string {
	return text.replace(/[^\n]/g, ' ');
}

/// Script, style and HTML comments blanked out of a `.svelte` file, leaving
/// markup at its original offsets.
export function markupOf(source: string): string {
	return source
		.replace(/<script\b[\s\S]*?<\/script(?=[\s/>])[^>]*>/gi, blank)
		.replace(/<style\b[\s\S]*?<\/style(?=[\s/>])[^>]*>/gi, blank)
		.replace(/<!--[\s\S]*?-->/g, blank);
}

/// The source a surface's string literals are read from: a `.ts` file whole,
/// a `.svelte` file without its styles and HTML comments, JS comments blanked
/// either way.
function codeOf(file: string, source: string): string {
	if (file.endsWith('.ts')) return stripComments(source);
	return stripComments(
		source.replace(/<style\b[\s\S]*?<\/style(?=[\s/>])[^>]*>/gi, blank).replace(/<!--[\s\S]*?-->/g, blank),
	);
}

/** Index just past the `{…}` expression opening at `i`, strings and template holes respected. */
function skipExpression(src: string, i: number): number {
	let depth = 0;
	for (let k = i; k < src.length; k++) {
		const c = src[k];
		if (c === '"' || c === "'") {
			k = skipQuoted(src, k);
		} else if (c === '`') {
			k = skipTemplate(src, k);
		} else if (c === '{') {
			depth++;
		} else if (c === '}') {
			depth--;
			if (depth === 0) return k + 1;
		}
	}
	return src.length;
}

function skipQuoted(src: string, i: number): number {
	for (let k = i + 1; k < src.length; k++) {
		if (src[k] === '\\') k++;
		else if (src[k] === src[i]) return k;
	}
	return src.length;
}

function skipTemplate(src: string, i: number): number {
	for (let k = i + 1; k < src.length; k++) {
		if (src[k] === '\\') k++;
		else if (src[k] === '$' && src[k + 1] === '{') k = skipExpression(src, k + 1) - 1;
		else if (src[k] === '`') return k;
	}
	return src.length;
}

interface Attr {
	name: string;
	/** The literal value of a quoted attribute; null for `{…}` or a bare flag. */
	value: string | null;
	valueIndex: number;
	dynamic: boolean;
}

interface Tag {
	name: string;
	index: number;
	closing: boolean;
	selfClosing: boolean;
	attrs: Attr[];
}

interface Markup {
	tags: Tag[];
	/** Static text: text nodes outside `{…}` and quoted attribute values. */
	text: { index: number; value: string }[];
}

const TAG_NAME = /[A-Za-z][\w:.-]*/y;
const ATTR_NAME = /[^\s=>/]+/y;
const UNQUOTED = /[^\s>]+/y;

function stickyMatch(re: RegExp, src: string, at: number): string {
	re.lastIndex = at;
	return re.exec(src)?.[0] ?? '';
}

const VOID = new Set([
	'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr',
]);

/// A tolerant single pass over Svelte markup: tags with their attributes, and
/// the static text a reader would see. `{…}` is skipped as a unit wherever it
/// appears, so `{a < b}` never opens a tag and `onclick={() => x}` never
/// closes one.
export function parseMarkup(source: string): Markup {
	const src = markupOf(source);
	const tags: Tag[] = [];
	const text: Markup['text'] = [];
	let i = 0;
	let runStart = 0;
	let run = '';
	const flush = () => {
		if (run.trim()) text.push({ index: runStart, value: run });
		run = '';
	};
	while (i < src.length) {
		const c = src[i];
		if (c === '{') {
			flush();
			i = skipExpression(src, i);
			runStart = i;
			continue;
		}
		if (c === '<' && /[A-Za-z/]/.test(src[i + 1] ?? '')) {
			flush();
			const start = i;
			const closing = src[i + 1] === '/';
			i += closing ? 2 : 1;
			const name = stickyMatch(TAG_NAME, src, i);
			i += name.length;
			const attrs: Attr[] = [];
			let selfClosing = false;
			while (i < src.length) {
				const ch = src[i];
				if (/\s/.test(ch)) {
					i++;
				} else if (ch === '>') {
					i++;
					break;
				} else if (ch === '/' && src[i + 1] === '>') {
					selfClosing = true;
					i += 2;
					break;
				} else if (ch === '{') {
					const end = skipExpression(src, i);
					attrs.push({ name: '', value: null, valueIndex: i, dynamic: true });
					i = end;
				} else {
					const attrName = stickyMatch(ATTR_NAME, src, i) || src[i];
					i += attrName.length;
					if (src[i] !== '=') {
						attrs.push({ name: attrName, value: null, valueIndex: i, dynamic: false });
						continue;
					}
					i++;
					const q = src[i];
					if (q === '"' || q === "'") {
						const end = skipQuoted(src, i);
						const value = src.slice(i + 1, end);
						attrs.push({ name: attrName, value, valueIndex: i + 1, dynamic: false });
						if (!value.includes('{')) text.push({ index: i + 1, value });
						i = end + 1;
					} else if (q === '{') {
						const end = skipExpression(src, i);
						attrs.push({ name: attrName, value: null, valueIndex: i, dynamic: true });
						i = end;
					} else {
						const value = stickyMatch(UNQUOTED, src, i);
						attrs.push({ name: attrName, value, valueIndex: i, dynamic: false });
						i += value.length;
					}
				}
			}
			if (name) tags.push({ name, index: start, closing, selfClosing, attrs });
			runStart = i;
			continue;
		}
		if (!run) runStart = i;
		run += c;
		i++;
	}
	flush();
	return { tags, text };
}

const attr = (tag: Tag, name: string) => tag.attrs.find((a) => a.name === name);

/// Contexts a disclosure button may not sit in, named by the rule they break.
function forbiddenAncestor(tag: Tag): string | null {
	const name = tag.name.toLowerCase();
	if (name === 'button' || name === 'label' || name === 'summary' || name === 'select') return `<${name}>`;
	if (attr(tag, 'aria-hidden')?.value === 'true') return 'aria-hidden="true"';
	return null;
}

export interface LabelUse {
	metric: string | null;
	plain: boolean;
	sentence: string | null;
	/** The line the `sentence` value sits on, which a multi-line tag moves off `line`. */
	sentenceLine: number | null;
	line: number;
	/** The ancestor that makes an interactive label invalid, if any. */
	blockedBy: string | null;
}

export function metricLabelUses(source: string): LabelUse[] {
	const { tags } = parseMarkup(source);
	const stack: Tag[] = [];
	const uses: LabelUse[] = [];
	for (const tag of tags) {
		if (tag.closing) {
			const at = stack.map((t) => t.name).lastIndexOf(tag.name);
			if (at >= 0) stack.length = at;
			continue;
		}
		if (tag.name === 'MetricLabel') {
			const plain = tag.attrs.some((a) => a.name === 'plain' && a.value !== 'false');
			const sentence = attr(tag, 'sentence');
			const blocked = plain ? null : stack.map(forbiddenAncestor).find((r) => r !== null) ?? null;
			uses.push({
				metric: attr(tag, 'metric')?.value ?? null,
				plain,
				sentence: sentence?.value ?? null,
				sentenceLine: sentence ? lineAt(source, sentence.valueIndex) : null,
				line: lineAt(source, tag.index),
				blockedBy: blocked,
			});
		}
		if (!tag.selfClosing && !VOID.has(tag.name.toLowerCase())) stack.push(tag);
	}
	return uses;
}

/** Every quoted occurrence of `key` in code or markup, as line numbers. */
export function keyMentions(source: string, key: string): number[] {
	if (!source.includes(key)) return [];
	const quoted = new RegExp(`(['"\`])${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\1`, 'g');
	return [...source.matchAll(quoted)].map((mm) => lineAt(source, mm.index ?? 0));
}

/** Static markup text and string literals, each with the line it starts on. */
export function copyChunks(file: string, source: string): { line: number; value: string }[] {
	const starts = [0];
	for (let k = 0; k < source.length; k++) if (source[k] === '\n') starts.push(k + 1);
	const lineOf = (index: number) => {
		let lo = 0;
		let hi = starts.length - 1;
		while (lo < hi) {
			const mid = (lo + hi + 1) >> 1;
			if (starts[mid] <= index) lo = mid;
			else hi = mid - 1;
		}
		return lo + 1;
	};
	const chunks: { line: number; value: string }[] = [];
	if (file.endsWith('.svelte')) {
		for (const t of parseMarkup(source).text) chunks.push({ line: lineOf(t.index), value: t.value });
	}
	const literal = /'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|`(?:[^`\\]|\\.)*`/g;
	for (const lit of codeOf(file, source).matchAll(literal)) {
		chunks.push({ line: lineOf(lit.index ?? 0), value: lit[0] });
	}
	return chunks;
}

/** Lines where a term appears in static markup text or in a string literal. */
export function termHits(chunks: { line: number; value: string }[], term: RegExp): number[] {
	const flags = term.flags.includes('g') ? term.flags : term.flags + 'g';
	const re = new RegExp(term.source, flags);
	const lines = new Set<number>();
	for (const chunk of chunks) {
		for (const mm of chunk.value.matchAll(re)) {
			lines.add(chunk.line + (chunk.value.slice(0, mm.index ?? 0).split('\n').length - 1));
		}
	}
	return [...lines].sort((a, b) => a - b);
}

/** English keys whose copy carries a term without being allowed to. */
export function unexplainedCopy(entry: MetricEntry, catalogue: Record<string, string>): string[] {
	if (!entry.term) return [];
	const allowed = new Set<string>([
		...nameKeys(entry),
		entry.definition,
		...Object.keys(entry.expandedIn ?? {}),
	]);
	return Object.entries(catalogue)
		.filter(([key, value]) => entry.term!.test(value) && !allowed.has(key))
		.map(([key]) => key);
}

// ─────────── Fixtures: each rule can fail ───────────

test('rule 1 fixture: a definition key spelled in a surface is found, on its line', () => {
	const src = `<div\n\ttitle={m('dash.ctlTooltip')}\n>CTL</div>`;
	assert.deepEqual(keyMentions(src, 'dash.ctlTooltip'), [2]);
	assert.deepEqual(keyMentions(src, 'dash.ctl'), [], 'a key prefix is not a mention');
});

test('rule 2 fixture: a term typed into markup is found; a class name, an expression and a comment are not', () => {
	const vdot = /\bVDOT\b/;
	assert.deepEqual(termHits(copyChunks('x.svelte', '<span>\n\tVDOT {plan.vdot}\n</span>'), vdot), [2]);
	assert.deepEqual(termHits(copyChunks('x.svelte', '<span aria-label="VDOT">{n}</span>'), vdot), [1]);
	assert.deepEqual(termHits(copyChunks('x.svelte', '<span class="vdot">{"VDOT".length > 0 ? n : 0}</span>'), vdot), [1],
		'a string literal inside an expression is still copy');
	assert.deepEqual(termHits(copyChunks('x.svelte', '<!-- VDOT -->\n<span class="vdot">{n}</span>'), vdot), []);
	assert.deepEqual(termHits(copyChunks('x.svelte', '<script>\n// VDOT is fine in a comment\nconst k = 1;\n</script>'), vdot), []);
	assert.deepEqual(termHits(copyChunks('x.ts', "export const label = 'VDOT';"), vdot), [1]);
});

test('rule 3 fixture: bare English copy is caught, and an allowed key is not', () => {
	const entry: MetricEntry = {
		label: 'dash.ctlLabel',
		definition: 'dash.ctlTooltip',
		term: /\bCTL\b/,
		expandedIn: { 'trainingLoad.chartAriaLabel': 'spelled out' },
	};
	assert.deepEqual(
		unexplainedCopy(entry, {
			'dash.ctlLabel': 'CTL (fitness)',
			'dash.ctlTooltip': 'Fitness (CTL) — …',
			'trainingLoad.chartAriaLabel': 'fitness (CTL)',
			'fresh.key': 'Your CTL is up',
			'other.key': 'Nothing here',
		}),
		['fresh.key'],
	);
});

test('rule 4 fixture: a disclosure inside a button, a label or an aria-hidden row is blocked; a plain one is not', () => {
	const uses = metricLabelUses(
		[
			'<button onclick={() => a > b}><MetricLabel metric="rpe" /></button>',
			'<label><span><MetricLabel metric="rpe" /></span><input /></label>',
			'<li aria-hidden="true"><MetricLabel metric="rpe" /></li>',
			'<label><MetricLabel metric="rpe" plain /></label>',
			'<div>{#if x < 3}<MetricLabel metric="rpe" />{/if}</div>',
			'<a href="/x"><MetricLabel metric="rpe" /></a>',
		].join('\n'),
	);
	assert.deepEqual(
		uses.map((u) => u.blockedBy),
		['<button>', '<label>', 'aria-hidden="true"', null, null, null],
	);
	assert.deepEqual(uses.map((u) => u.line), [1, 2, 3, 4, 5, 6]);
});

test('rule 5 fixture: plain and sentence attributes are read', () => {
	const [a, b] = metricLabelUses(
		'<MetricLabel metric="riegel" sentence="racePredictor.footnote" />\n<MetricLabel plain metric="e1rm" />',
	);
	assert.equal(a.sentence, 'racePredictor.footnote');
	assert.equal(a.plain, false);
	assert.equal(b.plain, true);
	assert.equal(b.metric, 'e1rm');
});

// ─────────── The tree ───────────

const FILES = surfaceFiles().map((file) => {
	const source = readFileSync(file, 'utf-8');
	return {
		file,
		rel: relative(SRC, file),
		source,
		chunks: copyChunks(file, source),
		uses: file.endsWith('.svelte') ? metricLabelUses(source) : [],
	};
});

test('the scan reaches the surfaces and finds the component in use', () => {
	assert.ok(FILES.length > 200, `the walk reached only ${FILES.length} files`);
	const uses = FILES.flatMap((f) => f.uses);
	assert.ok(uses.length >= ENTRIES.length, `found only ${uses.length} <MetricLabel> uses`);
});

test('rule 1: no registered name or definition key is rendered around <MetricLabel>', () => {
	const offenders: string[] = [];
	for (const [id, entry] of ENTRIES) {
		for (const key of [...nameKeys(entry), entry.definition]) {
			for (const { rel, source } of FILES) {
				for (const line of keyMentions(source, key)) offenders.push(`${rel}:${line} ${key} (${id})`);
			}
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'Render a registered metric through <MetricLabel metric="…" />, which resolves its name and ' +
			'definition from lib/metrics/metric_registry.ts. A key spelled here bypasses the disclosure:\n  ' +
			offenders.join('\n  '),
	);
});

test('rule 2: no registered term is typed straight into a surface', () => {
	const offenders: string[] = [];
	for (const [id, entry] of ENTRIES) {
		if (!entry.term) continue;
		for (const { rel, chunks } of FILES) {
			for (const line of termHits(chunks, entry.term)) offenders.push(`${rel}:${line} ${entry.term} (${id})`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'A registered term is copy with a definition waiting for it. Put it in the catalogue and ' +
			'render it through <MetricLabel>:\n  ' +
			offenders.join('\n  '),
	);
});

test('rule 3: English copy never carries a term without its expansion, and no exemption is stale', () => {
	const offenders: string[] = [];
	for (const [id, entry] of ENTRIES) {
		for (const key of unexplainedCopy(entry, EN)) offenders.push(`${key} (${id}): ${EN[key]}`);
		for (const key of Object.keys(entry.expandedIn ?? {})) {
			if (!(key in EN)) offenders.push(`${key} (${id}): exempted but no longer in the catalogue`);
			else if (entry.term && !entry.term.test(EN[key])) {
				offenders.push(`${key} (${id}): exempted but no longer carries ${entry.term}`);
			}
		}
		for (const key of [...nameKeys(entry), entry.definition]) {
			if (!(key in EN)) offenders.push(`${key} (${id}): registered but not in the catalogue`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'Copy that names a registered metric must be its label, its definition, a {term} sentence ' +
			'rendered through <MetricLabel sentence=…>, or an `expandedIn` exemption that spells the ' +
			'term out in the same string:\n  ' +
			offenders.join('\n  '),
	);
});

test('rule 3: every {term} sentence belongs to exactly one metric and carries one placeholder', () => {
	const owners = new Map<string, string[]>();
	for (const [id, entry] of ENTRIES) {
		for (const key of entry.sentences ?? []) owners.set(key, [...(owners.get(key) ?? []), id]);
	}
	const offenders: string[] = [];
	for (const [key, value] of Object.entries(EN)) {
		const count = value.split(TERM_PLACEHOLDER).length - 1;
		const ids = owners.get(key) ?? [];
		if (count > 0 && ids.length === 0) offenders.push(`${key}: carries ${TERM_PLACEHOLDER} but no metric owns it`);
		if (ids.length > 1) offenders.push(`${key}: owned by ${ids.join(', ')}`);
		if (ids.length === 1 && count !== 1) offenders.push(`${key}: ${count} placeholders`);
	}
	for (const key of owners.keys()) if (!(key in EN)) offenders.push(`${key}: registered but not in the catalogue`);
	assert.deepEqual(offenders, [], offenders.join('\n'));
});

test('rule 3: a {term} sentence is only rendered by the label of the metric that owns it', () => {
	const ownerOf = new Map<string, string>();
	for (const [id, entry] of ENTRIES) for (const key of entry.sentences ?? []) ownerOf.set(key, id);
	const offenders: string[] = [];
	for (const { rel, source, uses } of FILES) {
		const viaLabel = new Map(uses.filter((u) => u.sentence).map((u) => [u.sentenceLine, u]));
		for (const [key, owner] of ownerOf) {
			for (const line of keyMentions(source, key)) {
				const use = viaLabel.get(line);
				if (!use || use.sentence !== key) offenders.push(`${rel}:${line} ${key} rendered without <MetricLabel sentence>`);
				else if (use.metric !== owner) offenders.push(`${rel}:${line} ${key} rendered by metric="${use.metric}", owned by ${owner}`);
			}
		}
	}
	assert.deepEqual(offenders, [], offenders.join('\n'));
});

test('rule 4: no disclosure sits inside a button, a label or an aria-hidden subtree', () => {
	const offenders: string[] = [];
	for (const { rel, uses } of FILES) {
		for (const use of uses) {
			if (use.blockedBy) offenders.push(`${rel}:${use.line} metric="${use.metric}" inside ${use.blockedBy}`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'Move the label out of that element, or use `plain` there and render the interactive label ' +
			'for the same metric elsewhere in the file:\n  ' +
			offenders.join('\n  '),
	);
});

test('rule 5: a plain label has an interactive sibling in its file, and every metric is rendered', () => {
	const offenders: string[] = [];
	const rendered = new Set<string>();
	for (const { rel, source, uses } of FILES) {
		const interactive = new Set(uses.filter((u) => !u.plain).map((u) => u.metric));
		for (const use of uses) {
			if (use.metric) rendered.add(use.metric);
			if (use.plain && !use.metric) offenders.push(`${rel}:${use.line} a plain label needs a literal metric`);
			if (use.plain && use.metric && !interactive.has(use.metric)) {
				offenders.push(`${rel}:${use.line} plain metric="${use.metric}" with no interactive label in the file`);
			}
		}
		for (const mm of source.matchAll(/\bmetric:\s*'(\w+)'/g)) rendered.add(mm[1]);
	}
	for (const [id] of ENTRIES) if (!rendered.has(id)) offenders.push(`${id}: registered but never rendered`);
	assert.deepEqual(offenders, [], offenders.join('\n'));
});
