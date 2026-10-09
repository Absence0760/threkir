import { browser, dev } from '$app/environment';
import { CORE_LOADERS, FALLBACK_CORE, GROUPS, PART_LOADERS } from 'virtual:i18n-catalogues';
import { partsForRoute } from './areas';
import { CatalogueSet, holdsServerMarkup, type Catalogue } from './catalogue_set';
import { interpolate } from './interpolate';
import { setActiveFormatLocale } from '$lib/format/time';
import type { MessageKey } from './messages';
import {
	DEFAULT_LOCALE,
	dirForLocale,
	isSupportedLocale,
	negotiateLocale,
	type Locale,
} from './locale';

let locale = $state<Locale>(DEFAULT_LOCALE);
let dict = $state<Catalogue>(FALLBACK_CORE);

// A locale is a core catalogue plus one per area (areas.ts, decisions § 1802)
// and one per derived group of areas (§ 1812), all served by the build-time
// split in vite_plugin.ts. Only the default locale's core is bundled; every
// other part is its own lazy chunk, so a reader downloads the core and the
// parts of the routes they open, in their own language, and nothing else.
const catalogues = new CatalogueSet<Locale, string>({
	sources: {
		core: (l) => CORE_LOADERS[l](),
		area: (l, part) => {
			const load = PART_LOADERS[l][part];
			if (!load) return Promise.reject(new Error(`no catalogue part ${part}`));
			return load();
		},
	},
	fallbackLocale: DEFAULT_LOCALE,
	fallbackCore: FALLBACK_CORE,
	onChange: (next, merged) => {
		dict = merged;
		locale = next;
	},
	onError: (what, e) => console.warn(`i18n: catalogue ${what} failed to load`, e),
});

export function currentLocale(): Locale {
	return locale;
}

// True from the first load until the root layout mounts, when that first
// render hydrates markup the server wrote (in the default locale) rather than
// rendering into the SPA shell.
let hydratingServerMarkup = $state(false);

/// The locale a component may choose STRUCTURE by — which component, which
/// branch — as opposed to which words, which `currentLocale()` and `m()`
/// decide. Text the server wrote in English is rewritten as the page hydrates
/// in the reader's locale; a different subtree is not, it is a hydration
/// mismatch. So while a server-rendered page hydrates this answers the locale
/// the server rendered in, and the reader's own from the moment it mounts.
export function structureLocale(): Locale {
	return hydratingServerMarkup ? DEFAULT_LOCALE : locale;
}

const reportedMissing = new Set<string>();

// Reactive message lookup. Reading `dict` here makes every call site
// (template / $derived) re-render when the active locale changes. Falls
// back to the English core string, then the raw key, so a not-yet-translated
// key degrades gracefully rather than rendering blank.
//
// Synchronous by contract, which is why an area's catalogue is loaded by the
// root layout before its route renders (`loadRouteCatalogues`). A key that
// still misses here was named somewhere the build-time split could not see;
// in dev that is reported, because on screen it reads as a key name.
export function m(key: MessageKey, params?: Record<string, string | number>): string {
	const value: string | undefined = dict[key] ?? FALLBACK_CORE[key];
	if (value === undefined) {
		if (dev && !reportedMissing.has(key)) {
			reportedMissing.add(key);
			console.warn(`i18n: "${key}" is in no loaded catalogue — see areas.ts`);
		}
		return interpolate(key, params, locale);
	}
	return interpolate(value, params, locale);
}

let firstLoad = true;

/// Load the catalogues `routeId` renders with. Called by the root layout's
/// `load`, which SvelteKit resolves before any component of the route
/// renders — on the server for a prerendered page and in the browser for every
/// navigation. Never rejects (CatalogueSet keeps the current dict on failure).
///
/// The first load in the browser applies the reader's locale before anything
/// renders, whether the page boots from the SPA shell or hydrates markup the
/// server wrote. So a German reader fetches the German core and the route's
/// German parts and never an English part, cold deep link and prerendered
/// page alike. Hydrating over English markup in German is safe because
/// Svelte rewrites a text node or attribute whose value differs as it
/// hydrates; a component that picks different STRUCTURE by locale reads
/// `structureLocale()` instead. decisions § 1812.
export async function loadRouteCatalogues(routeId: string | null | undefined): Promise<void> {
	const parts = partsForRoute(routeId, GROUPS);
	if (browser && firstLoad) {
		firstLoad = false;
		hydratingServerMarkup = holdsServerMarkup(document.body.querySelector(':scope > div'));
		const next = negotiatedLocale();
		if (await catalogues.open(next, parts)) applyDocumentLocale(next);
		return;
	}
	await catalogues.ensureAreas(parts);
}

function applyDocumentLocale(next: Locale): void {
	// Keep the pure date/time formatters (time.ts) in sync with the active
	// locale (W-12). The FORMAT locale is the full browser locale when it is
	// a regional variant of the active catalogue locale (e.g. catalogue 'en'
	// + browser 'en-GB' → format with 'en-GB' so dates read "20 Jun 2026",
	// not the US "Jun 20, 2026"); otherwise the catalogue locale itself (an
	// explicit picker choice like 'de' wins over an unrelated browser tag).
	// Done outside the browser gate so it tracks even in non-DOM contexts.
	let formatLocale: string = next;
	if (browser && typeof navigator !== 'undefined' && navigator.language) {
		const nav = navigator.language;
		if (nav.toLowerCase().split('-')[0] === next) formatLocale = nav;
	}
	setActiveFormatLocale(formatLocale);
	if (!browser) return;
	try {
		localStorage.setItem('locale', next);
	} catch {
		/* storage may be unavailable (private mode / quota) — non-fatal */
	}
	document.documentElement.lang = next;
	document.documentElement.dir = dirForLocale(next);
}

// Switch the active locale. The new locale's core and every area already in
// use are fetched first and swapped in together, so the page never shows one
// language's core over another's area; on failure the current locale and dict
// stay (layered resilience — a failed locale fetch must not blank the UI).
export async function setLocale(next: Locale): Promise<void> {
	if (await catalogues.setLocale(next)) applyDocumentLocale(next);
}

// The visitor's locale: a stored choice wins, else navigator.language(s).
function negotiatedLocale(): Locale {
	let stored: string | null = null;
	try {
		stored = localStorage.getItem('locale');
	} catch {
		/* ignore */
	}
	const navLangs =
		typeof navigator !== 'undefined'
			? (navigator.languages?.join(',') ?? navigator.language ?? null)
			: null;
	return negotiateLocale(navLangs, stored);
}

// Apply the visitor's locale on first client mount. Called once from
// +layout.svelte. loadRouteCatalogues has already applied it before the first
// render, so this fetches nothing; it is the retry when that first apply
// could not fetch the locale's core. Hydration is over by the time any
// onMount runs, so a component choosing structure by locale may now follow
// the reader's (structureLocale).
export function initLocale(): void {
	if (!browser) return;
	hydratingServerMarkup = false;
	void setLocale(negotiatedLocale());
}

export { isSupportedLocale };
export type { Locale };
