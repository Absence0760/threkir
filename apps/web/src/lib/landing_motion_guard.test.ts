import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripComments } from '#lib/core/strip_comments.ts';
import { LIVE_CLOCK_TICKS } from './motion/motion.ts';

// Every animation the landing page can run settles within five seconds of
// starting. That is what keeps it outside WCAG 2.2.2 (Pause, Stop, Hide), and
// so what lets the page ship without a pause control (decisions § 1907). A
// single `infinite` brought back into any file the page renders puts the page
// back under 2.2.2 with no control to satisfy it, so this reads every file the
// page reaches and fails on a loop or on a timing that runs past the bound.
//
// The file set is derived, not listed: the walk follows `.svelte` imports from
// the route and every `#lib/motion/` module they pull in, so a component added
// to the page is read without anyone registering it. The timings read here are
// the literal ones; a delay set through a custom property from markup is
// measured in the browser by tests-e2e/landing/motion.spec.ts.

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = resolve(HERE, '..');
const ROUTE = join(SRC, 'routes', '+page.svelte');
const LIMIT_MS = 5000;

function resolveImport(from: string, spec: string): string | null {
	let path: string;
	if (spec.startsWith('#lib/')) path = join(HERE, spec.slice('#lib/'.length));
	else if (spec.startsWith('$lib/')) path = join(HERE, spec.slice('$lib/'.length));
	else if (spec.startsWith('.')) path = resolve(dirname(from), spec);
	else return null;
	for (const candidate of [path, `${path}.ts`]) {
		if (existsSync(candidate)) return candidate;
	}
	return null;
}

function landingFiles(): string[] {
	const seen = new Set<string>();
	const queue = [ROUTE];
	while (queue.length) {
		const file = queue.pop()!;
		if (seen.has(file)) continue;
		seen.add(file);
		const source = readFileSync(file, 'utf-8');
		for (const m of source.matchAll(/\bfrom\s+['"]([^'"]+)['"]/g)) {
			const target = resolveImport(file, m[1]);
			if (!target) continue;
			const followed =
				target.endsWith('.svelte') || relative(HERE, target).startsWith(`motion/`);
			if (followed && !target.endsWith('.test.ts')) queue.push(target);
		}
	}
	return [...seen];
}

type Timing = { where: string; text: string; totalMs: number };

function ms(token: string): number {
	return token.endsWith('ms') ? Number(token.slice(0, -2)) : Number(token.slice(0, -1)) * 1000;
}

/// Strips `var(--x, fallback)` down to its fallback (or nothing), so the
/// shorthand's remaining tokens are the literal ones.
function literal(value: string): string {
	let out = value;
	for (let prev = ''; prev !== out; ) {
		prev = out;
		out = out.replace(/var\(\s*--[\w-]+\s*(?:,\s*([^()]*))?\)/g, (_, fallback) => fallback ?? '');
	}
	return out.replace(/cubic-bezier\([^)]*\)|steps\([^)]*\)/g, '');
}

/// Splits a comma list at depth zero, so `var(--a, 0ms)` stays one layer.
function layersOf(value: string): string[] {
	const out: string[] = [];
	let depth = 0;
	let start = 0;
	for (let i = 0; i < value.length; i++) {
		const c = value[i];
		if (c === '(') depth++;
		else if (c === ')') depth--;
		else if (c === ',' && depth === 0) {
			out.push(value.slice(start, i));
			start = i + 1;
		}
	}
	out.push(value.slice(start));
	return out.map((l) => l.trim()).filter(Boolean);
}

/// Reads every CSS animation timing in a source: one entry per animation in
/// each declaration block. Throws on anything unbounded, so a caller asserts
/// on the message.
function cssTimings(source: string, where: string): Timing[] {
	const found: Timing[] = [];
	// A block is the text between two braces: nested at-rules leave the
	// declarations of each rule in a segment of their own.
	for (const block of source.split(/[{}]/)) {
		const decls = new Map<string, string>();
		for (const m of block.matchAll(/(?:^|;)\s*(animation(?:-[\w-]+)?)\s*:\s*([^;]+)/g)) {
			decls.set(m[1], m[2].trim());
		}
		if (!decls.size) continue;
		const text = [...decls].map(([k, v]) => `${k}: ${v}`).join('; ');
		for (const value of decls.values()) {
			if (/\binfinite\b/.test(value)) throw new Error(`${where}: loops forever: ${text}`);
		}
		// Scroll- and view-linked timelines are driven by the reader, not by
		// the clock, so they do not start on their own.
		if (decls.has('animation-timeline')) continue;
		if (decls.get('animation') === 'none') continue;

		const layers = layersOf(decls.get('animation') ?? '');
		const count = Math.max(layers.length, 1);
		for (let i = 0; i < count; i++) {
			const tokens = literal(layers[i] ?? '').trim().split(/\s+/).filter(Boolean);
			const times = tokens.filter((t) => /^-?[\d.]+m?s$/.test(t)).map(ms);
			const counts = tokens.filter((t) => /^[\d.]+$/.test(t)).map(Number);
			let duration = times[0] ?? 0;
			let delay = times[1] ?? 0;
			let iterations = counts[0] ?? 1;
			const pick = (name: string) => {
				const v = decls.get(name);
				if (!v) return undefined;
				const parts = layersOf(v).map(literal);
				return (parts[i] ?? parts[parts.length - 1]).trim();
			};
			const d = pick('animation-duration');
			if (d && /^-?[\d.]+m?s$/.test(d)) duration = ms(d);
			const dl = pick('animation-delay');
			if (dl && /^-?[\d.]+m?s$/.test(dl)) delay = ms(dl);
			const n = pick('animation-iteration-count');
			if (n && /^[\d.]+$/.test(n)) iterations = Number(n);
			if (!duration) continue;
			found.push({ where, text, totalMs: Math.max(0, delay) + duration * iterations });
		}
	}
	return found;
}

/// Script-driven motion with no end: a repeating timer, an infinite WAAPI
/// run, or an SVG SMIL animation that repeats indefinitely.
function unboundedScript(source: string): string[] {
	const hits: string[] = [];
	if (/\bsetInterval\s*\(/.test(source)) hits.push('setInterval');
	if (/\biterations\s*:\s*Infinity\b/.test(source)) hits.push('iterations: Infinity');
	if (/repeatCount\s*=\s*["']?indefinite/.test(source)) hits.push('repeatCount="indefinite"');
	if (/repeatDur\s*=\s*["']?indefinite/.test(source)) hits.push('repeatDur="indefinite"');
	return hits;
}

function styles(source: string): string {
	return [...source.matchAll(/<style(?=[\s/>])[^>]*>([\s\S]*?)<\/style(?=[\s/>])[^>]*>/g)]
		.map((m) => m[1])
		.join('\n');
}

test('the walk reaches the components the landing page renders', () => {
	const files = landingFiles().map((f) => relative(SRC, f));
	for (const expected of [
		'routes/+page.svelte',
		'lib/components/PublicHeader.svelte',
		'lib/components/marketing/ProductPreview.svelte',
		'lib/components/marketing/MapBackdrop.svelte',
		'lib/motion/actions.ts',
		'lib/motion/motion.ts',
	]) {
		assert.ok(files.includes(expected), `the walk missed ${expected}; it reached ${files.join(', ')}`);
	}
});

test('no landing animation loops, and each settles within five seconds', () => {
	const timings: Timing[] = [];
	const loops: string[] = [];
	for (const file of landingFiles()) {
		const source = stripComments(readFileSync(file, 'utf-8'));
		const where = relative(SRC, file);
		const css = file.endsWith('.svelte') ? styles(source) : '';
		try {
			timings.push(...cssTimings(css, where));
		} catch (error) {
			loops.push((error as Error).message);
		}
		for (const hit of unboundedScript(source)) loops.push(`${where}: ${hit}`);
	}
	assert.deepEqual(loops, [], 'motion that never ends is back on the landing page');
	// The page carries well over a dozen timed animations; a parser that
	// found none would pass everything.
	assert.ok(timings.length >= 12, `read only ${timings.length} animation timings`);
	const long = timings.filter((t) => t.totalMs > LIMIT_MS);
	assert.deepEqual(
		long.map((t) => `${t.where}: ${t.totalMs}ms: ${t.text}`),
		[],
		'an animation runs past five seconds of starting',
	);
});

test('the phone clock stops ticking inside five seconds', () => {
	assert.ok(Number.isInteger(LIVE_CLOCK_TICKS) && LIVE_CLOCK_TICKS > 0);
	assert.ok(LIVE_CLOCK_TICKS * 1000 <= LIMIT_MS, `${LIVE_CLOCK_TICKS} one-second ticks`);
});

test('the reader rejects what it is there to reject', () => {
	assert.throws(() => cssTimings('.a { animation: spin 1s linear infinite; }', 'x'), /loops forever/);
	assert.throws(
		() => cssTimings('.a { animation-name: spin; animation-iteration-count: infinite; }', 'x'),
		/loops forever/,
	);
	assert.deepEqual(
		cssTimings('.a { animation: drift 4s var(--ease, ease) 2s 2 backwards; }', 'x').map((t) => t.totalMs),
		[10000],
	);
	assert.deepEqual(
		cssTimings('.a { animation-name: lift; animation-duration: 1200ms; }', 'x').map((t) => t.totalMs),
		[1200],
	);
	assert.deepEqual(
		cssTimings('.a { animation: sink linear both; animation-timeline: scroll(root); }', 'x'),
		[],
	);
	assert.deepEqual(
		cssTimings('.a { animation: a 1s, b 2s 500ms 2; }', 'x').map((t) => t.totalMs),
		[1000, 4500],
	);
	assert.deepEqual(unboundedScript('const t = setInterval(f, 1000);'), ['setInterval']);
	assert.deepEqual(unboundedScript("el.animate(k, { iterations: Infinity })"), ['iterations: Infinity']);
	assert.deepEqual(unboundedScript('<animate repeatCount="indefinite" />'), ['repeatCount="indefinite"']);
});
