/// First-touch sign-up source, the I/O half (decisions § 2350). The pure
/// helpers are in `signup_source.ts`.
///
/// Auxiliary to the sign-up it rides on: a failed gate read degrades to "no
/// source", never to a failed sign-up.

import { supabase } from './supabase';
import { browserSessionStore, readFirstTouch, type SignupSource } from './signup_source';

/// What a sign-up records as `signup_source` in its GoTrue metadata: this
/// tab's first touch, but only while the `signup_source` gate is open, so a
/// closed gate stores nothing about where the person came from.
export async function signupSourceFor(): Promise<SignupSource | null> {
	const touch = readFirstTouch(browserSessionStore());
	if (!touch) return null;
	try {
		const { data, error } = await supabase.rpc('signup_source_enabled', undefined, { get: true });
		if (error) {
			console.error('signup_source_enabled failed', error.message);
			return null;
		}
		return data === true ? touch : null;
	} catch (e) {
		console.error('signup_source_enabled failed', e);
		return null;
	}
}
