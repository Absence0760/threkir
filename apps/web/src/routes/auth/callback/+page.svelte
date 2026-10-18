<script lang="ts">
	import { onMount } from 'svelte';
	import { goto, replaceState } from '$app/navigation';
	import { supabase } from '#lib/core/supabase.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { defaultUnitForLocale } from '#lib/format/locale_defaults.ts';
	import { emailOtpLink, verifyConsentStamped } from '#lib/core/auth_confirmation.ts';
	import AuthShell from '#lib/components/auth/AuthShell.svelte';
	import { OAUTH_PROVIDER_STASH_KEY, keepAppleRevocationCredential } from '#lib/core/apple_revocation.ts';
	import {
		LINK_REFUSAL_STASH_KEY,
		OAUTH_LINK_STASH_KEY,
		SIGN_IN_METHODS_PATH,
		authRedirectError,
		authRedirectErrorDetail,
		encodeLinkRefusal,
		parseLinkProvider,
	} from '#lib/core/auth_redirect_error.ts';

	let error = $state('');

	function takeStashed(key: string): string | null {
		try {
			const value = sessionStorage.getItem(key);
			sessionStorage.removeItem(key);
			return value;
		} catch (_) {
			return null;
		}
	}

	onMount(async () => {
		const linking = parseLinkProvider(takeStashed(OAUTH_LINK_STASH_KEY));

		// A refusal must be read before anything else: supabase-js keeps
		// the existing session through it, so the session check further
		// down would report a refused link as a successful sign-in.
		const refused = authRedirectError(window.location.search, window.location.hash);
		if (refused) {
			replaceState(window.location.pathname, {});
			takeStashed(OAUTH_PROVIDER_STASH_KEY);
			const signedIn = linking ? (await supabase.auth.getSession()).data.session : null;
			if (linking && signedIn) {
				try {
					sessionStorage.setItem(
						LINK_REFUSAL_STASH_KEY,
						encodeLinkRefusal({ provider: linking, ...refused }),
					);
					goto(SIGN_IN_METHODS_PATH, { replaceState: true });
					return;
				} catch (_) {
					/* No storage to hand it over with: say it here instead. */
				}
			}
			error = authRedirectErrorDetail(refused);
			return;
		}

		// Two shapes land here. An email link carries `token_hash` +
		// `type`, which `verifyOtp` turns into a session from any
		// browser — mail is read wherever the person happens to be, and
		// the PKCE `?code=` shape can only be exchanged by the browser
		// that started the flow. OAuth still arrives as `?code=`, and
		// there the flow begins and ends in one browser, so the verifier
		// is present.
		const otp = emailOtpLink(window.location.search);
		const { data: exchanged, error: authError } = otp
			? await supabase.auth.verifyOtp(otp)
			: await supabase.auth.exchangeCodeForSession(window.location.search.substring(1));

		// The token is a one-time credential sitting in the address bar;
		// drop it before the page can hand it to anything as a referrer,
		// and so a reload can't retry an already-spent token. Through
		// SvelteKit's own replaceState, not the history API directly —
		// a bare history call desynchronises the router from the URL it
		// thinks it is on, and the navigations below run off that.
		replaceState(window.location.pathname, {});

		let session = exchanged.session;
		if (authError) {
			// The client's detectSessionInUrl bootstrap can win a race with
			// this explicit exchange — it consumes the code + PKCE verifier
			// first, leaving our call to fail with "code verifier not found"
			// even though a valid session now exists. Treat that as success:
			// only surface the error when no session was established.
			session = (await supabase.auth.getSession()).data.session;
			if (!session) {
				error = authError.message;
				return;
			}
		}

		// Apple's refresh token arrives on this exchange only; keep it so
		// account deletion can revoke the grant (Guideline 5.1.1(v)).
		const stashedProvider = takeStashed(OAUTH_PROVIDER_STASH_KEY);
		// Not awaited: nothing below depends on it, and sign-in is already done.
		void keepAppleRevocationCredential(supabase.functions, stashedProvider, session);

		// OAuth-path age + terms capture (audit/gdpr Critical). The
		// pre-redirect tick on /login stashed timestamps in
		// sessionStorage; replay them via the RPC. Idempotent — a
		// returning user (already-stamped profile) is a no-op. If the
		// stash is missing (Safari private mode, returning user, or a
		// callback not initiated from /login), the /auth/confirm-age
		// fallback below re-prompts.
		try {
			const stampedAge = sessionStorage.getItem('age_confirmed_at');
			const stampedTerms = sessionStorage.getItem('terms_accepted_at');
			if (stampedAge && stampedTerms) {
				// Seed the region unit default from the browser locale on the
				// brand-new-row insert; a returning OAuth user's existing
				// choice is preserved by the RPC's insert-only apply (#488).
				await supabase.rpc('confirm_age_and_terms', {
					p_preferred_unit: defaultUnitForLocale(navigator.language),
				});
				sessionStorage.removeItem('age_confirmed_at');
				sessionStorage.removeItem('terms_accepted_at');
			}
		} catch (_) {
			/* RPC failed — the /auth/confirm-age check below catches it. */
		}

		await auth.refreshSession();

		// Profile-level gate: if either consent timestamp is null
		// post-callback, force the confirm-age page before any feature
		// surface renders. /audit/owasp May 2026 Medium #5.
		const consent = await verifyConsentStamped(() =>
			supabase.rpc('get_my_profile', undefined, { get: true }).maybeSingle(),
		);
		if (consent === 'needs-consent') {
			goto('/auth/confirm-age');
			return;
		}

		goto(linking ? SIGN_IN_METHODS_PATH : '/dashboard');
	});
</script>

<AuthShell>
	<main class="auth-card callback-card" id="main-content">
		{#if error}
			<span class="status status--error" aria-hidden="true">
				<span class="material-symbols">error</span>
			</span>
			<p class="message error" role="alert">{m('authCallback.failed', { error })}</p>
			<a class="btn btn-primary back" href="/login">{m('authCallback.backToLogin')}</a>
		{:else}
			<span class="status status--busy" aria-hidden="true"></span>
			<p class="message">{m('authCallback.signingIn')}</p>
		{/if}
	</main>
</AuthShell>

<style>
	/* The card chrome and the brand panel belong to AuthShell. */
	.callback-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
		text-align: center;
	}

	.status {
		display: grid;
		place-items: center;
		width: 3.5rem;
		height: 3.5rem;
		border-radius: var(--radius-pill);
	}

	/* A loading indicator, not decoration: it stops when the page navigates,
	   and the global reduced-motion rule stills it. */
	.status--busy {
		border: 3px solid var(--color-border);
		border-top-color: var(--color-primary);
		animation: spin 900ms linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	.status--error {
		background: var(--color-danger-light);
		color: var(--color-danger-text);
	}

	.status--error .material-symbols {
		font-size: 1.9rem;
	}

	.message {
		margin: 0;
		color: var(--color-text-secondary);
		line-height: 1.55;
		overflow-wrap: anywhere;
	}

	.error {
		color: var(--color-danger-text);
	}

	.back {
		width: 100%;
		min-height: 3rem;
		border-radius: var(--radius-lg);
		margin-top: var(--space-xs);
	}
</style>
