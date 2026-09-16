<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/core/supabase';
	import { auth } from '$lib/stores/auth.svelte';
	import { checkPasswordPair } from '$lib/core/auth_gates';
	import { PASSWORD_MIN_LENGTH } from '$lib/core/auth_rules';
	import { m } from '$lib/i18n/store.svelte';
	import PasswordInput from '$lib/components/PasswordInput.svelte';
	import AuthShell from '$lib/components/auth/AuthShell.svelte';

	let password = $state('');
	let confirmPassword = $state('');
	let error = $state('');
	let busy = $state(false);
	// Recovery token arrives in the URL hash; supabase-js consumes it
	// automatically (detectSessionInUrl=true) on this navigation, then
	// fires onAuthStateChange with a PASSWORD_RECOVERY-tagged session.
	let ready = $state(false);
	// True once updateUser succeeds. When the page unmounts WITHOUT
	// the password having been changed, we sign the recovery session
	// out — see Persona-hunt Round 2 finding Casual #1 below.
	let passwordChanged = $state(false);

	onMount(async () => {
		await auth.ready();
		ready = true;
	});

	// Persona-hunt Round 2 finding Casual #1: supabase-js consumed
	// the #access_token from the recovery URL on page load and minted
	// a live session BEFORE the new password was set. A user on a
	// shared / library / family laptop who opened the reset link
	// then closed the tab without typing left the session live —
	// anyone on that browser hitting /dashboard was signed in as the
	// victim. Fix: sign out on unmount / beforeunload IF the
	// password wasn't actually changed. This explicitly invalidates
	// the recovery session server-side so a stolen-laptop attack
	// can't navigate forward from a stale localStorage entry.
	function cleanupRecoverySession() {
		if (!passwordChanged) {
			// Fire-and-forget — we're unmounting, no await possible.
			supabase.auth.signOut({ scope: 'local' }).catch(() => {});
		}
	}

	onMount(() => {
		const handler = () => cleanupRecoverySession();
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	onDestroy(() => {
		cleanupRecoverySession();
	});

	async function handleSubmit(e: Event) {
		e.preventDefault();
		error = '';
		const pair = checkPasswordPair(password, confirmPassword);
		if (!pair.ok) {
			error = pair.reason === 'too_short'
				? m('authReset.errorTooShort', { min: PASSWORD_MIN_LENGTH })
				: m('authReset.errorMismatch');
			return;
		}
		busy = true;
		try {
			const { error: updateError } = await supabase.auth.updateUser({ password });
			if (updateError) throw updateError;
			// Flip BEFORE refreshSession so unmount triggered by goto
			// doesn't sign out the freshly-set session.
			passwordChanged = true;
			await auth.refreshSession();
			goto('/dashboard');
		} catch (err) {
			error = err instanceof Error ? err.message : m('authReset.errorGeneric');
			busy = false;
		}
	}
</script>

<AuthShell>
	<main class="auth-card reset-card" id="main-content">
		<p class="kicker">{m('authReset.kicker')}</p>
		<h1>{m('authReset.heading')}</h1>

		{#if !ready}
			<p class="muted">{m('authReset.verifying')}</p>
		{:else if !auth.user}
			<p class="muted">{m('authReset.invalidLink')}</p>
			<div class="error-block">
				<p>
					{m('authReset.invalidLinkBody')}
				</p>
			</div>
			<a class="btn btn-primary reset-cta" href="/login?reset=1">{m('authReset.requestNewLink')}</a>
		{:else}
			<p class="subtitle">{m('authReset.subtitlePrefix')} <strong>{auth.user.email}</strong>{m('authReset.subtitleSuffix')}</p>

			{#if error}
				<div class="error" role="alert">{error}</div>
			{/if}

			<form class="reset-form" onsubmit={handleSubmit}>
				<label for="reset-password" class="visually-hidden">
					{m('authReset.newPasswordPlaceholder')}
				</label>
				<PasswordInput
					id="reset-password"
					bind:value={password}
					placeholder={m('authReset.newPasswordPlaceholder')}
					required
					minlength={PASSWORD_MIN_LENGTH}
					autocomplete="new-password"
				/>
				<label for="reset-confirm-password" class="visually-hidden">
					{m('authReset.confirmPasswordPlaceholder')}
				</label>
				<PasswordInput
					id="reset-confirm-password"
					bind:value={confirmPassword}
					placeholder={m('authReset.confirmPasswordPlaceholder')}
					required
					minlength={PASSWORD_MIN_LENGTH}
					autocomplete="new-password"
				/>
				<button type="submit" class="btn btn-primary reset-cta" disabled={busy}>
					{busy ? m('authReset.updating') : m('authReset.updateButton')}
				</button>
			</form>
			<p class="reset-hint">{m('authReset.hint', { min: PASSWORD_MIN_LENGTH })}</p>
		{/if}

		<p class="back-link">
			<a href="/login"><span class="material-symbols" aria-hidden="true">arrow_back</span>{m('authReset.backToSignIn')}</a>
		</p>
	</main>
</AuthShell>

<style>
	/* The card chrome and the brand panel belong to AuthShell. */
	.reset-card {
		text-align: center;
	}

	.kicker {
		display: inline-block;
		text-transform: uppercase;
		letter-spacing: 0.12em;
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-primary);
		background: var(--color-primary-light);
		border-radius: var(--radius-pill);
		padding: 0.3rem 0.75rem;
		margin: 0 0 var(--space-md);
	}

	h1 {
		margin: 0 0 var(--space-sm);
		font-size: 1.85rem;
		font-weight: 800;
		line-height: 1.15;
		letter-spacing: -0.025em;
		color: var(--color-text);
		text-wrap: balance;
	}

	.subtitle {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		margin: 0 0 var(--space-xl);
		line-height: 1.5;
	}
	.subtitle strong {
		color: var(--color-text);
		font-weight: 600;
	}

	.muted {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		margin: 0 0 var(--space-md);
	}

	.reset-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		text-align: start;
	}

	.reset-cta {
		width: 100%;
		min-height: 3rem;
		padding: 0.8rem var(--space-lg);
		border-radius: var(--radius-lg);
		font-size: 0.95rem;
		margin-top: var(--space-xs);
	}

	.reset-hint {
		margin: var(--space-md) 0 0;
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}

	.error {
		background: var(--color-danger-light);
		border: 1px solid color-mix(in srgb, var(--color-danger) 30%, transparent);
		color: var(--color-danger-text);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		text-align: start;
		margin-bottom: var(--space-md);
	}

	.error-block {
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		padding: var(--space-md);
		border-radius: var(--radius-lg);
		text-align: start;
		margin-bottom: var(--space-md);
	}
	.error-block p {
		margin: 0;
		font-size: 0.88rem;
		line-height: 1.5;
		color: var(--color-text-secondary);
	}

	.back-link {
		margin: var(--space-xl) 0 0;
		font-size: 0.88rem;
	}
	.back-link a {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-text-secondary);
		text-decoration: none;
		transition: color var(--transition-fast), gap var(--transition-fast);
	}
	.back-link a:hover {
		color: var(--color-primary);
		gap: var(--space-xs);
	}
	.back-link .material-symbols {
		font-size: 1.1rem;
	}
</style>
