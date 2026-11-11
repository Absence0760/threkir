import type { MessageKey } from '#lib/i18n/messages.ts';

/// Friendly, actionable categories an auth failure maps to. Supabase's
/// raw `err.message` ("AuthApiException…", "Failed to fetch") is
/// developer jargon no end user should read — and it's unlocalized.
/// Classify into one of these and render the matching i18n message so
/// the banner can tell "wrong password" from "offline" from "that
/// email already has an account". Mobile mirrors the classification in
/// `apps/mobile_android/lib/auth_error.dart` — keep the branches in sync.
export type AuthErrorKind =
	| 'offline'
	| 'invalidCredentials'
	| 'rateLimited'
	| 'emailExists'
	| 'emailNotConfirmed'
	| 'linkExpired'
	| 'weakPassword'
	| 'generic';

/// SQLSTATE classes a database error can carry: every class Postgres and
/// PL/pgSQL define, plus the classes this project's own RPCs raise
/// (`RR` restart_training_plan, `RW` the recurrence dry run, `TR`
/// trim_training_plan, `PC` the propose_plan_change dry run), and `PT`, PostgREST's
/// escape for a chosen HTTP status (`PT429`, park-course reports). A test reads every `errcode` in the migrations and
/// fails when a new one is not covered here.
const SQLSTATE_CLASSES = new Set([
	'00', '01', '02', '03', '08', '09', '0A', '0B', '0F', '0L', '0P', '0Z',
	'20', '21', '22', '23', '24', '25', '26', '27', '28', '2B', '2D', '2F',
	'34', '38', '39', '3B', '3D', '3F', '40', '42', '44', '53', '54', '55',
	'57', '58', '72', 'F0', 'HV', 'P0', 'XX',
	'RR', 'RW', 'TR', 'PC', 'PT',
]);

/// Whether `code` is a SQLSTATE or a PostgREST `PGRST` code, in any case.
/// A bare five-character test also took Node's `EPIPE` and any five-letter
/// word an auth or storage service might send; a SQLSTATE is five
/// characters of `[0-9A-Z]` whose first two name a known class, and
/// GoTrue's snake_case codes and Storage's CamelCase ones can never be one.
/// Mirrors `isDatabaseCode` in mobile's auth_error.dart; `i18n/error_copy.ts`
/// uses this one too.
export function isDatabaseCode(code: string | null | undefined): boolean {
	if (!code) return false;
	const c = code.toUpperCase();
	if (/^PGRST\d{3}$/.test(c)) return true;
	return /^[0-9A-Z]{5}$/.test(c) && SQLSTATE_CLASSES.has(c.slice(0, 2));
}

/// A database code that decides the category on its own, so the message is
/// not read for one its code does not have. `P0001` is the exception: a
/// bare `raise exception` carries it whatever the failure is, and its
/// message is all there is. Mirrors `databaseCodeDecides` in mobile's
/// auth_error.dart.
export function databaseCodeDecides(code: string | null | undefined): boolean {
	return isDatabaseCode(code) && code!.toUpperCase() !== 'P0001';
}

/// Classify an arbitrary auth error. Structural / duck-typed: reads the
/// error's `code` + `status` when present (supabase-js `AuthApiError`
/// carries both) and falls back to matching the message, so plain
/// `TypeError: Failed to fetch` network failures classify too. A database
/// code is never overridden by a word in its message.
export function classifyAuthError(error: unknown): AuthErrorKind {
	const shaped = error as { code?: unknown; status?: unknown; message?: unknown } | null;
	const code = typeof shaped?.code === 'string' ? shaped.code.toLowerCase() : null;
	const status = typeof shaped?.status === 'number' ? shaped.status : null;
	const msg = (
		typeof shaped?.message === 'string' ? shaped.message : String(error ?? '')
	).toLowerCase();
	const readMsg = !databaseCodeDecides(code);
	const says = (text: string) => readMsg && msg.includes(text);

	if (says('failed to fetch') || says('networkerror') || says('load failed')) {
		return 'offline';
	}

	if (
		status === 429 ||
		(code !== null && code.includes('rate')) ||
		says('rate limit') ||
		// The Edge Functions' shared limiter answers 429 with this code, and a
		// caller that rethrows the code as its message loses the status.
		says('rate_limit_exceeded') ||
		says('too many requests')
	) {
		return 'rateLimited';
	}

	// Checked BEFORE invalidCredentials: GoTrue's token endpoint can
	// report an unconfirmed-email sign-in as the OAuth-style
	// `invalid_grant` error carrying the descriptive message "Email not
	// confirmed", not only via the dedicated `email_not_confirmed` code.
	// The invalidCredentials branch below also matches `invalid_grant`,
	// so this specific-message check has to win first — otherwise the
	// user gets a "wrong password" banner and no resend affordance for
	// what is really an unconfirmed account (issue #486).
	if (code === 'email_not_confirmed' || says('email not confirmed')) {
		return 'emailNotConfirmed';
	}

	// An emailed magic / confirmation / reset link opened after it expired
	// or a second time. The fix is a fresh link, which no other kind says.
	if (code === 'otp_expired' || says('link is invalid or has expired')) {
		return 'linkExpired';
	}

	if (
		code === 'invalid_credentials' ||
		code === 'invalid_grant' ||
		says('invalid login credentials') ||
		says('invalid credentials')
	) {
		return 'invalidCredentials';
	}

	if (code === 'user_already_exists' || code === 'email_exists' || says('already registered')) {
		return 'emailExists';
	}

	if (
		code === 'weak_password' ||
		says('weak password') ||
		says('password should be at least') ||
		says('password should contain at least')
	) {
		return 'weakPassword';
	}

	return 'generic';
}

const MESSAGE_KEYS: Record<AuthErrorKind, MessageKey> = {
	offline: 'login.errorOffline',
	invalidCredentials: 'login.errorInvalidCredentials',
	rateLimited: 'login.errorRateLimited',
	emailExists: 'login.errorEmailExists',
	emailNotConfirmed: 'login.errorEmailNotConfirmed',
	linkExpired: 'login.errorLinkExpired',
	weakPassword: 'login.errorWeakPassword',
	generic: 'login.errorGeneric',
};

/// The i18n key for a classified kind. `login.errorWeakPassword` takes
/// a `{min}` param — pass `{ min: PASSWORD_MIN_LENGTH }` to `m()`.
export function authErrorMessageKey(kind: AuthErrorKind): MessageKey {
	return MESSAGE_KEYS[kind];
}

/// Whether surfacing this error kind at the SIGN-UP surface would
/// disclose that an email is already registered. GoTrue only
/// obfuscates a duplicate sign-up (returning a session-less success
/// identical to a fresh one) when email confirmations are ON — a
/// dashboard-managed setting invisible from this repo. With
/// confirmations OFF a duplicate address throws `user_already_exists`
/// (→ `emailExists`), which would otherwise render a distinct "that
/// email already has an account" message and turn sign-up into an
/// account-existence oracle. Defence in depth: the sign-up call site
/// collapses this to the same neutral check-your-email outcome a fresh
/// sign-up shows, regardless of the server toggle. The full fix is prod
/// GoTrue running `enable_confirmations = true` — see
/// docs/features/web_app_auth.md. LOGIN is unaffected: an existing
/// email there classifies as `invalidCredentials`, which is standard.
export function signUpErrorRevealsAccountExistence(kind: AuthErrorKind): boolean {
	return kind === 'emailExists';
}
