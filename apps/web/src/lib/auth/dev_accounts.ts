// Dev only: the accounts apps/backend/supabase/seed.sql creates on every
// `supabase db reset`, for the login page's one-click sign-in. The login page
// reaches this module through a dynamic import inside an
// `import.meta.env.DEV` branch, which a production build removes, so no
// build contains it: scripts/check_web_dev_only_code.mjs fails the build if
// the first account's email ever reaches the client. The panel also hides
// itself unless the Supabase URL is a loopback address, so a dev server
// pointed anywhere else shows nothing.

export interface DevAccount {
	label: string;
	email: string;
	password: string;
}

export const DEV_SIGN_IN_HEADING = 'Dev sign-in (local seed accounts)';

export const DEV_ACCOUNTS: readonly DevAccount[] = [
	{ label: 'Runner (main test user, with runs)', email: 'runner@test.com', password: 'testtest' },
	{ label: 'Alex (follows Runner)', email: 'alex@test.com', password: 'testtest' },
	{ label: 'Morgan', email: 'morgan@test.com', password: 'testtest' },
];

/** Whether `url` names this machine: the only Supabase the seed accounts exist on. */
export function isLoopbackUrl(url: string | null | undefined): boolean {
	if (!url) return false;
	try {
		const host = new URL(url).hostname;
		return host === 'localhost' || host === '127.0.0.1' || host === '::1' || host === '[::1]';
	} catch {
		return false;
	}
}
