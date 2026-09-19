/// Open/closed state for the named disclosures on a surface, remembered
/// across visits.
///
/// `localStorage` is browser-scoped, not account-scoped, so the key carries
/// the account id the way `training/goals.ts` and the nutrition water counter
/// do — a shared browser must not hand the next account the previous one's
/// layout. It is per-viewer view state, the same class as the `runs_filters_v1`
/// / `routes_filters_v1` blobs, so it stays local rather than costing a
/// `user_settings` bag key and a round trip on every toggle.
///
/// Every read and write is wrapped: storage throws in a private window, on a
/// blocked origin and at quota, and a surface whose layout depends on it must
/// still render. A failed read falls back to the caller's defaults.

const KEY_PREFIX = 'run_app.disclosure_v1';

export type DisclosureState = Record<string, boolean>;

export function disclosureStorageKey(scope: string, userId: string | null | undefined): string {
	return `${KEY_PREFIX}:${scope}:${userId ?? 'anon'}`;
}

/// Overlay a stored blob onto the defaults. A key the surface no longer
/// declares is dropped and a non-boolean value is ignored, so a section added
/// after the blob was written opens in the direction it was designed for
/// rather than in whatever the old blob happened to hold.
export function mergeDisclosureState(defaults: DisclosureState, stored: unknown): DisclosureState {
	const merged: DisclosureState = { ...defaults };
	if (stored === null || typeof stored !== 'object' || Array.isArray(stored)) return merged;
	for (const [key, value] of Object.entries(stored as Record<string, unknown>)) {
		if (key in merged && typeof value === 'boolean') merged[key] = value;
	}
	return merged;
}

export function readDisclosureState(
	scope: string,
	userId: string | null | undefined,
	defaults: DisclosureState,
): DisclosureState {
	try {
		const raw = localStorage.getItem(disclosureStorageKey(scope, userId));
		return mergeDisclosureState(defaults, raw === null ? null : JSON.parse(raw));
	} catch (_) {
		return { ...defaults };
	}
}

export function writeDisclosureState(
	scope: string,
	userId: string | null | undefined,
	state: DisclosureState,
): void {
	try {
		localStorage.setItem(disclosureStorageKey(scope, userId), JSON.stringify(state));
	} catch (_) {
		/* storage unavailable or full — the surface still renders */
	}
}
