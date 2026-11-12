/// The signed-in runner's `show_mascot`, for components that do not load the
/// settings bag themselves (EmptyState, the onboarding panel). The reading
/// rules, including what null means, are in mascot_pref_read.ts.

import { auth } from '#lib/stores/auth.svelte.ts';
import { loadSettings, peekCachedSettings } from '#lib/settings/settings.ts';
import { loadMascotShownFrom, peekMascotShownFrom, type MascotPrefSource } from './mascot_pref_read.ts';

function source(): MascotPrefSource {
	return { userId: auth.user?.id, peek: peekCachedSettings, load: loadSettings };
}

export function peekMascotShown(): boolean | null {
	return peekMascotShownFrom(source());
}

export async function loadMascotShown(): Promise<boolean | null> {
	return loadMascotShownFrom(source());
}
