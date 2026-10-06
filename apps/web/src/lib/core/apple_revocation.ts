/// Keeping a revocable Sign in with Apple credential after web's OAuth
/// callback, so `delete-account` can revoke the Apple grant (App Store
/// Guideline 5.1.1(v)). GoTrue returns the refresh token Apple issued as the
/// session's `provider_refresh_token`, once, on the code exchange; nothing
/// can fetch it later.
///
/// Google's callback carries a `provider_refresh_token` too, so which
/// provider started the flow is stashed before the redirect rather than
/// guessed from the session afterwards.

export const OAUTH_PROVIDER_STASH_KEY = 'oauth_provider';

type SessionLike = { provider_refresh_token?: string | null } | null | undefined;

/// The body to post to `apple-token-exchange`, or null when this callback
/// was not an Apple sign-in or carried no token.
export function appleRevocationRequest(
	stashedProvider: string | null,
	session: SessionLike,
): { refresh_token: string } | null {
	if (stashedProvider !== 'apple') return null;
	const token = session?.provider_refresh_token?.trim();
	return token ? { refresh_token: token } : null;
}

type FunctionsLike = {
	invoke: (name: string, opts: { body: { refresh_token: string } }) => Promise<{ error: unknown }>;
};

/// Posts the token when there is one. Sign-in has already succeeded, so a
/// failure only costs the later revocation: it is logged, never thrown.
export async function keepAppleRevocationCredential(
	functions: FunctionsLike,
	stashedProvider: string | null,
	session: SessionLike,
): Promise<boolean> {
	const body = appleRevocationRequest(stashedProvider, session);
	if (!body) return false;
	try {
		const { error } = await functions.invoke('apple-token-exchange', { body });
		if (error) {
			console.error('apple-token-exchange failed:', error);
			return false;
		}
		return true;
	} catch (e) {
		console.error('apple-token-exchange failed:', e);
		return false;
	}
}
