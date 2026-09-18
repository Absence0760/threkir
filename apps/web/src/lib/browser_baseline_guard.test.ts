// A feature detect is an exception to the stated browser floor, and every one
// of them is declared here.
//
// The floor lives in ONE place — `browserslist` in `apps/web/package.json` —
// and `conventions.md § Web browser baseline` is its prose. Above it every
// Baseline API is used directly: no detect, no fallback. Below it the app is
// not supported. A runtime detect therefore says one of exactly three things,
// and `REASONS` is that closed set: the API is above the floor, or it is
// absent for a reason that is not a version (a permission, a secure context,
// an install state), or the probe is not about the platform at all but about
// the shape of a value. A detect for an API the floor already guarantees has
// no fourth reason available to it and fails here until it is deleted.
//
// Why this is a guard and not a paragraph: `clipText`'s grapheme cut had a
// hand-written `Intl.Segmenter` fallback whose whole justification was
// "Firefox gained the constructor only in 125", against a repo that had never
// said which Firefox it supports. The fallback was neither right nor wrong —
// it was unmeasurable (decisions § 1658). It is now the first entry below,
// with the release that retires it, and the floor reaching Firefox 125 fails
// this suite rather than leaving the fallback to outlive its reason.
//
// **Scope, and the blind spot it leaves.** The scan reads `apps/web/src` and
// asks about a PROPERTY: `typeof x.y === 'function'`, `'y' in X`,
// `(X as { y?: T }).y`, `CSS.supports(...)`, `@supports (...)`. A test of a
// BARE global — `typeof window === 'undefined'`, `typeof localStorage`,
// `typeof IntersectionObserver` — is deliberately outside it: that question is
// "is there a browser here at all", which every module that also runs on a
// share Lambda or under prerender has to ask, and there are dozens. The two
// questions are different, and only the second is about a browser's age.
// `apps/web/lambda` is outside for the same reason — it is Node 24.
//
// Both scanners parse. `.ts` goes through the TypeScript parser and `.svelte`
// through Svelte's own, whose script offsets then go through TypeScript's; a
// file either parses or throws naming itself, because a source-level guard
// that reads its input approximately is a green tick over text nobody looked
// at (conventions.md § A guard parses its input, or refuses it).

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';
import { parse } from 'svelte/compiler';
import { browserFloor } from '../../scripts/browser_baseline.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const WEB = resolve(HERE, '..', '..');
const SRC = join(WEB, 'src');
const CONVENTIONS = resolve(WEB, '..', '..', 'docs', 'architecture', 'conventions.md');

const REASONS = ['above-floor', 'optional-capability', 'value-shape'] as const;
type Reason = (typeof REASONS)[number];

type Exception = {
	/** Path under `apps/web`, as the scan reports it. */
	file: string;
	/** The probed member, as the scan names it. */
	probe: string;
	/** How many times the file probes it. */
	count: number;
	reason: Reason;
	/**
	 * For `above-floor` only: the first version of each browser that ships the
	 * API. The entry is obsolete — and this suite fails — once the floor meets
	 * every one of them. Omitted where no engine trio has shipped it yet and
	 * there is no version to name.
	 */
	until?: Record<string, number>;
	why: string;
};

const EXCEPTIONS: Exception[] = [
	{
		file: 'src/lib/util/clip_text.ts',
		probe: 'Intl.Segmenter',
		count: 1,
		reason: 'above-floor',
		until: { firefox: 125 },
		why: "the grapheme cut is the crawler's on every runtime the floor names except Firefox 121-124, which degrade to the code-unit cut. Every share `<head>` is built through this in the tab as well as on the Lambda, so a throw here is a blank page, not a clipped title (decisions § 1529, § 1658).",
	},
	{
		file: 'src/lib/share/svg_text_width.ts',
		probe: 'Intl.Segmenter',
		count: 1,
		reason: 'above-floor',
		until: { firefox: 125 },
		why: 'the og:image width estimate splits on code points instead of clusters on Firefox 121-124, which only ever over-estimates, so the one-sided bound the module claims survives the fallback.',
	},
	{
		file: 'src/lib/components/MetricLabel.svelte',
		probe: 'el.showPopover',
		count: 1,
		reason: 'above-floor',
		until: { chrome: 114, edge: 114, firefox: 125, safari: 17, ios_saf: 17 },
		why: 'the definition panel is promoted to the top layer where the Popover API exists and positioned by hand where it does not. The floor sits below all five of those, so the fallback is the path most of the supported range takes, not an edge.',
	},
	{
		file: 'src/routes/+page.svelte',
		probe: '@supports (animation-timeline: scroll())',
		count: 1,
		reason: 'above-floor',
		why: 'scroll-driven animations have no second engine, so there is no version to retire this at. The landing page is finished without it — the rule in `motion/actions.ts` is that an animation only moves an element away from where it already is.',
	},
	{
		file: 'src/routes/+page.svelte',
		probe: '@supports (animation-timeline: view())',
		count: 1,
		reason: 'above-floor',
		why: 'the view-timeline half of the same query, same reason.',
	},
	{
		file: 'src/lib/util/push.ts',
		probe: 'navigator.serviceWorker',
		count: 3,
		reason: 'optional-capability',
		why: 'a service worker is absent in a private window and on an iOS Safari tab that has not been installed to the home screen, at any version. This is not a question about the browser`s age.',
	},
	{
		file: 'src/lib/util/push.ts',
		probe: 'window.PushManager',
		count: 1,
		reason: 'optional-capability',
		why: 'same install-state gate — iOS exposes push only to an installed PWA.',
	},
	{
		file: 'src/lib/util/push.ts',
		probe: 'window.Notification',
		count: 1,
		reason: 'optional-capability',
		why: 'same, and the constructor is withheld from some embedded webviews outright.',
	},
	{
		file: 'src/lib/training/goals.ts',
		probe: 'crypto.randomUUID',
		count: 1,
		reason: 'optional-capability',
		why: 'exposed only in a secure context, so it is missing from a dev server reached over http at a LAN address on a browser well above the floor.',
	},
	{
		file: 'src/routes/runs/[id]/+page.svelte',
		probe: 'navigator.share',
		count: 1,
		reason: 'optional-capability',
		why: 'the Web Share API is a platform capability, not a version: desktop Firefox and Chrome on Linux are above the floor and have no share sheet to offer.',
	},
	{
		file: 'src/lib/core/edge_function_error.ts',
		probe: 'ctx.clone',
		count: 1,
		reason: 'value-shape',
		why: 'asks whether the `context` hung off an unknown error is a Response, which is a question about the value supabase-js threw, not about the runtime.',
	},
];

/* ── the floor ─────────────────────────────────────────────────────────── */

const FLOOR = browserFloor();
const FLOOR_BY_BROWSER = new Map(FLOOR.map((r) => [r.browser, Number(r.version)]));

test('the floor is one declaration, and conventions.md states the same one', () => {
	const prose = readFileSync(CONVENTIONS, 'utf-8');
	const heading = '## Web browser baseline';
	const start = prose.indexOf(heading);
	assert.notEqual(start, -1, `${heading} is missing from docs/architecture/conventions.md`);
	const next = prose.indexOf('\n## ', start + heading.length);
	const section = prose.slice(start, next === -1 ? prose.length : next);

	// The table's floor rows, read the way the section writes them: a leading
	// cell naming the browserslist key in backticks, then a cell with the
	// version. A row the section states and `package.json` does not (or the
	// other way round) is the drift this whole test exists for.
	const stated = new Map<string, number>();
	for (const m of section.matchAll(/^\|\s*`([a-z_]+)`\s*\|\s*([\d.]+)\s*\|/gm)) {
		stated.set(m[1], Number(m[2]));
	}
	assert.deepEqual(
		[...stated.entries()].sort(),
		[...FLOOR_BY_BROWSER.entries()].sort(),
		'conventions.md § Web browser baseline and apps/web/package.json declare different floors. ' +
			'package.json is the declaration; edit the prose table to match it.',
	);
});

test('every feature the floor is derived from is still used without a fallback', () => {
	// The two CSS features that set the floor's Firefox and Safari rows. If
	// either leaves the tree the floor is no longer derived from anything and
	// should be re-derived rather than inherited — which is the state this
	// whole policy replaced.
	const NEEDLES = [
		{ needle: ':has(', sets: 'firefox 121' },
		{ needle: 'container-type:', sets: 'safari 16.4 (via container queries at 16.0)' },
	];
	const all = svelteFiles().map((f) => readFileSync(f, 'utf-8'));
	for (const { needle, sets } of NEEDLES) {
		assert.ok(
			all.some((src) => src.replace(/\s+/g, '').includes(needle.replace(/\s+/g, ''))),
			`nothing in apps/web/src uses \`${needle}\` any more, and it is what justifies ${sets}. ` +
				'Re-derive the floor in package.json + conventions.md rather than leaving the row standing.',
		);
	}
});

/* ── the exceptions ────────────────────────────────────────────────────── */

test('every feature detect in apps/web/src is a declared exception', () => {
	const found = scan();
	const declared = new Map(EXCEPTIONS.map((e) => [`${e.file} ${e.probe}`, e]));

	const undeclared = [...found].filter(([key]) => !declared.has(key));
	assert.deepEqual(
		undeclared.map(([key, hits]) => `${key.replace(' ', ' — ')} (${hits.length}x)`),
		[],
		'a feature detect with no entry in EXCEPTIONS. Either the floor already guarantees the API — in which ' +
			'case delete the detect — or add an entry naming which of the three reasons it is, and why.',
	);

	const stale = [...declared.keys()].filter((key) => !found.has(key));
	assert.deepEqual(
		stale.map((key) => key.replace(' ', ' — ')),
		[],
		'an EXCEPTIONS entry for a detect the tree no longer has. Delete the entry.',
	);

	const miscounted = EXCEPTIONS.filter((e) => found.get(`${e.file} ${e.probe}`)?.length !== e.count).map(
		(e) => `${e.file} — ${e.probe}: declared ${e.count}, found ${found.get(`${e.file} ${e.probe}`)?.length}`,
	);
	assert.deepEqual(miscounted, [], 'an EXCEPTIONS count that no longer matches the file');
});

test('every exception names one of the three reasons, with a why', () => {
	for (const e of EXCEPTIONS) {
		assert.ok(
			(REASONS as readonly string[]).includes(e.reason),
			`${e.file} — ${e.probe}: ${e.reason} is not one of ${REASONS.join(', ')}`,
		);
		assert.ok(e.why.length > 40, `${e.file} — ${e.probe}: the why is too short to be one`);
		assert.ok(
			e.reason === 'above-floor' || e.until === undefined,
			`${e.file} — ${e.probe}: only an above-floor exception retires at a version`,
		);
	}
});

test('no above-floor exception outlives the floor that justifies it', () => {
	for (const e of EXCEPTIONS) {
		if (!e.until) continue;
		const unmet = Object.entries(e.until).filter(([browser, version]) => {
			const floor = FLOOR_BY_BROWSER.get(browser);
			return floor === undefined || floor < version;
		});
		assert.notEqual(
			unmet.length,
			0,
			`${e.file} — ${e.probe}: the floor now meets every version in \`until\`, so the API is guaranteed ` +
				'across the supported range and the fallback is dead code. Delete the fallback and this entry.',
		);
	}
});

/* ── the scan ──────────────────────────────────────────────────────────── */

type Hit = { file: string; probe: string };

function svelteFiles(): string[] {
	return sourceFiles().filter((f) => f.endsWith('.svelte'));
}

function sourceFiles(): string[] {
	const out: string[] = [];
	const walk = (dir: string) => {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const full = join(dir, entry.name);
			if (entry.isDirectory()) walk(full);
			else if (/\.(ts|svelte)$/.test(entry.name) && !entry.name.endsWith('.test.ts')) out.push(full);
		}
	};
	walk(SRC);
	return out.sort();
}

function scan(): Map<string, Hit[]> {
	const byKey = new Map<string, Hit[]>();
	for (const full of sourceFiles()) {
		const file = relative(WEB, full).split(sep).join('/');
		const src = readFileSync(full, 'utf-8');
		const hits = full.endsWith('.ts') ? scanTs(file, src, src) : scanSvelte(file, src);
		for (const hit of hits) {
			const key = `${hit.file} ${hit.probe}`;
			const list = byKey.get(key) ?? [];
			list.push(hit);
			byKey.set(key, list);
		}
	}
	return byKey;
}

function scanSvelte(file: string, src: string): Hit[] {
	let ast: ReturnType<typeof parse>;
	try {
		ast = parse(src, { modern: true });
	} catch (cause) {
		throw new Error(`${file} could not be parsed as Svelte`, { cause });
	}
	const hits: Hit[] = [];
	for (const block of [ast.instance, ast.module]) {
		if (!block) continue;
		hits.push(...scanTs(file, src.slice(block.content.start, block.content.end), src));
	}
	collectFeatureQueries(ast.css, file, hits);
	return hits;
}

/** Every `@supports` at-rule in a `<style>` block, from Svelte's own CSS AST. */
function collectFeatureQueries(node: unknown, file: string, out: Hit[]): void {
	if (node === null || typeof node !== 'object') return;
	const n = node as { type?: unknown; name?: unknown; prelude?: unknown };
	if (n.type === 'Atrule' && n.name === 'supports') {
		if (typeof n.prelude !== 'string') {
			throw new Error(`${file}: an @supports prelude Svelte did not give as text`);
		}
		out.push({ file, probe: `@supports ${n.prelude.replace(/\s+/g, ' ').trim()}` });
	}
	for (const value of Object.values(node as Record<string, unknown>)) {
		if (Array.isArray(value)) for (const child of value) collectFeatureQueries(child, file, out);
		else if (value && typeof value === 'object') collectFeatureQueries(value, file, out);
	}
}

function scanTs(file: string, code: string, whole: string): Hit[] {
	const sf = ts.createSourceFile(file, code, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
	// TypeScript's parser recovers rather than throwing, so a file it could not
	// read comes back as a tree full of error nodes. Refusing on the first one
	// is what keeps a misread file from reporting clean.
	const diagnostics = (sf as unknown as { parseDiagnostics?: { messageText: unknown }[] }).parseDiagnostics;
	if (diagnostics && diagnostics.length > 0) {
		throw new Error(`${file} could not be parsed as TypeScript: ${String(diagnostics[0].messageText)}`);
	}
	void whole;

	const bound = bindings(sf);
	const free = (name: string) => !bound.has(name);
	const hits: Hit[] = [];

	const visit = (node: ts.Node): void => {
		const probe = probeOf(node, sf, free);
		if (probe) hits.push({ file, probe });
		ts.forEachChild(node, visit);
	};
	ts.forEachChild(sf, visit);
	return hits;
}

function probeOf(node: ts.Node, sf: ts.SourceFile, free: (name: string) => boolean): string | null {
	// `typeof x.y === 'function' | 'undefined'` — a question about a member,
	// whatever the subject is. The subject being a parameter (`el.showPopover`)
	// is the common spelling, so the free-identifier rule does not apply here.
	if (ts.isTypeOfExpression(node) && isMemberAccess(node.expression)) {
		const parent = node.parent;
		if (parent && ts.isBinaryExpression(parent) && isStrictEquality(parent.operatorToken.kind)) {
			const other = parent.left === node ? parent.right : parent.left;
			if (ts.isStringLiteral(other) && (other.text === 'function' || other.text === 'undefined')) {
				return node.expression.getText(sf);
			}
		}
	}

	// `'y' in X` — free subject only. Bound subjects are the narrowing idiom
	// (`'notes' in patch`), which asks about a value's shape and not the host.
	if (
		ts.isBinaryExpression(node) &&
		node.operatorToken.kind === ts.SyntaxKind.InKeyword &&
		ts.isStringLiteral(node.left) &&
		ts.isIdentifier(node.right) &&
		free(node.right.text)
	) {
		return `${node.right.text}.${node.left.text}`;
	}

	// `(X as { y?: T }).y` — the only way to ask TypeScript about a member it
	// does not believe in. Free subject, and a read: the same cast over an
	// assignment is how a dev-only debug handle is hung off `window`.
	if (ts.isAsExpression(node) && optionalMembers(node.type).length > 0 && !isAssignmentTarget(node)) {
		const root = rootOf(node.expression);
		if (ts.isIdentifier(root) && free(root.text)) {
			return `${root.text}.${optionalMembers(node.type)
				.map((m) => m.name.getText(sf))
				.join('|')}`;
		}
	}

	// `CSS.supports(...)` — the scripted half of an `@supports` query.
	if (ts.isCallExpression(node)) {
		const callee = node.expression;
		if (
			ts.isPropertyAccessExpression(callee) &&
			callee.name.text === 'supports' &&
			ts.isIdentifier(callee.expression) &&
			free(callee.expression.text)
		) {
			return `${callee.expression.text}.supports`;
		}
	}

	return null;
}

function isMemberAccess(node: ts.Node): node is ts.PropertyAccessExpression | ts.ElementAccessExpression {
	return ts.isPropertyAccessExpression(node) || ts.isElementAccessExpression(node);
}

function isStrictEquality(kind: ts.SyntaxKind): boolean {
	return kind === ts.SyntaxKind.EqualsEqualsEqualsToken || kind === ts.SyntaxKind.ExclamationEqualsEqualsToken;
}

function optionalMembers(type: ts.TypeNode): ts.PropertySignature[] {
	if (!ts.isTypeLiteralNode(type)) return [];
	return type.members.filter((m): m is ts.PropertySignature => ts.isPropertySignature(m) && !!m.questionToken);
}

function rootOf(expression: ts.Expression): ts.Expression {
	let node = expression;
	for (;;) {
		if (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) || ts.isNonNullExpression(node)) {
			node = node.expression;
			continue;
		}
		return node;
	}
}

function isAssignmentTarget(node: ts.Node): boolean {
	let cursor: ts.Node = node;
	while (
		cursor.parent &&
		(ts.isParenthesizedExpression(cursor.parent) ||
			ts.isPropertyAccessExpression(cursor.parent) ||
			ts.isElementAccessExpression(cursor.parent))
	) {
		cursor = cursor.parent;
	}
	const parent = cursor.parent;
	return (
		!!parent &&
		ts.isBinaryExpression(parent) &&
		parent.left === cursor &&
		parent.operatorToken.kind === ts.SyntaxKind.EqualsToken
	);
}

/**
 * Every name the module binds anywhere in itself. Scope-flat on purpose: a
 * module that shadows `Intl` or `navigator` at any depth is one whose probes
 * this guard declines to reason about, which is the safe direction to be
 * imprecise in for a set this small.
 */
function bindings(sf: ts.SourceFile): Set<string> {
	const names = new Set<string>();
	const add = (name: ts.Node | undefined): void => {
		if (!name) return;
		if (ts.isIdentifier(name)) names.add(name.text);
		else if (ts.isObjectBindingPattern(name) || ts.isArrayBindingPattern(name)) {
			for (const element of name.elements) if (ts.isBindingElement(element)) add(element.name);
		}
	};
	const visit = (node: ts.Node): void => {
		if (ts.isVariableDeclaration(node) || ts.isParameter(node) || ts.isBindingElement(node)) add(node.name);
		else if (ts.isFunctionDeclaration(node) || ts.isClassDeclaration(node)) add(node.name);
		else if (ts.isImportClause(node) || ts.isImportSpecifier(node) || ts.isNamespaceImport(node)) add(node.name);
		ts.forEachChild(node, visit);
	};
	ts.forEachChild(sf, visit);
	return names;
}
