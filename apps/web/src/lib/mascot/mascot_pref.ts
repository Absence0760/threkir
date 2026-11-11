/// The signed-in runner's `show_mascot`, for components that do not load the
/// settings bag themselves (EmptyState, the onboarding panel). Null means not
/// known yet: a cold cache is an empty bag, and reading it as "on" would flash
/// him for a runner who hid him, so callers keep him hidden until it is known.

import { auth } from '#lib/stores/auth.svelte.ts';
import { loadSettings, peekCachedSettings } from '#lib/settings/settings.ts';
import { mascotShownIn } from './mascot.ts';

export function peekMascotShown(): boolean | null {
	const uid = auth.user?.id;
	if (!uid) return null;
	const cached = peekCachedSettings(uid);
	if (Object.keys(cached.universal).length === 0 && Object.keys(cached.device).length === 0) return null;
	return mascotShownIn(cached);
}

/// The server's answer, or the cached one when the read fails.
export async function loadMascotShown(): Promise<boolean | null> {
	const uid = auth.user?.id;
	if (!uid) return null;
	try {
		return mascotShownIn(await loadSettings(uid));
	} catch (e) {
		console.warn('show_mascot read failed', e);
		return peekMascotShown();
	}
}
