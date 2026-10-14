import type { LayoutLoad } from './$types';
import { loadHelpGuides } from '#lib/help/localized.svelte.ts';
import { currentLocale } from '#lib/i18n/store.svelte.ts';

// A translated locale's guides are one fetched JSON file (docs/features/help.md
// § Translation), loaded before a help page renders so it opens in the
// reader's language rather than switching from English. Never rejects: a
// failed fetch leaves the English guides, each saying it is in English.
export const load: LayoutLoad = async ({ parent, fetch }) => {
	await parent();
	await loadHelpGuides(currentLocale(), fetch);
};
