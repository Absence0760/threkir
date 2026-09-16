<script lang="ts">
	import { goto } from '$app/navigation';
	import { m } from '$lib/i18n/store.svelte';
	import { supabase } from '$lib/core/supabase';
	import { checkSignUpGates } from '$lib/core/auth_gates';
	import { defaultUnitForLocale } from '$lib/format/locale_defaults';
	import AuthShell from '$lib/components/auth/AuthShell.svelte';

	// Post-OAuth fallback gate. Reached from /auth/callback when the
	// user's user_profiles row is missing `age_confirmed_at` or
	// `terms_accepted_at`. Re-asks for the same affirmation the
	// /login sign-up flow captures, then stamps via the SECURITY
	// DEFINER `confirm_age_and_terms()` RPC.
	//
	// Server-side enforcement story: a user who skips this page (closes
	// the tab, or hits /dashboard directly via a stale URL) keeps a
	// profile with null consent timestamps. Future RPC guards can
	// reject privileged operations against such accounts. See migration
	// 20260929_001 + audit/gdpr (2026-05-25) Critical.

	let confirmAdult = $state(false);
	let acceptTerms = $state(false);
	let loading = $state(false);
	let error = $state('');

	async function handleSubmit(e: Event) {
		e.preventDefault();
		error = '';
		const gate = checkSignUpGates(true, confirmAdult, acceptTerms);
		if (!gate.ok) {
			error = gate.reason === 'adult' ? m('login.gateAdult') : m('login.gateTerms');
			return;
		}
		loading = true;
		try {
			const { error: rpcError } = await supabase.rpc('confirm_age_and_terms', {
				p_preferred_unit: defaultUnitForLocale(navigator.language),
			});
			if (rpcError) throw rpcError;
			goto('/dashboard');
		} catch (err) {
			error = err instanceof Error ? err.message : m('confirmAge.recordConsentError');
		} finally {
			loading = false;
		}
	}
</script>

<svelte:head>
	<title>{m('confirmAge.title')} — Threkir</title>
</svelte:head>

<AuthShell>
	<main class="auth-card confirm-card" id="main-content">
		<h1>{m('confirmAge.heading')}</h1>
		<p class="lede">
			{m('confirmAge.lede')}
		</p>

		<form onsubmit={handleSubmit}>
			<label class="check">
				<input type="checkbox" bind:checked={confirmAdult} />
				<span>{m('confirmAge.adultCheckbox')}</span>
			</label>

			<label class="check">
				<input type="checkbox" bind:checked={acceptTerms} />
				<span>
					{m('confirmAge.termsPrefix')}
					<a href="/terms" target="_blank" rel="noopener noreferrer">{m('legal.termsOfService')}</a> {m('confirmAge.termsBetween')}
					<a href="/privacy" target="_blank" rel="noopener noreferrer">{m('legal.privacyPolicy')}</a>{m('confirmAge.termsSuffix')}
				</span>
			</label>

			{#if error}
				<p class="error" role="alert">{error}</p>
			{/if}

			<button
				type="submit"
				class="btn btn-primary confirm-cta"
				disabled={loading || !confirmAdult || !acceptTerms}
			>
				{loading ? m('confirmAge.saving') : m('confirmAge.continue')}
			</button>
		</form>

		<p class="fine">
			{m('confirmAge.finePrefix')} {m('confirmAge.fineRequiredValues')}
		</p>
	</main>
</AuthShell>

<style>
	/* The card chrome and the brand panel belong to AuthShell. */
	.confirm-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	h1 {
		margin: 0;
		font-size: 1.85rem;
		font-weight: 800;
		line-height: 1.15;
		letter-spacing: -0.025em;
		text-wrap: balance;
	}
	.lede {
		color: var(--color-text-secondary);
		margin: 0;
		line-height: 1.55;
	}
	form {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-top: var(--space-xs);
	}
	/* Each confirmation is a whole-row target, and a ticked row says so with
	   more than a 13px box. */
	.check {
		display: flex;
		gap: var(--space-sm);
		align-items: flex-start;
		line-height: 1.45;
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		cursor: pointer;
		transition:
			border-color var(--transition-fast),
			background var(--transition-fast),
			box-shadow var(--transition-fast);
	}
	.check:hover {
		border-color: var(--color-text-secondary);
	}
	.check:has(input:checked) {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
		box-shadow: 0 0 0 1px var(--color-primary);
	}
	.check input {
		margin-top: 0.2rem;
		flex-shrink: 0;
	}
	.check a {
		color: inherit;
		text-decoration: underline;
	}
	.confirm-cta {
		min-height: 3rem;
		border-radius: var(--radius-lg);
		margin-top: var(--space-xs);
	}
	.error {
		color: var(--color-danger-text);
		margin: 0;
	}
	.fine {
		font-size: 0.875rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		margin: 0;
	}
</style>
