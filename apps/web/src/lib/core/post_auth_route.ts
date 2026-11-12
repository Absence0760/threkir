/// Where a signed-in account belongs before any app page paints, and
/// whether the root layout must hold the app shell until that is known.
///
/// A brand-new account used to land on /dashboard, paint it, and only then
/// bounce to /onboarding once the profile hydrated (decisions § 2149). Both
/// halves live here, pure, so the sign-in hops and the layout cannot drift.

export const ONBOARDING_PATH = '/onboarding';
export const CONSENT_PATH = '/auth/confirm-age';
const DEFAULT_LANDING = '/dashboard';

export interface PostAuthProfile {
	consent_recorded: boolean;
	onboarded_at: string | null;
}

/// The gate an account still owes, or null once it owes none. Consent comes
/// first: the onboarding wizard writes to a profile the Art 8 gate guards.
export function pendingGate(profile: PostAuthProfile): string | null {
	if (!profile.consent_recorded) return CONSENT_PATH;
	if (profile.onboarded_at == null) return ONBOARDING_PATH;
	return null;
}

/// Destination for a sign-in hop. Only the default landing is diverted: an
/// explicit return_to may name a surface the layout deliberately exempts from
/// the gates (a club invite, a share page), and for a gated one the layout's
/// hold already keeps it from painting. A profile that failed to load (null)
/// never diverts, so a read failure cannot send an onboarded account back
/// through the wizard.
export function postAuthDestination(profile: PostAuthProfile | null, target: string): string {
	if (profile == null) return target;
	const path = target.split(/[?#]/, 1)[0];
	if (path !== DEFAULT_LANDING) return target;
	return pendingGate(profile) ?? target;
}

/// True while the layout must render its neutral loading state in place of
/// the app shell. `gatedPath` is false for every surface the layout lets
/// render without auth, so public pages never wait. A failed profile load
/// releases the hold (the old behaviour) rather than trapping the user.
export function holdAppShell(input: {
	loggedIn: boolean;
	gatedPath: boolean;
	profile: PostAuthProfile | null;
	profileFailed: boolean;
}): boolean {
	if (!input.loggedIn || !input.gatedPath) return false;
	if (input.profile == null) return !input.profileFailed;
	return pendingGate(input.profile) != null;
}
