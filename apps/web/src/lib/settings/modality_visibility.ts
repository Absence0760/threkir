import type { LoadedSettings } from './settings_overlay';

/// The non-running modalities a runner can switch on or off. Running is never
/// hidden, so it has no key.
export const MODALITIES = ['gym', 'nutrition'] as const;
export type Modality = (typeof MODALITIES)[number];

export const MODALITY_VISIBILITY_KEYS = {
	gym: 'show_gym',
	nutrition: 'show_nutrition',
} as const satisfies Record<Modality, string>;

/// Whether a modality's entry points are surfaced: its nav item, its Log
/// actions, its Home cards. Mirrors mobile's `modalityShown`.
///
/// An explicit choice always wins. Left unset, the modality shows only once it
/// has data, so a runner who has never logged a lift or a meal gets a run-only
/// app while someone already logging them keeps the surfaces they use without
/// having to find a toggle first (decisions § 1739).
export function modalityShown({
	explicit,
	hasData,
}: {
	explicit: boolean | null;
	hasData: boolean;
}): boolean {
	return explicit ?? hasData;
}

/// The runner's explicit choice, or null when there is none. Both keys are
/// universal-scope, so a device bag is not consulted. A non-bool is treated as
/// no choice rather than as hidden, the same as mobile.
export function explicitModalityChoice(settings: LoadedSettings, modality: Modality): boolean | null {
	const raw = settings.universal[MODALITY_VISIBILITY_KEYS[modality]];
	return typeof raw === 'boolean' ? raw : null;
}

/// Whether anything but runs has been logged, from the two presence reads.
/// One known `true` answers it while the other read is still out; a `false`
/// needs both. History is shown and kept only on `true`: for a runner with
/// runs alone it repeats /runs (decisions § 2114). Mobile reaches the same
/// end by showing its run list inline under History.
export function nonRunDataPresence(gym: boolean | null, nutrition: boolean | null): boolean | null {
	if (gym === true || nutrition === true) return true;
	if (gym === null || nutrition === null) return null;
	return false;
}
