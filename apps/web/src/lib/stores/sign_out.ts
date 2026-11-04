export type SignOutScope = 'local' | 'global';

export interface SignOutError {
	message?: string;
}

export interface AuthSignOutClient {
	signOut(options: { scope: SignOutScope }): Promise<{ error: SignOutError | null }>;
}

/// Single seam the local "Sign out" and the "Sign out everywhere" affordances
/// both route through, so the only thing that differs between them is `scope`.
/// `local` invalidates just this browser context; `global` also revokes every
/// refresh token server-side (mobile + watch + other browsers) — the action a
/// user reaches for when they suspect a token was exfiltrated. Returns the
/// provider error (or null) rather than throwing so each caller can decide
/// whether to swallow it (local Sign out) or fail closed (global).
///
/// `settlePending` runs first, while the session still exists: it commits a
/// delete still inside its undo window, which would otherwise fire after the
/// sign-out with no session, or under whoever signs in next. Settling is
/// auxiliary to signing out, so its failure is logged and the sign-out
/// still runs.
export async function signOutWithScope(
	client: AuthSignOutClient,
	scope: SignOutScope,
	settlePending: () => Promise<void> = async () => {},
): Promise<SignOutError | null> {
	try {
		await settlePending();
	} catch (e) {
		console.error('sign-out: settling a pending delete failed', e);
	}
	const { error } = await client.signOut({ scope });
	return error;
}
