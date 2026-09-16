/// Post-confirmation landing + consent verification.
///
/// A GoTrue confirmation link only lands on `/auth/callback` when the
/// hosted project's Site URL + Redirect-URLs allow-list say so — a
/// dashboard setting the code cannot enforce. When it is wrong, the link
/// lands on the project Site URL instead (`/?code=<pkce>`), where
/// `detectSessionInUrl` still exchanges the code and mints a LIVE
/// session, but the consent-stamp retry and the GDPR Art 8 gate never
/// run. Both helpers here exist to make that misconfiguration
/// non-silent. See docs/features/web_app_auth.md § Email confirmation
/// redirect.

/// Routes that legitimately receive a code / token-bearing URL and
/// consume it themselves: the Supabase auth callback, the password-
/// recovery form, and the Strava OAuth return. A code anywhere else is
/// a stray confirmation landing.
const CODE_LANDING_OWNERS = new Set(['/auth/callback', '/auth/reset', '/settings/integrations']);

function normalisePath(pathname: string): string {
	return pathname.length > 1 && pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
}

/// Where a confirmation landing that arrived on the wrong route should
/// be sent, or null when this URL is not a stray landing. The query and
/// hash are carried through untouched so `/auth/callback` can still run
/// the verification itself — a `token_hash` counts alongside a PKCE
/// `code`, because the auth-email link now carries one to whichever
/// landing the hosted project's allow-list permits.
export function strayConfirmationTarget(
	pathname: string,
	search: string,
	hash: string,
): string | null {
	if (CODE_LANDING_OWNERS.has(normalisePath(pathname))) return null;
	const query = new URLSearchParams(search);
	const hasCode = query.has('code') || query.has('token_hash');
	const hasImplicitToken = new URLSearchParams(hash.replace(/^#/, '')).has('access_token');
	if (!hasCode && !hasImplicitToken) return null;
	return `/auth/callback${search}${hash}`;
}

export type ConsentGateOutcome = 'ok' | 'needs-consent';

/// Verifies the caller's profile actually carries BOTH consent
/// timestamps. Fail-closed on every ambiguity — a missing row, a null
/// stamp, a failed read, a thrown error — because the next session
/// refresh does not repeat the check, so a transient failure here would
/// otherwise hand out the app to an account with no recorded consent.
/// `confirm_age_and_terms()` is idempotent, so an already-confirmed user
/// costs at most one extra click.
export async function verifyConsentStamped(
	readProfile: () => PromiseLike<{ data: unknown }>,
): Promise<ConsentGateOutcome> {
	try {
		const { data } = await readProfile();
		const row = data as
			| { age_confirmed_at: string | null; terms_accepted_at: string | null }
			| null;
		return row?.age_confirmed_at && row?.terms_accepted_at ? 'ok' : 'needs-consent';
	} catch (_) {
		return 'needs-consent';
	}
}

/// The email-link verification types GoTrue puts in `type=`. Kept as a
/// runtime list because the value arrives as an untrusted query string;
/// `verifyOtp` rejects anything outside its own union at compile time,
/// so an entry here that supabase-js does not know fails the build.
const EMAIL_OTP_TYPES = [
	'signup',
	'invite',
	'magiclink',
	'recovery',
	'email_change',
	'email',
] as const;

export type EmailOtpLinkType = (typeof EMAIL_OTP_TYPES)[number];

export interface EmailOtpLink {
	token_hash: string;
	type: EmailOtpLinkType;
}

/// Reads a `token_hash` + `type` pair off an auth-email landing URL.
///
/// This is the device-independent half of email confirmation: a
/// `token_hash` mints a session through `verifyOtp` from ANY browser,
/// where the PKCE `?code=` the old link shape produced can only be
/// exchanged by the browser that started the flow (it alone holds the
/// verifier). Mail is read wherever the person happens to be — the iOS
/// Mail in-app browser, webmail in another browser, a second device —
/// so the code form stranded most sign-ups on "PKCE code verifier not
/// found in storage" with the account already confirmed. See
/// docs/features/web_app_auth.md § Email confirmation redirect.
export function emailOtpLink(search: string): EmailOtpLink | null {
	const params = new URLSearchParams(search);
	const tokenHash = params.get('token_hash');
	const type = params.get('type');
	if (!tokenHash || !type) return null;
	if (!(EMAIL_OTP_TYPES as readonly string[]).includes(type)) return null;
	return { token_hash: tokenHash, type: type as EmailOtpLinkType };
}
