/// GoTrue refuses an OAuth sign-in or an identity link by redirecting to
/// `/auth/callback` with `error` / `error_code` / `error_description`
/// instead of a `code` — in the query for the PKCE flow, in the fragment
/// for the implicit one. supabase-js's own URL detection keeps an existing
/// session through such a refusal, so on the callback "a session exists"
/// is not proof the redirect succeeded: a refused link by a signed-in
/// runner looks exactly like a successful sign-in unless these are read.
/// See docs/features/web_app_auth.md § Refused OAuth redirects.

export interface AuthRedirectError {
	error: string | null;
	code: string | null;
	description: string | null;
}

/// The refusal carried by a callback URL, or null when there is none.
/// The fragment is read first and the query overrides it per key, the
/// same precedence supabase-js applies; an empty value counts as absent.
export function authRedirectError(search: string, hash: string): AuthRedirectError | null {
	const params = new Map<string, string>();
	for (const source of [hash.replace(/^#/, ''), search.replace(/^\?/, '')]) {
		for (const [key, value] of new URLSearchParams(source)) params.set(key, value);
	}
	const error = params.get('error') || null;
	const code = params.get('error_code') || null;
	const description = params.get('error_description') || null;
	if (!error && !code && !description) return null;
	return { error, code, description };
}

/// Set by the Sign-in methods section before `linkIdentity`, so the
/// callback can tell a link (the runner was already signed in) from a
/// sign-in. A sibling of OAUTH_PROVIDER_STASH_KEY, which the sign-in
/// buttons own.
export const OAUTH_LINK_STASH_KEY = 'oauth_link_provider';

/// Hands a refused link from the callback back to the account page.
export const LINK_REFUSAL_STASH_KEY = 'oauth_link_refusal';

/// Where a link attempt returns to, refused or not.
export const SIGN_IN_METHODS_PATH = '/settings/account#sign-in-methods';

const LINK_PROVIDERS = ['google', 'apple'] as const;
export type LinkProvider = (typeof LINK_PROVIDERS)[number];

export function parseLinkProvider(value: string | null | undefined): LinkProvider | null {
	return (LINK_PROVIDERS as readonly string[]).includes(value ?? '') ? (value as LinkProvider) : null;
}

export interface LinkRefusal extends AuthRedirectError {
	provider: LinkProvider;
}

export function encodeLinkRefusal(refusal: LinkRefusal): string {
	return JSON.stringify(refusal);
}

/// Session storage is writable by anything on the origin, so the value is
/// validated rather than trusted; anything malformed reads as no refusal.
export function decodeLinkRefusal(raw: string | null | undefined): LinkRefusal | null {
	if (!raw) return null;
	let parsed: unknown;
	try {
		parsed = JSON.parse(raw);
	} catch (_) {
		return null;
	}
	if (!parsed || typeof parsed !== 'object') return null;
	const bag = parsed as Record<string, unknown>;
	const provider = parseLinkProvider(typeof bag.provider === 'string' ? bag.provider : null);
	if (!provider) return null;
	const text = (v: unknown) => (typeof v === 'string' && v ? v : null);
	return { provider, error: text(bag.error), code: text(bag.code), description: text(bag.description) };
}

/// The text a generic failure shows in its `{error}` slot.
export function authRedirectErrorDetail(e: AuthRedirectError): string {
	return e.description ?? e.code ?? e.error ?? 'unspecified_error';
}
