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
/// How long a sign-out waits for a pending delete to settle before it signs
/// out anyway. The commit is a single request; one that has not answered in
/// this long is a stalled network, and a Sign out that never finishes leaves
/// the session open on the very device the user is leaving.
export const SIGN_OUT_SETTLE_TIMEOUT_MS = 5_000;

/// Runs `settlePending` (the undo queue's `flush`) before the session ends,
/// so a delete still inside its undo window commits as the account that made
/// it rather than firing later with no session, under whoever signs in next,
/// or against an account that has just been deleted. Settling is auxiliary to
/// ending the session: a failure is logged and so is a settle still running
/// after `SIGN_OUT_SETTLE_TIMEOUT_MS`, and neither stops the caller. The
/// request already in flight keeps the token it was sent with and may still
/// land. Never throws. Mobile's `settleBeforeSessionEnds` in `sign_out.dart`.
export async function settleBeforeSessionEnds(settlePending: () => Promise<void>): Promise<void> {
	const settled = (async () => {
		try {
			await settlePending();
		} catch (e) {
			console.error('sign-out: settling a pending delete failed', e);
		}
		return true;
	})();
	let timer: ReturnType<typeof setTimeout> | undefined;
	const timedOut = new Promise<false>((resolve) => {
		timer = setTimeout(() => resolve(false), SIGN_OUT_SETTLE_TIMEOUT_MS);
	});
	const inTime = await Promise.race([settled, timedOut]);
	clearTimeout(timer);
	if (!inTime) {
		console.warn(
			`sign-out: a pending delete had not settled after ${SIGN_OUT_SETTLE_TIMEOUT_MS} ms; ending the session anyway`,
		);
	}
}

/// `settlePending` runs first, while the session still exists
/// (`settleBeforeSessionEnds`); the sign-out runs whatever it did.
export async function signOutWithScope(
	client: AuthSignOutClient,
	scope: SignOutScope,
	settlePending: () => Promise<void> = async () => {},
): Promise<SignOutError | null> {
	await settleBeforeSessionEnds(settlePending);
	const { error } = await client.signOut({ scope });
	return error;
}

/// Feed every auth state change's session user id (null when there is no
/// session); calls [onSessionEnded] with the prior user's id each time a
/// session ends or is replaced by another user's. The auth listener runs
/// this synchronously in the same callback that clears `loggedIn`, so the
/// per-user drop has happened before the auth guard reacts to the
/// signed-out state and navigates to /login. supabase-js notifies
/// SIGNED_OUT from inside `signOut()`, before that call returns to
/// `logout()`, and it also fires for an expired refresh token or a
/// sign-out in another tab, which never pass through `logout()` at all.
export function trackSessionUser(
	onSessionEnded: (priorUserId: string) => void,
): (sessionUserId: string | null) => void {
	let current: string | null = null;
	return (sessionUserId) => {
		const prior = current;
		current = sessionUserId;
		if (prior !== null && prior !== sessionUserId) onSessionEnded(prior);
	};
}
