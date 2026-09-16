<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/core/supabase';
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { defaultUnitForLocale } from '$lib/format/locale_defaults';
	import { verifyConsentStamped } from '$lib/core/auth_confirmation';
	import AuthShell from '$lib/components/auth/AuthShell.svelte';

	let error = $state('');

	onMount(async () => {
		// Supabase PKCE flow: auth code arrives in the query string (?code=…), not the hash.
		const { error: authError } = await supabase.auth.exchangeCodeForSession(
			window.location.search.substring(1)
		);

		if (authError) {
			// The client's detectSessionInUrl bootstrap can win a race with
			// this explicit exchange — it consumes the code + PKCE verifier
			// first, leaving our call to fail with "code verifier not found"
			// even though a valid session now exists. Treat that as success:
			// only surface the error when no session was established.
			const { data: { session } } = await supabase.auth.getSession();
			if (!session) {
				error = authError.message;
				return;
			}
		}

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
			supabase.rpc('get_my_profile').maybeSingle(),
		);
		if (consent === 'needs-consent') {
			goto('/auth/confirm-age');
			return;
		}

		goto('/dashboard');
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
