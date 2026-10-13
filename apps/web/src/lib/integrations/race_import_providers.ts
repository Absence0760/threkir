import type { MessageKey } from '#lib/i18n/messages.ts';
import type { ImportRaceResultInput } from '#lib/core/data.ts';
import type { RaceProvider } from '#lib/types.ts';

/// Every provider the `race-results-import` Edge Function has a leg for, read
/// off the call it accepts rather than spelled out again.
export type RaceImportProvider = ImportRaceResultInput['provider'];

/// The listing providers whose result import can be reached from a race in the
/// calendar. Derived from the two vocabularies because they are different sets
/// that merely overlap: `paste` is a leg with no listing behind it, and
/// `parkrun` / `manual` / `raceresult` are listings with no leg — those fall
/// through to the manual paste form, which is the correct answer for them.
export type RaceImportLeg = Extract<RaceProvider, Exclude<RaceImportProvider, 'paste'>>;

export interface RaceImportLegSpec {
	/// What scopes the pull to this runner. A bib is a race number the runner
	/// types per race. UltraSignup is instead scoped by WHO the runner is there —
	/// the person they picked once in Settings (decisions § 1841) — so the import
	/// asks for nothing and `importRaceResult` reads the stored link.
	scopeField: 'bib' | 'linkedPerson';
	/// Whether the Edge Function refuses the call without it. All three legs
	/// reject an unscoped request 400 before any upstream fetch.
	scopeRequired: boolean;
	/// The scope's label: the input's for a bib, the "importing as" line for a
	/// linked person.
	labelKey: MessageKey;
	hintKey: MessageKey;
	/// Shown in place of the form when the leg's credentials are unset
	/// server-side. Per leg: a runner told "RunSignUp import isn't available"
	/// about a ChronoTrack race learns nothing true.
	unavailableKey: MessageKey;
	/// The element that carries the scope: the bib input, or the line naming
	/// the linked person.
	inputTestId: string;
	submitTestId: string;
	unavailableTestId: string;
}

export const RACE_IMPORT_LEGS: Record<RaceImportLeg, RaceImportLegSpec> = {
	runsignup: {
		scopeField: 'bib',
		scopeRequired: true,
		labelKey: 'races.bib',
		hintKey: 'races.runSignUpBibHint',
		unavailableKey: 'integrations.runsignupUnavailable',
		inputTestId: 'runsignup-bib',
		submitTestId: 'race-import-runsignup',
		unavailableTestId: 'race-runsignup-unavailable'
	},
	ultrasignup: {
		scopeField: 'linkedPerson',
		scopeRequired: true,
		labelKey: 'races.ultraSignUpImportingAs',
		hintKey: 'races.ultraSignUpLinkedHint',
		unavailableKey: 'integrations.ultrasignupUnavailable',
		inputTestId: 'ultrasignup-linked-person',
		submitTestId: 'race-import-ultrasignup',
		unavailableTestId: 'race-ultrasignup-unavailable'
	},
	chronotrack: {
		scopeField: 'bib',
		scopeRequired: true,
		labelKey: 'races.bib',
		hintKey: 'races.chronoTrackBibHint',
		unavailableKey: 'integrations.chronotrackUnavailable',
		inputTestId: 'chronotrack-bib',
		submitTestId: 'race-import-chronotrack',
		unavailableTestId: 'race-chronotrack-unavailable'
	}
};

export const RACE_IMPORT_LEG_NAMES = Object.keys(RACE_IMPORT_LEGS) as RaceImportLeg[];

/// The leg a listing's `provider` reaches, or null when it has none.
/// `RaceListingResult.provider` arrives from the RPC as a bare string, so the
/// narrowing happens here rather than at every call site.
export function raceImportLegFor(provider: string): RaceImportLeg | null {
	return Object.hasOwn(RACE_IMPORT_LEGS, provider) ? (provider as RaceImportLeg) : null;
}
