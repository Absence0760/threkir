// Pure halves of apple-token-exchange: reading the request, and deciding
// which Apple client a credential belongs to. The handler does the I/O.

import type { AppleClients } from '../_shared/apple_auth.ts';

/// The Apple client that issued a credential. iOS's native flow issues to
/// the app's bundle id; Android's `sign_in_with_apple` and web's GoTrue
/// redirect both go through the Services ID. A code exchanged against the
/// wrong one is refused by Apple, so the client must say which it used.
export type AppleFlow = 'native' | 'web';

/// An authorization code (iOS, Android) or the refresh token GoTrue handed
/// web's OAuth session. Exactly one.
export type AppleTokenRequest =
	| { kind: 'code'; code: string; flow: AppleFlow }
	| { kind: 'refresh_token'; refreshToken: string; flow: 'web' };

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
	if (code && !refreshToken) {
		// No default: guessing the flow is exactly how an Android code was
		// once exchanged against the bundle id and silently refused.
		if (b.client !== 'native' && b.client !== 'web') return null;
		return { kind: 'code', code, flow: b.client };
	}
	if (refreshToken && !code) return { kind: 'refresh_token', refreshToken, flow: 'web' };
	return null;
}

/// Null when that flow's client is not configured, so nothing is stored
/// that delete-account could not later revoke.
export function clientIdFor(req: AppleTokenRequest, clients: AppleClients): string | null {
	return req.flow === 'native' ? clients.native : clients.web;
}

type IdentityLike = { provider: string; id?: string; identity_data?: Record<string, unknown> | null };

/// The Apple user id (`sub`) the account is linked to, or null when it has
/// no Apple identity. A credential is stored only when Apple says it belongs
/// to this same `sub`; otherwise an account could keep, and later have us
/// revoke, a token that is not its own.
export function appleSubjectOf(user: { identities?: IdentityLike[] | null }): string | null {
	const identity = user.identities?.find((i) => i.provider === 'apple');
	if (!identity) return null;
	const sub = identity.identity_data?.sub;
	if (typeof sub === 'string' && sub !== '') return sub;
	return identity.id && identity.id !== '' ? identity.id : null;
}
