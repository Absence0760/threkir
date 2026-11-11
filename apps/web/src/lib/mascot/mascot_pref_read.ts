/// How the runner's `show_mascot` is read, with where it is read from passed
/// in: mascot_pref.ts wires the auth store and the settings cache, both of
/// which live in modules the `tsx --test` runner cannot compile.
///
/// Null means not known yet: a cold cache is an empty bag, and reading it as
/// "on" would flash him for a runner who hid him, so callers keep him hidden
/// until it is known. A cache that cannot be read at all (storage blocked in
/// a private window) is not known either.

import type { LoadedSettings } from '#lib/settings/settings_overlay.ts';
import { mascotShownIn } from './mascot.ts';

export interface MascotPrefSource {
	userId: string | null | undefined;
	peek(userId: string): LoadedSettings;
	load(userId: string): Promise<LoadedSettings>;
}

export function peekMascotShownFrom(src: MascotPrefSource): boolean | null {
	if (!src.userId) return null;
	let cached: LoadedSettings;
	try {
		cached = src.peek(src.userId);
	} catch (e) {
		console.warn('show_mascot cache read failed', e);
		return null;
	}
	if (Object.keys(cached.universal).length === 0 && Object.keys(cached.device).length === 0) return null;
	return mascotShownIn(cached);
}

/// The server's answer, or the cached one when the read fails.
export async function loadMascotShownFrom(src: MascotPrefSource): Promise<boolean | null> {
	if (!src.userId) return null;
	try {
		return mascotShownIn(await src.load(src.userId));
	} catch (e) {
		console.warn('show_mascot read failed', e);
		return peekMascotShownFrom(src);
	}
}
