import { en } from './locales/en';
import type { Messages } from './messages';
import type { Locale } from './locale';

// One loader per supported locale, typed `Record<Locale, …>` so adding a
// locale to SUPPORTED_LOCALES without a catalogue here is a compile error.
// Each resolves the WHOLE catalogue of its locale.
//
// The app does not use this. The runtime (store.svelte.ts) loads a locale as
// a core part plus one part per area, split at build time by vite_plugin.ts
// (decisions § 1802), so no reader ever downloads a whole catalogue. This
// registry is for the tests that validate every shipped catalogue without
// hard-coding the locale list (messages_parity.test.ts and its siblings);
// `area_catalogues.test.ts` fails if app code imports it.
export const CATALOGUE_LOADERS: Record<Locale, () => Promise<Messages>> = {
	en: () => Promise.resolve(en),
	de: () => import('./locales/de').then((m) => m.messages),
	fr: () => import('./locales/fr').then((m) => m.messages),
	es: () => import('./locales/es').then((m) => m.messages),
	ja: () => import('./locales/ja').then((m) => m.messages),
	'pt-BR': () => import('./locales/pt-BR').then((m) => m.messages),
	'pt-PT': () => import('./locales/pt-PT').then((m) => m.messages),
};
