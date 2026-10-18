/// The account page's message for a link GoTrue refused. Kept apart from
/// auth_redirect_error.ts, which every route loads through the auth store:
/// the i18n area split follows the import graph (decisions § 1802), so
/// naming these keys there would pull them into the core catalogue.

export type LinkRefusalMessageKey =
	| 'settingsAccount.linkIdentityTaken'
	| 'settingsAccount.linkIdentityNotFound'
	| 'settingsAccount.needOneMethod'
	| 'settingsAccount.linkingDisabled'
	| 'settingsAccount.linkFailed';

/// The message for a refused link, by GoTrue error code (the strings in
/// @supabase/auth-js `lib/error-codes.d.ts`). Every unrecognised code gets
/// the generic failure, which carries GoTrue's own description.
export function linkRefusalMessageKey(code: string | null): LinkRefusalMessageKey {
	switch (code) {
		case 'identity_already_exists':
			return 'settingsAccount.linkIdentityTaken';
		case 'identity_not_found':
			return 'settingsAccount.linkIdentityNotFound';
		case 'single_identity_not_deletable':
			return 'settingsAccount.needOneMethod';
		case 'manual_linking_disabled':
			return 'settingsAccount.linkingDisabled';
		default:
			return 'settingsAccount.linkFailed';
	}
}
