import { m } from '#lib/i18n/store.svelte.ts';
import type { RaceCourseSource, RaceProvider } from '#lib/types.ts';

// Who listed a race, as the race detail page says it. Provider names are
// brands and stay untranslated; `manual` is a hand-added listing, credited to
// the verified club that claimed it when there is one (decisions § 2381) and
// otherwise to "a runner".
const PROVIDER_NAMES: Record<RaceProvider, string | null> = {
	runsignup: 'RunSignUp',
	ultrasignup: 'UltraSignup',
	chronotrack: 'ChronoTrack',
	raceresult: 'RaceResult',
	parkrun: 'parkrun',
	manual: null
};

export function raceSourceLabel(provider: string, organiserName: string | null = null): string {
	const name = (PROVIDER_NAMES as Record<string, string | null | undefined>)[provider];
	if (name) return m('races.sourceProvider', { provider: name });
	return organiserName ? m('races.sourceClub', { club: organiserName }) : m('races.sourceManual');
}

/// Where a linked course came from (decisions § 2381, issue #1297 decision 6).
/// Null for a course linked before claims existed, which names no club.
export function raceCourseSourceLabel(
	source: RaceCourseSource | null,
	organiserName: string | null
): string | null {
	if (!source || !organiserName) return null;
	return source === 'official'
		? m('raceCourse.sourceOfficial', { club: organiserName })
		: m('raceCourse.sourceTraced', { club: organiserName });
}
