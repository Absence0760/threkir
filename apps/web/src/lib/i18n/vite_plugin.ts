// Build-time split of every locale catalogue into a core part and one part per
// area (`areas.ts`, decisions § 1802). Registered in `vite.config.ts`; never
// imported by the app (it reads the tree with `node:fs`).
//
// The catalogues stay one source file per locale (`locales/<tag>.ts`), so
// adding a key, every guard that reads those files, and every lane editing
// them are unchanged. What changes is what the browser downloads: the plugin
// serves
//
//   virtual:i18n-catalogues               the loader table the store imports
//   virtual:i18n-catalogue/<tag>/<part>   one part of one locale, as a plain
//                                         object literal holding only its keys
//
// and which part a key lands in is `splitCatalogue` over the current tree —
// derived from who renders it, never declared — so the client build, the SSR
// build and the dev server all agree with the guard in
// `area_catalogues.test.ts` by construction.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { transformSync } from 'esbuild';
import type { Plugin, ViteDevServer } from 'vite';
import { AREA_NAMES, type Area } from './areas.ts';
import { CORE, SOURCE_EXTENSIONS, splitCatalogue, type Part } from './area_scan.ts';
import { DEFAULT_LOCALE, SUPPORTED_LOCALES, type Locale } from './locale.ts';

export const LOADERS_ID = 'virtual:i18n-catalogues';
export const PART_ID_PREFIX = 'virtual:i18n-catalogue/';

export function partId(locale: Locale, part: Part): string {
	return `${PART_ID_PREFIX}${locale}/${part}`;
}

/// Evaluate one `locales/<tag>.ts` and return its catalogue object. The file
/// is a single exported object literal (`en` for English, `messages` for the
/// rest) behind a type-only import, so stripping the types is all it needs.
export function readCatalogue(file: string): Record<string, string> {
	const { code } = transformSync(readFileSync(file, 'utf8'), {
		loader: 'ts',
		format: 'cjs',
		sourcefile: file,
	});
	const module = { exports: {} as Record<string, unknown> };
	new Function('module', 'exports', 'require', code)(module, module.exports, () => ({}));
	const dict = module.exports.messages ?? module.exports.en;
	if (!dict || typeof dict !== 'object') {
		throw new Error(`${file} exports neither 'messages' nor 'en'`);
	}
	return dict as Record<string, string>;
}

type Split = {
	parts: Map<string, Part>;
	catalogues: Map<Locale, Record<string, string>>;
};

export function computeSplit(srcDir: string): Split {
	const localesDir = join(srcDir, 'lib', 'i18n', 'locales');
	const catalogues = new Map<Locale, Record<string, string>>();
	for (const locale of SUPPORTED_LOCALES) {
		catalogues.set(locale, readCatalogue(join(localesDir, `${locale}.ts`)));
	}
	const keys = Object.keys(catalogues.get(DEFAULT_LOCALE)!);
	return { parts: splitCatalogue(srcDir, keys), catalogues };
}

/// The keys of one part, in source order, mapped to `locale`'s strings.
export function partCatalogue(split: Split, locale: Locale, part: Part): Record<string, string> {
	const dict = split.catalogues.get(locale)!;
	const out: Record<string, string> = {};
	for (const [key, p] of split.parts) {
		if (p === part && key in dict) out[key] = dict[key];
	}
	return out;
}

export function loadersModule(): string {
	const parts: string[] = [];
	parts.push(`import fallbackCore from ${JSON.stringify(partId(DEFAULT_LOCALE, CORE))};`);
	parts.push('export const FALLBACK_CORE = fallbackCore;');
	const pick = (id: string) => `() => import(${JSON.stringify(id)}).then((m) => m.default)`;
	parts.push('export const CORE_LOADERS = {');
	for (const locale of SUPPORTED_LOCALES) {
		const body = locale === DEFAULT_LOCALE ? '() => Promise.resolve(fallbackCore)' : pick(partId(locale, CORE));
		parts.push(`\t${JSON.stringify(locale)}: ${body},`);
	}
	parts.push('};');
	parts.push('export const AREA_LOADERS = {');
	for (const locale of SUPPORTED_LOCALES) {
		parts.push(`\t${JSON.stringify(locale)}: {`);
		for (const area of AREA_NAMES) parts.push(`\t\t${JSON.stringify(area)}: ${pick(partId(locale, area))},`);
		parts.push('\t},');
	}
	parts.push('};');
	return parts.join('\n');
}

function parsePartId(id: string): { locale: Locale; part: Part } | null {
	if (!id.startsWith(PART_ID_PREFIX)) return null;
	const [locale, part] = id.slice(PART_ID_PREFIX.length).split('/');
	if (!(SUPPORTED_LOCALES as readonly string[]).includes(locale)) return null;
	if (part !== CORE && !(AREA_NAMES as readonly string[]).includes(part)) return null;
	return { locale: locale as Locale, part: part as Area | typeof CORE };
}

export function i18nAreaCatalogues(options: { srcDir: string }): Plugin {
	const { srcDir } = options;
	let split: Split | null = null;
	const current = () => (split ??= computeSplit(srcDir));

	return {
		name: 'i18n-area-catalogues',
		buildStart() {
			split = null;
			for (const locale of SUPPORTED_LOCALES) {
				this.addWatchFile(join(srcDir, 'lib', 'i18n', 'locales', `${locale}.ts`));
			}
		},
		resolveId(id) {
			if (id === LOADERS_ID || parsePartId(id)) return `\0${id}`;
			return null;
		},
		load(id) {
			if (!id.startsWith('\0')) return null;
			const bare = id.slice(1);
			if (bare === LOADERS_ID) return loadersModule();
			const parsed = parsePartId(bare);
			if (!parsed) return null;
			const dict = partCatalogue(current(), parsed.locale, parsed.part);
			return `export default ${JSON.stringify(dict, null, '\t')};\n`;
		},
		configureServer(server: ViteDevServer) {
			// A key's part depends on every file that names it, so any source
			// edit can move one. Recompute, and reload only when the split or a
			// catalogue's text actually changed.
			const reload = (file: string) => {
				if (!file.startsWith(srcDir) || !SOURCE_EXTENSIONS.some((e) => file.endsWith(e))) return;
				const before = split;
				split = null;
				// Nothing has been served from the old split, so there is
				// nothing to invalidate; the next load computes afresh.
				if (!before) return;
				if (sameSplit(before, current())) return;
				for (const env of Object.values(server.environments)) {
					for (const locale of SUPPORTED_LOCALES) {
						for (const part of [CORE, ...AREA_NAMES] as Part[]) {
							const mod = env.moduleGraph.getModuleById(`\0${partId(locale, part)}`);
							if (mod) env.moduleGraph.invalidateModule(mod);
						}
					}
				}
				server.ws.send({ type: 'full-reload' });
			};
			server.watcher.on('change', reload);
			server.watcher.on('add', reload);
			server.watcher.on('unlink', reload);
		},
	};
}

function sameSplit(a: Split, b: Split): boolean {
	if (a.parts.size !== b.parts.size) return false;
	for (const [k, p] of a.parts) if (b.parts.get(k) !== p) return false;
	for (const locale of SUPPORTED_LOCALES) {
		if (JSON.stringify(a.catalogues.get(locale)) !== JSON.stringify(b.catalogues.get(locale))) return false;
	}
	return true;
}
