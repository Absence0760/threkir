// Sign in with Apple server-to-server calls: trading the native flow's
// one-time authorization code for a refresh token, and revoking that token
// when the account is deleted (App Store Guideline 5.1.1(v)). Both calls
// authenticate with a client secret that is itself an ES256 JWT signed by
// the team's Sign in with Apple key, so there is no static secret to store.
//
// Configuration is fail-closed: with any of APPLE_TEAM_ID / APPLE_KEY_ID /
// APPLE_PRIVATE_KEY unset, appleKeyConfigFromEnv() answers null and callers
// neither store nor revoke anything.

export const APPLE_TOKEN_URL = 'https://appleid.apple.com/auth/token';
export const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke';
const APPLE_AUDIENCE = 'https://appleid.apple.com';

// Apple caps a client secret's lifetime at six months; each call mints its
// own, so a few minutes is all one ever needs.
const CLIENT_SECRET_TTL_S = 300;

export type AppleKeyConfig = { teamId: string; keyId: string; privateKeyPem: string };

/// The two Apple clients a token can have been issued to. The native app's
/// is its bundle id; web's is the Services ID GoTrue's Apple provider uses.
export type AppleClients = { native: string | null; web: string | null };

type EnvGet = (key: string) => string | undefined;

export function appleKeyConfigFromEnv(get: EnvGet = (k) => Deno.env.get(k)): AppleKeyConfig | null {
	const teamId = get('APPLE_TEAM_ID')?.trim();
	const keyId = get('APPLE_KEY_ID')?.trim();
	const privateKeyPem = get('APPLE_PRIVATE_KEY')?.trim();
	if (!teamId || !keyId || !privateKeyPem) return null;
	return { teamId, keyId, privateKeyPem };
}

export function appleClientsFromEnv(get: EnvGet = (k) => Deno.env.get(k)): AppleClients {
	return {
		native: get('APPLE_NATIVE_CLIENT_ID')?.trim() || null,
		web: get('APPLE_WEB_CLIENT_ID')?.trim() || null,
	};
}

function base64url(bytes: Uint8Array): string {
	let bin = '';
	for (const b of bytes) bin += String.fromCharCode(b);
	return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToPkcs8(pem: string): Uint8Array<ArrayBuffer> {
	// Operators paste the .p8 as-is; a secret store that flattened its
	// newlines to literal "\n" is accepted too.
	const body = pem
		.replace(/\\n/g, '\n')
		.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '')
		.replace(/\s+/g, '');
	return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/// The ES256 JWT Apple accepts as `client_secret` for [clientId]. WebCrypto's
/// ECDSA signature is already the raw r||s form JWS wants.
export async function appleClientSecret(
	cfg: AppleKeyConfig,
	clientId: string,
	nowS: number = Math.floor(Date.now() / 1000),
): Promise<string> {
	const enc = new TextEncoder();
	const header = base64url(enc.encode(JSON.stringify({ alg: 'ES256', kid: cfg.keyId })));
	const payload = base64url(
		enc.encode(
			JSON.stringify({
				iss: cfg.teamId,
				iat: nowS,
				exp: nowS + CLIENT_SECRET_TTL_S,
				aud: APPLE_AUDIENCE,
				sub: clientId,
			}),
		),
	);
	const key = await crypto.subtle.importKey(
		'pkcs8',
		pemToPkcs8(cfg.privateKeyPem),
		{ name: 'ECDSA', namedCurve: 'P-256' },
		false,
		['sign'],
	);
	const sig = await crypto.subtle.sign(
		{ name: 'ECDSA', hash: 'SHA-256' },
		key,
		enc.encode(`${header}.${payload}`),
	);
	return `${header}.${payload}.${base64url(new Uint8Array(sig))}`;
}

type FetchFn = (url: string, init: RequestInit) => Promise<Response>;

/// Trades a native-flow authorization code for a refresh token. Apple only
/// returns a refresh token on this first exchange; the code is single-use
/// and expires five minutes after sign-in.
export async function exchangeAppleCode(opts: {
	cfg: AppleKeyConfig;
	clientId: string;
	code: string;
	fetchFn?: FetchFn;
}): Promise<{ refreshToken: string } | { error: string }> {
	const { cfg, clientId, code, fetchFn = fetch } = opts;
	const res = await fetchFn(APPLE_TOKEN_URL, {
		method: 'POST',
		headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
		body: new URLSearchParams({
			client_id: clientId,
			client_secret: await appleClientSecret(cfg, clientId),
			code,
			grant_type: 'authorization_code',
		}),
	});
	let json: Record<string, unknown> = {};
	try {
		json = await res.json();
	} catch {
		// Apple answers JSON on every status it documents; a non-JSON body is
		// reported as the status alone below.
	}
	if (!res.ok) return { error: `apple token ${res.status}: ${String(json.error ?? 'unknown')}` };
	const token = json.refresh_token;
	if (typeof token !== 'string' || token === '') {
		return { error: 'apple token response carried no refresh_token' };
	}
	return { refreshToken: token };
}

/// Revokes [token], invalidating the user's Sign in with Apple session for
/// [clientId]. Apple answers 200 for a token it has already revoked too, so
/// a retry is safe.
export async function revokeAppleToken(opts: {
	cfg: AppleKeyConfig;
	clientId: string;
	token: string;
	fetchFn?: FetchFn;
}): Promise<boolean> {
	const { cfg, clientId, token, fetchFn = fetch } = opts;
	const res = await fetchFn(APPLE_REVOKE_URL, {
		method: 'POST',
		headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
		body: new URLSearchParams({
			client_id: clientId,
			client_secret: await appleClientSecret(cfg, clientId),
			token,
			token_type_hint: 'refresh_token',
		}),
	});
	await res.body?.cancel();
	return res.ok;
}
