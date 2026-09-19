<script lang="ts">
	import { browser } from '$app/environment';
	import { goto, replaceState } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import {
		checkPasswordPair,
		checkSignUpGates,
		type PasswordPairReason,
		type SignUpGateReason,
	} from '$lib/core/auth_gates';
	import {
		classifyAuthError,
		authErrorMessageKey,
		signUpErrorRevealsAccountExistence,
	} from '$lib/core/auth_errors';
	import { PASSWORD_MIN_LENGTH } from '$lib/core/auth_rules';
	import { defaultUnitForLocale } from '$lib/format/locale_defaults';
	import { verifyConsentStamped } from '$lib/core/auth_confirmation';
	import { safeReturnTo as resolveReturnTo } from '$lib/core/safe_redirect';
	import { googleAuthEnabled } from '$lib/core/google_auth_flag';
	import { appleAuthEnabled } from '$lib/core/apple_auth_flag';
	import { m } from '$lib/i18n/store.svelte';
	import PasswordInput from '$lib/components/PasswordInput.svelte';
	import AuthShell from '$lib/components/auth/AuthShell.svelte';

	// Fail-closed: each provider is off until it is wired on the Supabase
	// side (PUBLIC_GOOGLE_AUTH_ENABLED / PUBLIC_APPLE_AUTH_ENABLED). When off
	// the button keeps its label but shows a "coming soon" pill and the click
	// short-circuits to a notice, because a live click would only surface an
	// opaque provider error.
	const googleEnabled = googleAuthEnabled();
	const appleEnabled = appleAuthEnabled();

	function gateMessage(reason: SignUpGateReason): string {
		return reason === 'adult' ? m('login.gateAdult') : m('login.gateTerms');
	}

	function passwordMessage(reason: PasswordPairReason): string {
		return reason === 'too_short'
			? m('login.errorPasswordTooShort', { min: PASSWORD_MIN_LENGTH })
			: m('login.errorPasswordMismatch');
	}

	let error = $state('');
	let info = $state('');
	let loading = $state(false);
	let email = $state('');
	let password = $state('');
	let confirmPassword = $state('');
	let isSignUp = $state($page.url.searchParams.get('signup') === '1');
	let isReset = $state($page.url.searchParams.get('reset') === '1');
	let confirmAdult = $state(false);
	let acceptTerms = $state(false);
	let hydrated = $state(false);
	// Set to the attempted email when sign-in failed with
	// email_not_confirmed — renders the resend-confirmation affordance.
	let resendFor = $state<string | null>(null);
	// Snapshot return_to at mount, BEFORE either the post-sign-in $effect
	// or the explicit handler goto can fire. The previous version re-read
	// $page.url.searchParams every call, but the $effect's goto mutates
	// the URL to the return_to target on the same tick — caching once
	// removes the race. resolveReturnTo rejects off-origin targets
	// (//evil.com, /\evil.com, absolute URLs) so the attacker-controllable
	// query param can't turn /login into an open-redirect.
	let returnToOnMount = $state<string>('/dashboard');
	onMount(() => {
		hydrated = true;
		returnToOnMount = resolveReturnTo($page.url.searchParams.get('return_to'));
	});

	function safeReturnTo(): string {
		return returnToOnMount;
	}

	$effect(() => {
		if (browser && !auth.loading && auth.loggedIn) {
			goto(safeReturnTo(), { replaceState: true });
		}
	});

	// Both providers take the same path because both CREATE an account on
	// first sign-in: the sign-up gates (16+ + ToS / Privacy acceptance) and
	// the consent stash have to apply to each of them exactly as they do to
	// the email/password sign-up. Apple diverging from Google here is how one
	// of them ends up minting accounts with no recorded consent.
	async function startOAuthSignIn(provider: 'google' | 'apple') {
		error = '';
		// Mobile's `sign_up_screen._signInWithGoogle` / `_signInWithApple`
		// mirror this via `_checkGates()`. Sign-in to an existing account
		// skips the gates — `checkSignUpGates` returns ok when `isSignUp`
		// is false.
		const gate = checkSignUpGates(isSignUp, confirmAdult, acceptTerms);
		if (!gate.ok) {
			error = gateMessage(gate.reason);
			return;
		}
		// Stash the consent timestamps so /auth/callback can stamp
		// them server-side after the OAuth redirect — OAuth's first-
		// sign-in flow can't pass options.data into raw_user_meta_data,
		// so the post-callback RPC is the canonical capture point.
		// See migration 20260929_001 + audit/gdpr (2026-05-25) Critical.
		if (isSignUp) {
			const stamp = new Date().toISOString();
			try {
				sessionStorage.setItem('age_confirmed_at', stamp);
				sessionStorage.setItem('terms_accepted_at', stamp);
			} catch (_) {
				/* Safari private-mode disables sessionStorage — the
				   /auth/callback fallback redirects to /auth/confirm-age
				   when the stash is missing. */
			}
		}
		loading = true;
		try {
			await (provider === 'google' ? auth.signInWithGoogle() : auth.signInWithApple());
		} catch (err) {
			// Classified into a localized, user-facing message — the raw
			// supabase err.message is unlocalized developer jargon. Same
			// mapping as mobile's friendlyAuthError (auth_error.dart).
			error = m(authErrorMessageKey(classifyAuthError(err)), { min: PASSWORD_MIN_LENGTH });
			loading = false;
		}
	}

	// The provider isn't wired on the Supabase side yet, so a real click would
	// only surface an opaque provider error. Flipping the flag the day the
	// provider is configured reverts the button to startOAuthSignIn.
	function showProviderSoon(key: 'login.googleSoon' | 'login.appleSoon') {
		error = m(key);
	}

	// Both callers — a fresh sign-up and the emailExists collapse —
	// must land here identically, or sign-up becomes an
	// account-existence oracle again.
	function showConfirmationPending(address: string) {
		info = m('login.checkEmail', { email: address });
		isSignUp = false;
		password = '';
		confirmPassword = '';
		// Consent is affirmed per sign-up attempt, never carried across
		// one: a later sign-up for another address must tick both again.
		confirmAdult = false;
		acceptTerms = false;
		// ?signup=1 seeds the initial mode only, but leaving it on the
		// URL means a refresh restores the form we just dismissed.
		const url = new URL($page.url);
		if (url.searchParams.has('signup')) {
			url.searchParams.delete('signup');
			replaceState(`${url.pathname}${url.search}`, {});
		}
	}

	async function handleEmailSubmit(e: Event) {
		e.preventDefault();
		error = '';
		info = '';
		resendFor = null;
		if (isSignUp && !isReset) {
			const gate = checkSignUpGates(isSignUp, confirmAdult, acceptTerms);
			if (!gate.ok) {
				error = gateMessage(gate.reason);
				return;
			}
			// Before signUp, not after: a mistyped password that
			// reaches GoTrue is hashed and stored, the confirmation
			// mail goes out, and the account is then unreachable by
			// its owner with no error anywhere to show for it.
			const pair = checkPasswordPair(password, confirmPassword);
			if (!pair.ok) {
				error = passwordMessage(pair.reason);
				return;
			}
		}
		loading = true;
		try {
			if (isReset) {
				// Supabase tacks the recovery token on the hash; the wording
				// is intentionally non-committal so this isn't a user-
				// enumeration oracle.
				const redirectTo = `${window.location.origin}/auth/reset`;
				const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
					redirectTo
				});
				if (resetError) throw resetError;
				info = m('login.resetEmailSent');
				email = '';
			} else if (isSignUp) {
				const stamp = new Date().toISOString();
				const { data, error: signUpError } = await supabase.auth.signUp({
					email,
					password,
					options: {
						// Land the confirmation link on /auth/callback (the
						// PKCE-exchange + consent-stamp-retry + Art 8 gate
						// handler), not the app root. Without this GoTrue
						// falls back to the project Site URL. Must be on the
						// dashboard Redirect-URLs allow-list. See
						// web_app_auth.md § Email confirmation redirect.
						emailRedirectTo: `${window.location.origin}/auth/callback`,
						// raw_user_meta_data carries the consent
						// timestamps at the auth layer; the server-side
						// stamp on user_profiles happens via the RPC
						// below. See migration 20260929_001 + audit/gdpr.
						data: { age_confirmed_at: stamp, terms_accepted_at: stamp },
					},
				});
				if (signUpError) throw signUpError;
				if (!data.session) {
					// Success WITHOUT a session: email confirmation is
					// pending — or the address is already registered and
					// GoTrue returned its obfuscated duplicate response
					// (deliberately the same shape, so sign-up can't be
					// used to enumerate accounts). Either way there is no
					// session to navigate with; show the check-your-email
					// state instead of a silent non-event.
					showConfirmationPending(email);
					return;
				}
				// Server-side consent stamp on user_profiles. Also seeds
				// the region unit default from the browser locale on this
				// brand-new-row insert (the server has no locale);
				// returning users are never overwritten (#488).
				try {
					await supabase.rpc('confirm_age_and_terms', {
						p_preferred_unit: defaultUnitForLocale(navigator.language),
					});
				} catch (_) {
					/* Verified below — a failed stamp routes to the gate. */
				}
				await auth.refreshSession();
				// A session was issued straight away, so there is no
				// /auth/callback hop to retry the stamp on: a silently
				// failed RPC would otherwise leave a live session with no
				// recorded consent. Fail closed to the Art 8 gate instead.
				const consent = await verifyConsentStamped(() =>
					supabase.rpc('get_my_profile').maybeSingle(),
				);
				goto(consent === 'ok' ? safeReturnTo() : '/auth/confirm-age');
			} else {
				const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
				if (signInError) throw signInError;
				await auth.refreshSession();
				goto(safeReturnTo());
			}
		} catch (err) {
			// Classified into a localized, user-facing message — raw
			// supabase err.message is unlocalized and over-general. Same
			// mapping as mobile's friendlyAuthError (auth_error.dart).
			const kind = classifyAuthError(err);
			// Sign-up must never disclose that an email is already
			// registered: collapse an emailExists outcome to the same
			// neutral check-your-email state a fresh sign-up shows, so
			// sign-up can't be an account-existence oracle even when prod
			// GoTrue has email confirmations off. Login is untouched (an
			// existing email there classifies as invalidCredentials).
			if (isSignUp && !isReset && signUpErrorRevealsAccountExistence(kind)) {
				showConfirmationPending(email);
				return;
			}
			error = m(authErrorMessageKey(kind), { min: PASSWORD_MIN_LENGTH });
			if (kind === 'emailNotConfirmed' && email) resendFor = email;
		} finally {
			loading = false;
		}
	}

	async function handleResendConfirmation() {
		if (!resendFor) return;
		error = '';
		loading = true;
		try {
			const { error: resendError } = await supabase.auth.resend({
				type: 'signup',
				email: resendFor,
				options: { emailRedirectTo: `${window.location.origin}/auth/callback` }
			});
			if (resendError) throw resendError;
			// Privacy-preserving copy — must not confirm account existence.
			info = m('login.confirmationResent');
			resendFor = null;
		} catch (err) {
			error = m(authErrorMessageKey(classifyAuthError(err)), { min: PASSWORD_MIN_LENGTH });
		} finally {
			loading = false;
		}
	}

	let kicker = $derived(
		isReset ? m('login.kicker.reset') : isSignUp ? m('login.kicker.signup') : m('login.kicker.signin')
	);
	let headline = $derived(
		isReset
			? m('login.headline.reset')
			: isSignUp
				? m('login.headline.signup')
				: m('login.headline.signin')
	);
	let subtitle = $derived(
		isReset
			? m('login.subtitle.reset')
			: isSignUp
				? m('login.subtitle.signup')
				: m('login.subtitle.signin')
	);
</script>

<AuthShell>
	{#snippet panel()}
		<!-- The landing page's eyebrow, not the card's own kicker: both halves
		     are on screen together above 56rem, and repeating the card's words
		     put "Welcome back" on the screen twice. -->
		<p class="brand-kicker">{m('landing.heroEyebrow')}</p>
		<h2 class="brand-headline">{m('login.brandHeadline')}</h2>
		<ul class="brand-bullets">
			{#each [m('login.bullet1'), m('login.bullet2'), m('login.bullet3')] as bullet, i (i)}
				<li style="--enter-at: {380 + i * 110}ms">
					<span class="bullet-mark" aria-hidden="true"><span class="material-symbols">check</span></span>
					<span>{bullet}</span>
				</li>
			{/each}
		</ul>
		<p class="brand-foot">{m('login.brandFoot')}</p>
	{/snippet}

	<main class="auth-card login-card" id="main-content">
		<p class="kicker">{kicker}</p>
		<h1>{headline}</h1>
		<p class="subtitle">{subtitle}</p>

		{#if error}
			<div class="error" role="alert">
				{error}
				{#if resendFor}
					<button
						type="button"
						class="link-btn resend-btn"
						onclick={handleResendConfirmation}
						disabled={loading}
					>
						{m('login.resendConfirmation')}
					</button>
				{/if}
			</div>
		{/if}
		<!-- Permanently mounted: a live region announces changes made INSIDE
		     it, not its own arrival, so a region that appears together with
		     its first message announces nothing (decisions.md § 736). -->
		<div role="status" aria-live="polite">
			{#if info}
				<div class="info">{info}</div>
			{/if}
		</div>

		{#if !isReset}
			<div class="login-buttons">
				<button
					class="btn btn-google"
					onclick={googleEnabled
						? () => startOAuthSignIn('google')
						: () => showProviderSoon('login.googleSoon')}
					disabled={loading}
				>
					<svg class="oauth-icon" viewBox="0 0 24 24" width="20" height="20">
						<path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/>
						<path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
						<path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
						<path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
					</svg>
					{m('login.continueGoogle')}
					{#if !googleEnabled}
						<span class="soon-pill">{m('login.soon')}</span>
					{/if}
				</button>

				<button
					class="btn btn-apple"
					onclick={appleEnabled
						? () => startOAuthSignIn('apple')
						: () => showProviderSoon('login.appleSoon')}
					disabled={loading}
				>
					<svg class="oauth-icon" viewBox="0 0 24 24" width="20" height="20" fill="white">
						<path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
					</svg>
					{m('login.continueApple')}
					{#if !appleEnabled}
						<span class="soon-pill">{m('login.soon')}</span>
					{/if}
				</button>
			</div>

			<div class="divider">
				<span>{m('login.orEmail')}</span>
			</div>
		{/if}

		<form class="email-form" onsubmit={handleEmailSubmit}>
			<!--
				audit/accessibility High (May 2026): inputs used
				placeholder-only — disappears as the user types and
				screen readers announce just "edit text" without a
				persistent name. Add a visually-hidden <label> via
				.visually-hidden (defined in app.css). aria-label
				alone is also valid per WCAG 3.3.2 but explicit
				<label for> is the most compatible form.
			-->
			<label for="login-email" class="visually-hidden">{m('login.emailPlaceholder')}</label>
			<input
				id="login-email"
				type="email"
				bind:value={email}
				placeholder={m('login.emailPlaceholder')}
				required
				autocomplete="email"
			/>
			{#if !isReset}
				<label for="login-password" class="visually-hidden">{m('login.passwordPlaceholder')}</label>
				<PasswordInput
					id="login-password"
					bind:value={password}
					placeholder={m('login.passwordPlaceholder')}
					required
					minlength={isSignUp ? PASSWORD_MIN_LENGTH : undefined}
					autocomplete={isSignUp ? 'new-password' : 'current-password'}
					toggleDisabled={!hydrated}
				/>
				{#if isSignUp}
					<label for="login-confirm-password" class="visually-hidden">
						{m('login.confirmPasswordPlaceholder')}
					</label>
					<PasswordInput
						id="login-confirm-password"
						bind:value={confirmPassword}
						placeholder={m('login.confirmPasswordPlaceholder')}
						required
						minlength={PASSWORD_MIN_LENGTH}
						autocomplete="new-password"
						toggleDisabled={!hydrated}
					/>
				{/if}
			{/if}
			{#if isSignUp}
				<label class="signup-check">
					<input type="checkbox" bind:checked={confirmAdult} required />
					<span>{m('login.confirmAdult')}</span>
				</label>
				<label class="signup-check">
					<input type="checkbox" bind:checked={acceptTerms} required />
					<span>
						{m('login.agreePrefix')}
						<a href="/terms" target="_blank" rel="noopener noreferrer">{m('legal.termsOfService')}</a>
						{m('login.agreeBetween')}
						<a href="/privacy" target="_blank" rel="noopener noreferrer">{m('legal.privacyPolicy')}</a>{m('login.agreeSuffix')}
					</span>
				</label>
			{/if}
			<button
				type="submit"
				class="btn btn-email"
				disabled={!hydrated || loading || (isSignUp && (!confirmAdult || !acceptTerms))}
			>
				{#if loading}
					{#if isReset}{m('login.sending')}{:else}{isSignUp ? m('login.signingUp') : m('login.signingIn')}{/if}
				{:else if isReset}
					{m('login.sendResetLink')}
				{:else}
					{isSignUp ? m('login.signUp') : m('login.signIn')}
				{/if}
			</button>
		</form>

		{#if isReset}
			<p class="toggle-mode">
				<button type="button" class="link-btn" onclick={() => { isReset = false; error = ''; info = ''; }}>
					{m('login.backToSignIn')}
				</button>
			</p>
		{:else}
			<p class="toggle-mode">
				{isSignUp ? m('login.haveAccount') : m('login.noAccount')}
				<button type="button" class="link-btn" onclick={() => { isSignUp = !isSignUp; error = ''; info = ''; }}>
					{isSignUp ? m('login.toggleToSignIn') : m('login.toggleToSignUp')}
				</button>
			</p>
			{#if !isSignUp}
				<p class="toggle-mode">
					<button type="button" class="link-btn" onclick={() => { isReset = true; error = ''; password = ''; confirmPassword = ''; }}>
						{m('login.kicker.reset')}
					</button>
				</p>
			{/if}
		{/if}

		{#if !isSignUp}
			<p class="terms">
				{m('login.termsPrefix')}
				<a href="/terms" target="_blank" rel="noopener noreferrer">{m('legal.termsOfService')}</a>
				{m('login.termsBetween')}
				<a href="/privacy" target="_blank" rel="noopener noreferrer">{m('legal.privacyPolicy')}</a>{m('login.termsSuffix')}
			</p>
		{/if}
	</main>

	{#if !isReset}
		<p class="form-pane-foot">
			{m('login.formFoot')}
		</p>
	{/if}
</AuthShell>

<style>
	/* Layout, the brand panel and the card chrome belong to AuthShell. What
	   stays here is the copy the panel carries and the form's own controls. */

	/* --- panel copy (white on the shell's measured plum ramp) ------------ */

	.brand-kicker {
		text-transform: uppercase;
		letter-spacing: 0.14em;
		font-size: 0.78rem;
		font-weight: 700;
		color: #FFD6C8;
		margin: 0 0 var(--space-md);
	}

	.brand-headline {
		font-size: clamp(2.1rem, 3.2vw, 3rem);
		line-height: 1.08;
		font-weight: 800;
		margin: 0 0 var(--space-xl);
		letter-spacing: -0.03em;
		text-wrap: balance;
		text-shadow: 0 0.5rem 2rem rgba(20, 10, 24, 0.5);
	}

	.brand-bullets {
		list-style: none;
		padding: 0;
		margin: 0 0 var(--space-xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.brand-bullets li {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		font-size: 1rem;
		line-height: 1.5;
	}

	.bullet-mark {
		flex-shrink: 0;
		display: grid;
		place-items: center;
		width: 1.6rem;
		height: 1.6rem;
		margin-top: -0.05rem;
		border-radius: var(--radius-pill);
		background: rgba(255, 255, 255, 0.12);
		border: 1px solid rgba(255, 255, 255, 0.28);
		color: #FFD6C8;
	}

	.bullet-mark .material-symbols {
		font-size: 1.05rem;
	}

	.brand-foot {
		font-size: 0.88rem;
		/* 0.85 white, measured like the hero subhead at every stop and veil. */
		color: rgba(255, 255, 255, 0.85);
		max-width: 30rem;
		line-height: 1.55;
		margin: 0;
	}

	/* Entrances only for visitors who accept motion: a `from` keyframe that
	   hides content still paints for one frame under the global reduced-motion
	   rule, before the timeline ticks. */
	@media (prefers-reduced-motion: no-preference) {
		.brand-kicker {
			animation: copy-rise 800ms cubic-bezier(0.22, 1, 0.36, 1) 150ms backwards;
		}
		.brand-headline {
			animation: copy-rise 900ms cubic-bezier(0.22, 1, 0.36, 1) 240ms backwards;
		}
		.brand-bullets li {
			animation: copy-rise 800ms cubic-bezier(0.22, 1, 0.36, 1) var(--enter-at, 0ms) backwards;
		}
		.brand-foot {
			animation: copy-rise 800ms cubic-bezier(0.22, 1, 0.36, 1) 760ms backwards;
		}
		.error {
			animation: nudge 360ms ease-out;
		}
	}

	@keyframes copy-rise {
		from {
			opacity: 0;
			transform: translateY(0.9rem);
		}
	}

	/* --- card ------------------------------------------------------------ */

	.login-card {
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
		font-size: 1.85rem;
		font-weight: 800;
		margin: 0 0 var(--space-xs);
		letter-spacing: -0.025em;
		line-height: 1.15;
		color: var(--color-text);
		text-wrap: balance;
	}

	.subtitle {
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-xl);
		line-height: 1.5;
	}

	.error {
		background: var(--color-danger-light);
		border: 1px solid color-mix(in srgb, var(--color-danger) 30%, transparent);
		color: var(--color-danger-text);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-lg);
		font-size: 0.85rem;
		margin-bottom: var(--space-md);
		text-align: start;
	}

	/* One small shake as an error lands, so the eye goes to it. Ends. */
	@keyframes nudge {
		20% { transform: translateX(calc(-4px * var(--dir-sign))); }
		45% { transform: translateX(calc(4px * var(--dir-sign))); }
		70% { transform: translateX(calc(-2px * var(--dir-sign))); }
	}

	.info {
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		color: var(--color-text);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-lg);
		font-size: 0.85rem;
		margin-bottom: var(--space-md);
		text-align: start;
	}

	.login-buttons {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.btn-google,
	.btn-apple,
	.btn-email {
		width: 100%;
		min-height: 3rem;
		padding: 0.8rem var(--space-lg);
		border-radius: var(--radius-lg);
		font-size: 0.95rem;
		transition:
			transform var(--transition-base),
			box-shadow var(--transition-base),
			border-color var(--transition-base),
			background var(--transition-base);
	}

	.btn-google:hover:not(:disabled),
	.btn-apple:hover:not(:disabled),
	.btn-email:hover:not(:disabled) {
		transform: translateY(-1px);
	}

	.btn-google {
		position: relative;
		background: var(--color-surface);
		border: 1.5px solid var(--color-border);
		color: var(--color-text);
	}

	.btn-google:hover:not(:disabled) {
		border-color: var(--color-text-secondary);
		box-shadow: var(--shadow-md);
	}

	.btn-apple {
		background: #000;
		border: 1.5px solid #000;
		color: white;
		position: relative;
	}

	.btn-apple:hover:not(:disabled) {
		background: #1a1a1a;
		box-shadow: var(--shadow-md);
	}

	/* A badge on the button's top corner, not a pill in its text line. In the
	   line it shared the width with the label, so whether "Continue with
	   Apple" fitted on a phone depended on the device's fallback font: Noto
	   Sans fitted, DejaVu Sans wrapped (CI run 35134263272). Out of the line,
	   the label has the whole button.
	   The primary pair rather than a translucent white, which read on the
	   black Apple button and vanished on the white Google one. It stays in
	   the button's text, so the accessible name still says "Soon". */
	.soon-pill {
		position: absolute;
		top: 0;
		inset-inline-end: var(--space-md);
		translate: 0 -50%;
		font-size: var(--font-size-section-label);
		font-weight: 700;
		line-height: 1.3;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		padding: 0.1rem 0.5rem;
		border-radius: 9999px;
		background: var(--color-primary);
		color: var(--color-on-primary);
		box-shadow: 0 0 0 2px var(--color-surface);
		pointer-events: none;
	}

	:global(html[data-theme='dark']) .btn-apple {
		border-color: #334155;
	}

	.oauth-icon {
		flex-shrink: 0;
	}

	.divider {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin: var(--space-lg) 0;
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
	}

	.divider::before,
	.divider::after {
		content: '';
		flex: 1;
		border-top: 1px solid var(--color-border);
	}

	.email-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		text-align: start;
	}

	input[type='email'] {
		width: 100%;
		padding: 0.7rem var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.95rem;
		font-family: inherit;
		background: var(--color-surface);
		color: var(--color-text);
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}

	input[type='email']:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-primary) 18%, transparent);
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	input[type='email']:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	/* --gradient-primary passes through a pale stop in BOTH themes (#F2A07B
	   light, #B9A7E8 dark), so no single ink clears it: white read 2.081:1
	   light and 2.153:1 dark. A gradient is a fill and its palest stop sets
	   the ink, so the primary-action button takes the solid pair § 506 minted
	   for exactly this — 9.120:1 — the same fix § 511 applied to
	   .btn-primary. */
	.btn-email {
		background: var(--color-primary);
		color: var(--color-on-primary);
		border: none;
		font-weight: 600;
		margin-top: var(--space-xs);
		box-shadow: 0 0.6rem 1.4rem -0.6rem color-mix(in srgb, var(--color-primary) 60%, transparent);
	}

	.btn-email:hover:not(:disabled) {
		filter: brightness(1.05);
		box-shadow: 0 0.9rem 1.8rem -0.6rem color-mix(in srgb, var(--color-primary) 70%, transparent);
	}

	.toggle-mode {
		margin-top: var(--space-md);
		font-size: 0.88rem;
		color: var(--color-text-secondary);
	}

	.link-btn {
		background: none;
		border: none;
		color: var(--color-primary);
		font-weight: 600;
		cursor: pointer;
		font-size: inherit;
		padding: 0;
	}

	.link-btn:hover {
		text-decoration: underline;
	}

	.resend-btn {
		display: block;
		margin-top: var(--space-xs);
	}

	.terms {
		margin-top: var(--space-lg);
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
	}
	.terms a,
	.signup-check a {
		color: inherit;
		text-decoration: underline;
	}
	.signup-check {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.4;
		text-align: start;
		margin-top: var(--space-2xs);
	}
	.signup-check input[type='checkbox'] {
		margin-top: 0.2rem;
		flex-shrink: 0;
	}

	.form-pane-foot {
		max-width: 26rem;
		text-align: center;
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
		margin: 0;
	}
	@media (min-width: 56rem) {
		.form-pane-foot {
			display: none;
		}
	}
</style>
