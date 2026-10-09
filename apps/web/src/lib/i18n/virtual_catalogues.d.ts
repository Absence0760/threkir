// Served by `vite_plugin.ts`: the per-locale catalogue loaders, one per area
// (decisions § 1802) and one per derived group (§ 1812). Only
// `store.svelte.ts` imports it.
declare module 'virtual:i18n-catalogues' {
	import type { Catalogue } from '$lib/i18n/catalogue_set';
	import type { Locale } from '$lib/i18n/locale';
	import type { GroupTable } from '$lib/i18n/areas';

	/// The default locale's core, bundled synchronously: the `m()` fallback
	/// and the prerender default.
	export const FALLBACK_CORE: Catalogue;
	export const CORE_LOADERS: Record<Locale, () => Promise<Catalogue>>;
	/// The derived groups of this build: name -> the route prefixes that load it.
	export const GROUPS: GroupTable;
	/// Every area and group part, by name (`partsForRoute` returns these names).
	export const PART_LOADERS: Record<Locale, Readonly<Record<string, () => Promise<Catalogue>>>>;
}
