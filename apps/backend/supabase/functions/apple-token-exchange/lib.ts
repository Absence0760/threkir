// Pure halves of apple-token-exchange: reading the request, and deciding
// which Apple client a credential belongs to. The handler does the I/O.

import type { AppleClients } from '../_shared/apple_auth.ts';

/// iOS sends the native flow's one-time authorization code; web sends the
/// refresh token GoTrue handed back in the OAuth session. Exactly one.
export type AppleTokenRequest =
	| { kind: 'code'; code: string }
	| { kind: 'refresh_token'; refreshToken: string };

// Apple's codes and tokens are a few hundred characters; anything far past
// that is not one, and is refused before it reaches Apple or Vault.
const MAX_CREDENTIAL_LEN = 2048;

function credential(v: unknown): string | null {
	if (typeof v !== 'string') return null;
	const s = v.trim();
	return s.length > 0 && s.length <= MAX_CREDENTIAL_LEN ? s : null;
}

export function parseAppleTokenRequest(body: unknown): AppleTokenRequest | null {
	if (typeof body !== 'object' || body === null) return null;
	const b = body as Record<string, unknown>;
	const code = credential(b.authorization_code);
	const refreshToken = credential(b.refresh_token);
	if (code && !refreshToken) return { kind: 'code', code };
	if (refreshToken && !code) return { kind: 'refresh_token', refreshToken };
	return null;
}

/// The Apple client the credential was issued to: a native code can only
/// have come from the app's bundle id, a GoTrue refresh token only from the
/// web Services ID. Null when that client is not configured, so nothing is
/// stored that delete-account could not later revoke.
export function clientIdFor(req: AppleTokenRequest, clients: AppleClients): string | null {
	return req.kind === 'code' ? clients.native : clients.web;
}

/// Whether the account signed in with Apple at all. A token for an account
/// that has no Apple identity would be revoking someone else's grant.
export function hasAppleIdentity(
	user: { identities?: { provider: string }[] | null; app_metadata?: Record<string, unknown> },
): boolean {
	if (user.identities?.some((i) => i.provider === 'apple')) return true;
	const providers = user.app_metadata?.providers;
	return Array.isArray(providers) && providers.includes('apple');
}
