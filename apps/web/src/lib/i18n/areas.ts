// Area-scoped message catalogues (decisions § 1802).
//
// A locale used to be one chunk: a reader who never opens a club, gym or plan
// editor still downloaded every sentence on those screens, and the English
// fallback rode the code bundle for every reader on earth. Now each locale is
// split at build time into a CORE catalogue plus one catalogue per AREA below.
// The root layout's `load` awaits `partsForRoute(route.id)` before any
// component of that route renders, so `m()` stays synchronous and an area key
// can never be read before its catalogue has arrived.
//
// Nobody assigns a key to an area by hand. The Vite plugin
// (`vite_plugin.ts`) derives it from the import graph: a key goes to area A
// when every route that can render a file naming it lies under one of A's
// prefixes, and to core otherwise. Adding a key is therefore unchanged —
// write it in `locales/<tag>.ts` like any other — and so is reusing one on a
// new surface: the next build moves it to core on its own.
//
// An area is a route PREFIX: `/gym` covers `/gym` and every route under it.
// One per top-level segment whose own sentences are worth a round trip
// (about 2 KB of source or more); smaller segments stay in core, where their
// few hundred bytes cost every reader less than a request costs one.
//
// Keys that several areas share are not core's either. The plugin groups
// them by the exact set of areas (and unregistered segments) that render
// them, and a set big enough to be worth a request becomes a GROUP part that
// every route under any of them loads (`partsForRoute`, decisions § 1812).
// Groups are derived, never listed here.

export const AREAS = {
	settings: ['/settings'],
	settingsAccount: ['/settings/account'],
	settingsIntegrations: ['/settings/integrations'],
	settingsGear: ['/settings/gear'],
	settingsDevices: ['/settings/devices'],
	clubs: ['/clubs'],
	routes: ['/routes'],
	routeBuilder: ['/routes/new'],
	plans: ['/plans'],
	planDetail: ['/plans/[id]'],
	runs: ['/runs'],
	dashboard: ['/dashboard'],
	gym: ['/gym'],
	profile: ['/u'],
	coach: ['/coach'],
	nutrition: ['/nutrition'],
	social: ['/social'],
	coaching: ['/coaching'],
	onboarding: ['/onboarding'],
	live: ['/live'],
	share: ['/share'],
	challenges: ['/challenges'],
	recap: ['/recap'],
	login: ['/login'],
	races: ['/races'],
	admin: ['/admin'],
} as const satisfies Record<string, readonly string[]>;

export type Area = keyof typeof AREAS;

export const AREA_NAMES = Object.keys(AREAS) as Area[];

/// True when `routeId` is `prefix` or lies under it. Segment-aware, so
/// `/routes` does not cover `/routesheatmap`.
export function routeUnder(routeId: string, prefix: string): boolean {
	return routeId === prefix || routeId.startsWith(prefix + '/');
}

/// Every area whose catalogue a route needs before it renders. `null` (no
/// matched route — the 404 page) needs none.
export function areasForRoute(routeId: string | null | undefined): Area[] {
	if (!routeId) return [];
	return AREA_NAMES.filter((area) =>
		(AREAS[area] as readonly string[]).some((prefix) => routeUnder(routeId, prefix)),
	);
}

/// Derived groups (decisions § 1812): group name -> the route prefixes that
/// load it. Never written by hand. The Vite plugin derives it from the same
/// scan that places every key (`deriveGroups` in `area_scan.ts`) and serves
/// it as `GROUPS` from `virtual:i18n-catalogues`.
export type GroupTable = Readonly<Record<string, readonly string[]>>;

/// Every catalogue part beyond core that a route needs before it renders:
/// its areas, then each derived group one of whose prefixes covers it.
export function partsForRoute(routeId: string | null | undefined, groups: GroupTable): string[] {
	if (!routeId) return [];
	const covering = Object.keys(groups).filter((g) => groups[g].some((p) => routeUnder(routeId, p)));
	return [...areasForRoute(routeId), ...covering];
}
