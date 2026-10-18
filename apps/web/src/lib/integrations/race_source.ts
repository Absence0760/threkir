import { m } from '#lib/i18n/store.svelte.ts';
import type { RaceProvider } from '#lib/types.ts';

// Who listed a race, as the race detail page says it. Provider names are
// brands and stay untranslated; `manual` is a runner's own submission.
const PROVIDER_NAMES: Record<RaceProvider, string | null> = {
	runsignup: 'RunSignUp',
	ultrasignup: 'UltraSignup',
	chronotrack: 'ChronoTrack',
	raceresult: 'RaceResult',
	parkrun: 'parkrun',
	manual: null
};

export function raceSourceLabel(provider: string): string {
	const name = (PROVIDER_NAMES as Record<string, string | null | undefined>)[provider];
	return name ? m('races.sourceProvider', { provider: name }) : m('races.sourceManual');
}
