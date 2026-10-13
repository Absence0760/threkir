// The help guides in the reader's language (docs/features/help.md §
// Translation). English is bundled (`index.ts`); a translated locale is one
// generated JSON file under /help-guides/, fetched the first time that locale
// is needed. Until it arrives, or if it never does, the reader gets the
// English guides, each marked `lang: 'en'` so the page says so.

import { browser } from '$app/environment';
import { currentLocale } from '#lib/i18n/store.svelte.ts';
import { createHelpIndex, type HelpIndex } from './catalogue';
import { allGuides } from './index';
import { SOURCE_LANG, localizeGuide, mergeFetchedGuides } from './translate';
import type { LocalizedGuide } from './types';

const english = createHelpIndex(
	allGuides().map((g) => localizeGuide(g, undefined, SOURCE_LANG)),
	SOURCE_LANG,
);

let loaded = $state.raw<Record<string, HelpIndex<LocalizedGuide>>>({});
const pending = new Map<string, Promise<void>>();
const failed = new Set<string>();

export function helpGuidesUrl(locale: string): string {
	return `/help-guides/guides.${locale}.json`;
}

/// Fetches `locale`'s guides once. Never rejects: a failed fetch leaves the
/// English guides in place and is retried by the next explicit call (the help
/// layout's load), not by every render.
export function loadHelpGuides(locale: string, fetcher: typeof fetch = fetch): Promise<void> {
	if (locale === SOURCE_LANG || loaded[locale]) return Promise.resolve();
	const inFlight = pending.get(locale);
	if (inFlight) return inFlight;
	failed.delete(locale);
	const request = fetcher(helpGuidesUrl(locale))
		.then((res) => {
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			return res.json() as Promise<unknown>;
		})
		.then((raw) => {
			loaded = { ...loaded, [locale]: createHelpIndex(mergeFetchedGuides(allGuides(), raw, locale), locale) };
		})
		.catch((e: unknown) => {
			failed.add(locale);
			console.warn(`help: the ${locale} guides could not be loaded, showing English`, e);
		})
		.finally(() => pending.delete(locale));
	pending.set(locale, request);
	return request;
}

/// The guide index in the active locale, or English while that locale's
/// guides are loading or unavailable.
export function helpIndex(): HelpIndex<LocalizedGuide> {
	const locale = currentLocale();
	const index = loaded[locale];
	if (index) return index;
	if (browser && locale !== SOURCE_LANG && !pending.has(locale) && !failed.has(locale)) void loadHelpGuides(locale);
	return english;
}
