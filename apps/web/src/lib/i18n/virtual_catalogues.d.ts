// Served by `vite_plugin.ts`: the per-locale, per-area catalogue loaders
// (decisions § 1802). Only `store.svelte.ts` imports it.
declare module 'virtual:i18n-catalogues' {
	import type { Catalogue } from '$lib/i18n/catalogue_set';
	import type { Locale } from '$lib/i18n/locale';
	import type { Area } from '$lib/i18n/areas';

	/// The default locale's core, bundled synchronously: the `m()` fallback
	/// and the prerender default.
	export const FALLBACK_CORE: Catalogue;
	export const CORE_LOADERS: Record<Locale, () => Promise<Catalogue>>;
	export const AREA_LOADERS: Record<Locale, Record<Area, () => Promise<Catalogue>>>;
}
