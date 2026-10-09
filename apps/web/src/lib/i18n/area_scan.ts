// Node-only source scanner behind the area-catalogue guard
// (`area_catalogues.test.ts`). Never imported by the app: it reads the tree
// with `node:fs`, so a browser bundle that reached it would fail to build.
//
// It answers one question per message key: which routes can render a file
// that names it? An area catalogue is loaded by the root layout's `load`
// for the routes `areas.ts` assigns it to, before any component of that route
// renders (decisions § 1802). A key that lives in an area catalogue but is
// named by a file some OTHER route can render would resolve to its raw key
// name there, because `m()` is synchronous and nothing would ever have loaded
// it. The guard computes that reachability from the import graph instead of
// trusting a directory convention, because a component under
// `lib/components/gym/` is free to be imported by the dashboard.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { AREAS, areasForRoute, type Area, type GroupTable } from './areas.ts';
import { ENUM_VOCABULARIES } from './enum_labels.ts';

export const SOURCE_EXTENSIONS = ['.svelte', '.ts', '.js', '.md'] as const;

function posix(p: string): string {
	return p.split(sep).join('/');
}

function isSource(name: string): boolean {
	if (/\.test\.(ts|js|mjs)$/.test(name) || name.endsWith('.d.ts')) return false;
	return SOURCE_EXTENSIONS.some((ext) => name.endsWith(ext));
}

/// Every non-test source file under `srcDir`, absolute paths.
export function listSourceFiles(srcDir: string): string[] {
	const out: string[] = [];
	const walk = (dir: string) => {
		for (const name of readdirSync(dir).sort()) {
			const abs = join(dir, name);
			if (statSync(abs).isDirectory()) {
				walk(abs);
				continue;
			}
			if (isSource(name)) out.push(abs);
		}
	};
	walk(srcDir);
	return out;
}

const IMPORT_SPECIFIER = [
	/\bimport\s+(?:type\s+)?[^'"`;]*?\bfrom\s*['"]([^'"]+)['"]/g,
	/\bimport\s*['"]([^'"]+)['"]/g,
	/\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
	/\bexport\s+(?:type\s+)?(?:\*|\{[^}]*\})\s*from\s*['"]([^'"]+)['"]/g,
];
const GLOB_SPECIFIER = /import\.meta\.glob(?:<[^>]*>)?\(\s*['"]([^'"]+)['"]/g;

function resolveFile(candidate: string, known: ReadonlySet<string>): string | null {
	if (known.has(candidate)) return candidate;
	for (const ext of ['.ts', '.js', '.svelte', '.svelte.ts', '.svelte.js']) {
		if (known.has(candidate + ext)) return candidate + ext;
	}
	for (const index of ['/index.ts', '/index.js']) {
		if (known.has(candidate + index)) return candidate + index;
	}
	// `import './x.js'` that names a `.ts` source (TS's ESM spelling).
	if (candidate.endsWith('.js') && known.has(candidate.slice(0, -3) + '.ts')) {
		return candidate.slice(0, -3) + '.ts';
	}
	return null;
}

function globToRegExp(absPattern: string): RegExp {
	const escaped = posix(absPattern)
		.split('*')
		.map((part) => part.replace(/[.+?^${}()|[\]\\]/g, '\\$&'))
		.join('[^/]*');
	return new RegExp(`^${escaped}$`);
}

/// file -> the source files it imports (static, dynamic, re-export, and
/// `import.meta.glob` matches). Type-only imports are kept: they cost nothing
/// at runtime, but a type import is never how a string literal travels, so
/// keeping them only ever makes the guard stricter, never blind.
export function buildImportGraph(srcDir: string, files: readonly string[]): Map<string, Set<string>> {
	const known = new Set(files);
	const lib = join(srcDir, 'lib');
	const graph = new Map<string, Set<string>>();
	for (const file of files) {
		const text = readFileSync(file, 'utf8');
		const edges = new Set<string>();
		for (const pattern of IMPORT_SPECIFIER) {
			for (const match of text.matchAll(pattern)) {
				const spec = match[1];
				let base: string | null = null;
				if (spec.startsWith('$lib/') || spec === '$lib') base = join(lib, spec.slice(5));
				else if (spec.startsWith('.')) base = resolve(dirname(file), spec);
				if (!base) continue;
				const hit = resolveFile(base, known);
				if (hit) edges.add(hit);
			}
		}
		for (const match of text.matchAll(GLOB_SPECIFIER)) {
			const re = globToRegExp(resolve(dirname(file), match[1]));
			for (const candidate of files) if (re.test(posix(candidate))) edges.add(candidate);
		}
		graph.set(file, edges);
	}
	return graph;
}

const ROUTE_ENTRY = /^\+(page|layout|error)(@[^.]*)?\.(svelte|ts|js)$/;

/// The SvelteKit route id a route entry file belongs to: `src/routes/gym/[id]/+page.svelte`
/// -> `/gym/[id]`. `null` for anything that is not a page, layout or error
/// file (a `+server.ts` renders no component and so never calls `m()` for a
/// reader).
export function routeIdOf(routesDir: string, file: string): string | null {
	const name = file.slice(file.lastIndexOf(sep) + 1);
	if (!ROUTE_ENTRY.test(name)) return null;
	const rel = posix(relative(routesDir, dirname(file)));
	return rel === '' ? '/' : `/${rel}`;
}

/// file -> the route ids whose entries reach it through the import graph.
export function reachingRoutes(
	routesDir: string,
	graph: ReadonlyMap<string, ReadonlySet<string>>,
): Map<string, Set<string>> {
	const out = new Map<string, Set<string>>();
	for (const entry of graph.keys()) {
		const routeId = routeIdOf(routesDir, entry);
		if (routeId === null) continue;
		const stack = [entry];
		const seen = new Set<string>();
		while (stack.length) {
			const file = stack.pop()!;
			if (seen.has(file)) continue;
			seen.add(file);
			let set = out.get(file);
			if (!set) out.set(file, (set = new Set()));
			set.add(routeId);
			for (const next of graph.get(file) ?? []) stack.push(next);
		}
	}
	return out;
}

const STRING_LITERAL = /'((?:\\.|[^'\\\n])*)'|"((?:\\.|[^"\\\n])*)"|`((?:\\.|[^`\\])*)`/g;

/// Every key a source text names. A key is named by a literal equal to it, by
/// a template literal whose static head it starts with (`m(\`nutrition.slot_${s}\`)`),
/// or by a plain literal ending in `.` or `_` that it starts with (a prefix
/// glued on with `+`). Over-reporting is the safe direction: a key named in a
/// comment-looking string only ever pins it to a wider audience.
export function keysNamedIn(text: string, keys: readonly string[], keySet: ReadonlySet<string>): Set<string> {
	const out = new Set<string>();
	for (const match of text.matchAll(STRING_LITERAL)) {
		const single = match[1] ?? match[2];
		if (single !== undefined) {
			if (keySet.has(single)) out.add(single);
			else if (/[._]$/.test(single) && single.length > 1) {
				for (const k of keys) if (k.startsWith(single)) out.add(k);
			}
			continue;
		}
		const template = match[3];
		const cut = template.indexOf('${');
		if (cut === -1) {
			if (keySet.has(template)) out.add(template);
			continue;
		}
		const head = template.slice(0, cut);
		if (head.length === 0 || !head.includes('.')) continue;
		for (const k of keys) if (k.startsWith(head)) out.add(k);
	}
	return out;
}

export type Usage = { file: string; routes: ReadonlySet<string> };

/// key -> every file naming it, with the routes that can render that file.
export function keyUsage(
	srcDir: string,
	keys: readonly string[],
): { usage: Map<string, Usage[]>; graph: Map<string, Set<string>>; reach: Map<string, Set<string>> } {
	const files = listSourceFiles(srcDir);
	const graph = buildImportGraph(srcDir, files);
	const reach = reachingRoutes(join(srcDir, 'routes'), graph);
	const keySet = new Set(keys);
	const usage = new Map<string, Usage[]>();
	const catalogues = join(srcDir, 'lib', 'i18n', 'locales') + sep;
	for (const file of files) {
		if (file.startsWith(catalogues)) continue;
		const named = keysNamedIn(readFileSync(file, 'utf8'), keys, keySet);
		const routes = reach.get(file) ?? new Set<string>();
		for (const k of named) {
			let list = usage.get(k);
			if (!list) usage.set(k, (list = []));
			list.push({ file, routes });
		}
	}
	return { usage, graph, reach };
}

export const CORE = 'core' as const;

/// A derived group's name: its units joined by `~` (several units), or a
/// lone `_segment` unit. Neither shape can be an area name, which is a plain
/// identifier, so the three kinds of part never collide.
export type GroupName = `${string}~${string}` | `_${string}`;
export type Part = Area | typeof CORE | GroupName;

/// Namespaces whose keys are built with NO static head (`${vocab}.${value}`
/// in `enum_labels.ts`), so no literal anywhere names them and the scan above
/// cannot see who renders them. They are pinned to core rather than guessed
/// at. Derived from the registry the builder itself reads, so a new
/// vocabulary is pinned the moment it is registered.
export function pinnedNamespaces(): string[] {
	return Object.keys(ENUM_VOCABULARIES).map((ns) => `${ns}.`);
}

/// key -> the catalogue part it ships in. Core unless EVERY route that can
/// render a file naming the key needs one and the same area: a key nothing
/// names, a key named by a file no route reaches, and a key shared by two
/// areas all stay in core, because each of those is a reader who would
/// otherwise render the raw key name.
export function assignParts(
	keys: readonly string[],
	usage: ReadonlyMap<string, readonly Usage[]>,
	pinned: readonly string[] = pinnedNamespaces(),
): Map<string, Part> {
	const out = new Map<string, Part>();
	for (const key of keys) out.set(key, partFor(key, usage.get(key), pinned));
	return out;
}

function partFor(key: string, uses: readonly Usage[] | undefined, pinned: readonly string[]): Part {
	if (pinned.some((ns) => key.startsWith(ns))) return CORE;
	if (!uses || uses.length === 0) return CORE;
	let candidates: Area[] | null = null;
	for (const use of uses) {
		if (use.routes.size === 0) return CORE;
		for (const routeId of use.routes) {
			const here = areasForRoute(routeId);
			candidates = candidates ? candidates.filter((a) => here.includes(a)) : here;
			if (candidates.length === 0) return CORE;
		}
	}
	if (!candidates || candidates.length === 0) return CORE;
	// Nested areas (`/settings` and `/settings/account`) can both cover every
	// reader of a key; the narrower one ships it to fewer of them.
	return narrowest(candidates);
}

function narrowest(areas: readonly Area[]): Area {
	return areas.reduce((best, a) => (areaDepth(a) > areaDepth(best) ? a : best));
}

function areaDepth(area: Area): number {
	return Math.max(...(AREAS[area] as readonly string[]).map((p) => p.split('/').length));
}

/// The smallest group worth its own part, in bytes of English source
/// (`JSON.stringify` of its keys and strings). Measured, decisions § 1812:
/// halving it from 2048 to 1024 took the mean route's catalogue payload from
/// 21 to 16 KB gzip and the core from 16 to 9, for at most one more part on
/// any route; 512 bought another 1.4 KB for six more parts. A part costs a
/// request (in parallel with the others, so per-request overhead rather than
/// a serial round trip), paid only on the routes that load it; the bytes it
/// takes out of core are saved by every reader on every route.
export const MIN_GROUP_SOURCE_BYTES = 1024;

/// The unit a route belongs to for grouping: its narrowest area, or `_x` for
/// a route under the top-level segment `/x` that no area covers. `null` for
/// the root, whose layout renders on every route — a key it names is global.
export function unitOf(routeId: string): string | null {
	const areas = areasForRoute(routeId);
	if (areas.length > 0) return narrowest(areas);
	const segment = routeId.split('/')[1];
	return segment ? `_${segment}` : null;
}

/// The route prefixes a unit covers: the area's own, or its segment.
export function unitPrefixes(unit: string): readonly string[] {
	if (unit.startsWith('_')) return [`/${unit.slice(1)}`];
	const prefixes = (AREAS as Record<string, readonly string[]>)[unit];
	if (!prefixes) throw new Error(`no area or segment unit named ${unit}`);
	return prefixes;
}

/// Keys that no single area covers but that never render outside a known set
/// of units (two areas, an area and an unregistered segment, or one such
/// segment alone) are grouped by that exact set. A set whose keys reach
/// `minBytes` of English source becomes a part of its own, loaded by every
/// route under any of its units (`partsForRoute`); smaller sets stay in core.
/// Nobody lists a group or its keys: both follow from who renders what, so a
/// key reused on a new surface moves to the right group, or to core, on the
/// next build.
export function deriveGroups(
	parts: ReadonlyMap<string, Part>,
	usage: ReadonlyMap<string, readonly Usage[]>,
	sourceBytes: (keys: readonly string[]) => number,
	pinned: readonly string[] = pinnedNamespaces(),
	minBytes: number = MIN_GROUP_SOURCE_BYTES,
): CatalogueSplit {
	const bySet = new Map<string, string[]>();
	for (const [key, part] of parts) {
		if (part !== CORE || pinned.some((ns) => key.startsWith(ns))) continue;
		const units = unitsFor(usage.get(key));
		if (!units) continue;
		const name = units.join('~');
		let list = bySet.get(name);
		if (!list) bySet.set(name, (list = []));
		list.push(key);
	}
	const out = new Map(parts);
	const groups: Record<string, readonly string[]> = {};
	for (const [name, keys] of [...bySet].sort(([a], [b]) => (a < b ? -1 : 1))) {
		if (sourceBytes(keys) < minBytes) continue;
		groups[name] = [...new Set(name.split('~').flatMap(unitPrefixes))].sort();
		for (const key of keys) out.set(key, name as GroupName);
	}
	return { parts: out, groups };
}

/// The sorted units every reader of a key lies in, or null when one of them
/// is global (the root) or unreachable, which keeps the key in core.
function unitsFor(uses: readonly Usage[] | undefined): string[] | null {
	if (!uses || uses.length === 0) return null;
	const units = new Set<string>();
	for (const use of uses) {
		if (use.routes.size === 0) return null;
		for (const routeId of use.routes) {
			const unit = unitOf(routeId);
			if (unit === null) return null;
			units.add(unit);
		}
	}
	return [...units].sort();
}

/// How many bytes of English source a set of keys is: the unit
/// `MIN_GROUP_SOURCE_BYTES` is measured in.
export function englishSourceBytes(english: Readonly<Record<string, string>>) {
	return (keys: readonly string[]): number => {
		const picked: Record<string, string> = {};
		for (const key of keys) if (key in english) picked[key] = english[key];
		return Buffer.byteLength(JSON.stringify(picked));
	};
}

export type CatalogueSplit = { parts: Map<string, Part>; groups: GroupTable };

/// The whole split for a source tree, from the tree's own usage: key -> part
/// (core, an area, or a derived group) and the groups that exist.
export function splitCatalogue(srcDir: string, english: Readonly<Record<string, string>>): CatalogueSplit {
	const keys = Object.keys(english);
	const { usage } = keyUsage(srcDir, keys);
	return deriveGroups(assignParts(keys, usage), usage, englishSourceBytes(english));
}
