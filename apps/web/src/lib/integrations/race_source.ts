import type { MessageKey } from '#lib/i18n/messages.ts';
import type { RaceCourseSource, RaceProvider } from '#lib/types.ts';

// The catalogue lookup arrives as an argument: `m` lives in a runes module the
// `tsx --test` runner cannot compile, and the choice of sentence is the part
// worth testing. Callers pass `m`.
export type Translate = (key: MessageKey, params?: Record<string, string | number>) => string;

// Who listed a race, as the race detail page says it. Provider names are
// brands and stay untranslated; `manual` is a hand-added listing, credited to
// the verified club that claimed it when there is one (decisions § 2381) and
// otherwise to "a runner".
const PROVIDER_NAMES: Record<RaceProvider, string | null> = {
	runsignup: 'RunSignUp',
	ultrasignup: 'UltraSignup',
	chronotrack: 'ChronoTrack',
	raceresult: 'RaceResult',
	manual: null
};

export function raceSourceLabel(t: Translate, provider: string, organiserName: string | null = null): string {
	const name = Object.prototype.hasOwnProperty.call(PROVIDER_NAMES, provider)
		? PROVIDER_NAMES[provider as RaceProvider]
		: null;
	if (name) return t('races.sourceProvider', { provider: name });
	return organiserName ? t('races.sourceClub', { club: organiserName }) : t('races.sourceManual');
}

/// Where a linked course came from (decisions § 2381, issue #1297 decision 6).
/// Null for a course linked before claims existed, which names no club.
export function raceCourseSourceLabel(
	t: Translate,
	source: RaceCourseSource | null,
	organiserName: string | null
): string | null {
	if (!source || !organiserName) return null;
	return source === 'official'
		? t('raceCourse.sourceOfficial', { club: organiserName })
		: t('raceCourse.sourceTraced', { club: organiserName });
}
