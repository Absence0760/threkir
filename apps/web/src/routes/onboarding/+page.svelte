<script lang="ts">
	import { TEXT_LIMITS } from '$lib/core/text_limits';
	import { onMount, tick } from 'svelte';
	import AuthShell from '$lib/components/auth/AuthShell.svelte';
	import { browser } from '$app/environment';
	import { m } from '$lib/i18n/store.svelte';
	import { defaultUnitForLocale } from '$lib/format/locale_defaults';
	import {
		parseWeightToKg,
		roundWeight,
		isBodyWeightInRangeKg,
		weightBoundsIn,
		type WeightUnit,
	} from '$lib/format/weight';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { showToast } from '$lib/stores/toast.svelte';
	import { updateUniversal } from '$lib/settings/settings';
	import type { PrefsBag } from '$lib/settings/settings';
	import type { Updatable } from '$lib/core/database';
	import {
		isPushSupported,
		pushPermission,
		subscribeToPush,
		getCurrentSubscription,
	} from '$lib/util/push';
	import {
		ONBOARDING_STEPS,
		PRIMARY_GOAL_KEY,
		PRIMARY_GOAL_VALUES,
		visibleOnboardingSteps,
		type OnboardingStep,
		type PrimaryGoal,
	} from '$lib/settings/onboarding';

	/// Step state, a 1-based index into `steps`. Persona-hunt
	/// new-runner finding-area #1: a Garmin-style step-by-step is
	/// lower cognitive load than a single long form, especially for
	/// the new-runner persona who's overwhelmed by choice.
	let step = $state(1);

	// The steps this visitor walks. Settled in onMount, before the wizard
	// renders: the notifications step only appears when push can actually be
	// turned on in this browser (visibleOnboardingSteps).
	let steps = $state<OnboardingStep[]>([...ONBOARDING_STEPS]);
	const total = $derived(steps.length);
	const current = $derived<OnboardingStep>(steps[step - 1]);

	// ── Step 1: display name ──────────────────────────────────
	let displayName = $state('');

	// ── Step 2: units ─────────────────────────────────────────
	// Seed from the visitor's locale (mi for US/GB/LR/MM, km otherwise)
	// instead of hard-coding km — the user can still flip it on this step.
	// audit-findings 2026-05-30 Medium [regional].
	let preferredUnit = $state<'km' | 'mi'>(
		browser ? defaultUnitForLocale(navigator.language) : 'km',
	);

	// ── Step 3: primary goal ──────────────────────────────────
	let primaryGoal = $state<PrimaryGoal | null>(null);

	// ── Step 4: about you (gender + DOB + weight + Art 9 consent) ──
	// Identical shape to /settings/preferences so the same fields
	// land in the same columns. Consent gates the health-data *use* —
	// gender, the prefs-bag mirror, and the consent timestamp are only
	// written when the box is ticked. The bare `date_of_birth` column,
	// however, writes unconditionally: it backs the under-18
	// minor-exclusion in people-search (a child-safety purpose, distinct
	// from consenting to use DOB for HR/leaderboards), so a declined
	// consent must not leave a NULL DOB that keeps the account
	// discoverable. Weight isn't Art 9, so it persists regardless.
	let gender = $state<'male' | 'female' | ''>('');
	let dateOfBirth = $state('');
	// Body weight is entered in the unit implied by the distance choice in
	// step 2: a runner who picked miles (US/GB/LR/MM) thinks of their weight
	// in pounds, so asking for kg there both reads wrong beside an otherwise
	// imperial session and risks a lbs value being silently stored as kg —
	// which then inflates the TDEE / hydration math that consumes
	// body_weight_kg. Storage stays canonical kg; this only changes display +
	// parsing, exactly like preferred_unit for distance.
	let bodyWeight = $state('');
	const weightUnit = $derived<WeightUnit>(preferredUnit === 'mi' ? 'lbs' : 'kg');
	const weightBounds = $derived(weightBoundsIn('body_metrics.weight_kg', weightUnit));
	const weightMin = $derived(weightBounds.min);
	const weightMax = $derived(weightBounds.max);
	// The `min`/`max` input attributes above are cosmetic — the wizard
	// advances via onclick handlers, not a native form submit, so the
	// browser's constraint validation never runs (issue #677). This is the
	// real gate: parses the typed value the same way the Finish handler
	// does, then checks it against the plausible-human-body-weight range.
	const weightOutOfRange = $derived.by(() => {
		const kg = parseWeightToKg(String(bodyWeight ?? ''), weightUnit);
		return kg != null && !isBodyWeightInRangeKg(kg);
	});
	let healthDataConsent = $state(false);

	// ── Step 5: privacy default ───────────────────────────────
	// Defaults to `private` (privacy-by-default) so a new runner isn't
	// silently opted into a follower-visible feed, and so the value the
	// wizard writes to the bag matches the mobile onboarding default —
	// previously this 'followers' default propagated via SettingsSync and
	// overrode a mobile user's private choice. Persona-hunt new #56.
	let privacyDefault = $state<'public' | 'followers' | 'private'>('private');

	// ── Step 6: notifications (web shows it only when push can be turned on) ──
	const pushSupported = isPushSupported();
	let pushSubscribed = $state(false);
	let pushBusy = $state(false);

	let saving = $state(false);

	// Gates the wizard render until onMount has run (auth polled + fields
	// prefilled). The page is prerendered + hydrated, so without this the
	// interactive form paints before hydration attaches handlers — an early
	// click on Continue / Skip is silently dropped and the prefill clobbers
	// a value typed into the gap. Rendering the wizard only once `ready` is
	// true means it exists only client-side, post-hydration, fully wired.
	let ready = $state(false);

	onMount(async () => {
		// `auth.svelte.ts` flips loading=false before the async
		// fetchUser resolves, so a hard reload onto /onboarding can
		// mount with `auth.user` still null. Wait for the gate so the
		// pre-fill below sees the real row.
		await auth.ready();
		// Pre-fill display name from the auth row if the OAuth provider
		// returned one — the user can edit before continuing.
		if (auth.user?.display_name) displayName = auth.user.display_name;
		// Same for the unit prefiller — `auth.user.preferred_unit`
		// defaults to 'km' if never set.
		if (auth.user?.preferred_unit) preferredUnit = auth.user.preferred_unit;
		if (pushSupported) {
			pushSubscribed = !!(await getCurrentSubscription());
		}
		steps = visibleOnboardingSteps({
			supported: pushSupported,
			permission: pushPermission(),
			subscribed: pushSubscribed,
		});
		ready = true;
	});

	// Which way the last step change went, so the incoming step slides in
	// from the side the reader is moving toward.
	let direction = $state<1 | -1>(1);

	function next() {
		if (step < total) {
			direction = 1;
			step += 1;
		}
	}

	function back() {
		if (step > 1) {
			direction = -1;
			step -= 1;
		}
	}

	// A step change replaces the whole card body, so without this, focus
	// stays on a Continue button that now belongs to a different question
	// and a screen reader announces nothing. Moving it to the new step's
	// heading reads the question out. The first render is left alone.
	let card = $state<HTMLElement | null>(null);
	let shownStep = 1;
	$effect(() => {
		const current = step;
		if (!ready || current === shownStep) return;
		shownStep = current;
		tick().then(() => card?.querySelector<HTMLElement>('.step-frame h1')?.focus());
	});

	// The panel's step list. Short names, keyed by step.
	const RAIL_NAME = {
		name: 'onboarding.rail.name',
		units: 'onboarding.rail.units',
		goal: 'onboarding.rail.goal',
		about: 'onboarding.rail.about',
		privacy: 'onboarding.rail.privacy',
		notifications: 'onboarding.rail.notifications',
		done: 'onboarding.rail.done',
	} as const satisfies Record<OnboardingStep, string>;

	// One glyph per goal, all already in the icon subset.
	const GOAL_ICON: Record<PrimaryGoal, string> = {
		general_fitness: 'favorite',
		weight_loss: 'local_fire_department',
		'5k': 'directions_run',
		'10k': 'sprint',
		half_marathon: 'military_tech',
		marathon: 'emoji_events',
	};

	const PRIVACY_ICON = { private: 'lock', followers: 'group', public: 'public' } as const;

	function skipStep() {
		// Per-step skip — keeps the wizard moving without forcing the
		// user to commit. The unset field falls back to its default
		// at save time, and the Settings nudge surfaces it later.
		next();
	}

	async function handleEnablePush() {
		if (!pushSupported || pushBusy) return;
		pushBusy = true;
		try {
			await subscribeToPush();
			pushSubscribed = true;
		} catch (e) {
			showToast(m('onboarding.pushEnableError', { message: (e as Error).message }), 'error');
		} finally {
			pushBusy = false;
		}
	}

	/// Helper used by both the Skip-onboarding header link and the
	/// final Open-dashboard button. Resolves once `auth.user` has
	/// hydrated from the async `fetchUser` path so the caller can
	/// rely on `auth.user.id`. Returns false when the hydration
	/// never lands — caller bails out.
	async function ensureAuthUser(): Promise<boolean> {
		await auth.ready();
		return auth.user != null;
	}

	/// Row-count-verified profile write with an insert fallback (ADR 248).
	/// `user_profiles` rows are client-provisioned, so a plain update
	/// against a user whose row hasn't materialised yet (OAuth / email-
	/// confirmation timing) matches 0 rows and reports success — the
	/// wizard then navigated to /dashboard, the gate re-read a still-null
	/// `onboarded_at`, and bounced the user back to step 1 with every
	/// answer lost (issue #227). Throws so both callers surface the toast.
	async function stampProfile(profileUpdate: Updatable<'user_profiles'>): Promise<void> {
		const { data: updatedRows, error } = await supabase
			.from('user_profiles')
			.update(profileUpdate)
			.eq('id', auth.user!.id)
			.select('id');
		if (error) throw error;
		if (!updatedRows?.length) {
			const { error: insertError } = await supabase
				.from('user_profiles')
				.insert({ id: auth.user!.id, ...profileUpdate });
			if (insertError) throw insertError;
		}
	}

	/// Full page navigation rather than client-side `goto` so the
	/// layout's onboarding-gate $effect can't race the auth-store
	/// refresh — the next page load re-bootstraps auth from the
	/// cookie + the just-written onboarded_at column, so the gate
	/// trivially sees a non-null value and routes through to
	/// /dashboard.
	function navigateToDashboard(): void {
		window.location.href = '/dashboard';
	}

	/// Skip-onboarding header link. Stamps `onboarded_at = now()`
	/// on user_profiles — that's the minimum required for the
	/// layout gate to stop redirecting back here on future loads.
	/// Every other field stays at its existing value (the seed
	/// row's default, or whatever the runner already had); the
	/// Settings page surfaces a "Finish setting up" nudge for fields
	/// they may still want to fill in.
	///
	/// Why a single, narrow write: `event-race-control` style
	/// flakes aside, the previous shape (parallelised
	/// updateUniversal + profile update) was still consistently
	/// timing out under CI load (runs 26583136874 / 26584629824 /
	/// 26588671185 all failed here despite progressive timeout
	/// bumps). A single round-trip lands well inside any reasonable
	/// test budget.
	async function skipOnboarding(): Promise<void> {
		if (saving) return;
		if (!(await ensureAuthUser())) {
			// Never bail silently — a button that does nothing reads as a
			// broken exit and strands the user on the wizard (issue #227).
			showToast(m('onboarding.saveError', { message: m('onboarding.notSignedIn') }), 'error');
			return;
		}
		saving = true;
		try {
			await stampProfile({ onboarded_at: new Date().toISOString() });
			navigateToDashboard();
		} catch (e) {
			showToast(m('onboarding.saveError', { message: (e as Error).message }), 'error');
			saving = false;
		}
		// On success the navigation tears down the page; no need to
		// reset `saving = false` because the next page is a fresh
		// component instance.
	}

	/// Final "Open dashboard" button on the done step. Persists everything
	/// the runner answered along the way: display name, units, goal,
	/// optional demographics (with GDPR Art 9 consent), privacy
	/// default. Stamps `onboarded_at` so the gate releases.
	async function finishAndExit(dest: string = '/dashboard'): Promise<void> {
		if (saving) return;
		if (!(await ensureAuthUser())) {
			// Same no-silent-bail contract as skipOnboarding (issue #227).
			showToast(m('onboarding.saveError', { message: m('onboarding.notSignedIn') }), 'error');
			return;
		}
		saving = true;
		try {
			// 1. Universal prefs bag (units + goal + weight + privacy).
			const bagChanges: PrefsBag = {
				preferred_unit: preferredUnit,
				weight_unit: weightUnit,
				privacy_default: privacyDefault,
			};
			if (primaryGoal) bagChanges[PRIMARY_GOAL_KEY] = primaryGoal;
			// The typed value is in the display unit (kg or lbs); store canonical
			// kg. parseWeightToKg rejects empty / non-numeric / negative input.
			// `bind:value` on a type=number input coerces bodyWeight to a
			// number (or null when empty); parseWeightToKg takes the raw typed
			// string (it trims + tolerates a comma decimal), so stringify first.
			const weightKg = parseWeightToKg(String(bodyWeight ?? ''), weightUnit);
			// isBodyWeightInRangeKg is the same gate the Continue button's
			// disabled state checks — kept here too so an out-of-bounds value
			// can never reach the TDEE/hydration math even via a path that
			// bypasses the about step (e.g. the done step's CTA reached after Skip).
			if (weightKg != null && weightKg > 0 && isBodyWeightInRangeKg(weightKg)) {
				bagChanges.body_weight_kg = roundWeight(weightKg);
			}
			// DOB mirrors into the prefs bag only under health consent —
			// the bag copy feeds the coach/leaderboard read paths, which
			// are Art 9 surfaces. The minor-exclusion floor reads the
			// user_profiles column written below, not the bag, so the
			// child-safety write doesn't depend on this mirror.
			if (healthDataConsent && dateOfBirth) {
				bagChanges.date_of_birth = dateOfBirth;
			}
			// 2. user_profiles columns: display_name, preferred_unit
			// (dual-write for the cross-user readable surfaces),
			// gender + DOB + health_data_consent_at, onboarded_at.
			const profileUpdate: Updatable<'user_profiles'> = {
				preferred_unit: preferredUnit,
				onboarded_at: new Date().toISOString(),
			};
			if (displayName.trim()) profileUpdate.display_name = displayName.trim();
			// DOB writes to user_profiles whenever supplied, NOT only under
			// Art 9 consent (persona round-5 family-club): the under-18
			// minor-exclusion floor in search_user_profiles keys off this
			// column, so consent-gating it left a child who declined the
			// health-data checkbox with a NULL DOB and fully discoverable.
			// Storing a date of birth to enforce a minor-safety
			// discoverability floor is a child-protection purpose distinct
			// from the Art 9(2)(a) explicit consent needed to USE that DOB
			// for health calibration + age-banded leaderboards — which
			// stays gated below via gender + health_data_consent_at.
			if (dateOfBirth) profileUpdate.date_of_birth = dateOfBirth;
			if (healthDataConsent) {
				profileUpdate.gender = gender || null;
				// health_data_consent_at is stamped server-side by the RPC
				// below (migration 20261118_001) — a direct write of it is
				// rejected by the lock trigger, so it's NOT in profileUpdate.
			}

			// Stamp Art 9 consent server-side first (first-stamp-wins), then
			// the bag + profile writes. The RPC is the only path that can
			// set health_data_consent_at to a non-null value.
			if (healthDataConsent) {
				const { error: consentErr } = await supabase.rpc('grant_health_data_consent');
				if (consentErr) throw consentErr;
			}

			// Issue both writes in parallel — the bag write doesn't
			// depend on the profile write and vice versa. stampProfile
			// throws on error AND on a 0-row update (issue #227), so a
			// stamp that never landed can't navigate.
			await Promise.all([
				updateUniversal(auth.user!.id, bagChanges),
				stampProfile(profileUpdate),
			]);

			showToast(m('onboarding.welcomeToast'), 'success');
			// Full page navigation (same rationale as navigateToDashboard) so the
			// layout onboarding-gate re-bootstraps from the freshly-written
			// onboarded_at. `dest` is /dashboard by default, or the goal-keyed
			// /plans/new deep-link from the "create my training plan" CTA.
			window.location.href = dest;
		} catch (e) {
			showToast(m('onboarding.saveError', { message: (e as Error).message }), 'error');
			saving = false;
		}
		// On success the navigation tears down the page; no need to
		// reset `saving = false`.
	}
</script>

<svelte:head>
	<title>{m('onboarding.pageTitle')}</title>
</svelte:head>

<AuthShell wide>
	{#snippet panel()}
		<p class="panel-kicker">{m('onboarding.stepCount', { index: step, total })}</p>
		<h2 class="panel-title">{m('onboarding.panelTitle')}</h2>
		<p class="panel-sub">{m('onboarding.panelSub')}</p>
		<!-- A picture of the progressbar in the card, which is what assistive
		     technology reads; this copy is for the eye. -->
		<ol class="rail" aria-hidden="true">
			{#each steps as id, i (id)}
				<li class:rail-done={i + 1 < step} class:rail-now={i + 1 === step}>
					<span class="rail-mark">
						{#if i + 1 < step}<span class="material-symbols">check</span>{:else}{i + 1}{/if}
					</span>
					<span class="rail-name">{m(RAIL_NAME[id])}</span>
				</li>
			{/each}
		</ol>
	{/snippet}

	<main class="auth-card onboarding-card" id="main-content" bind:this={card}>
		<div class="card-top">
			<div
				class="progress-track"
				role="progressbar"
				aria-label={m('onboarding.stepCount', { index: step, total })}
				aria-valuemin="1"
				aria-valuemax={total}
				aria-valuenow={step}
			>
				<span class="progress-fill" style="--progress: {step / total}"></span>
			</div>
			<button type="button" class="skip-all" onclick={skipOnboarding} disabled={saving}>
				{m('onboarding.skipOnboarding')}
			</button>
		</div>
		<p class="step-count" aria-hidden="true">
			{m('onboarding.stepCount', { index: step, total })}
		</p>

		{#key step}
		<div class="step-frame" style="--from: {direction}">
		{#if !ready}
			<p class="loading-hint">{m('shell.loading')}</p>
		{:else if current === 'name'}
			<section aria-labelledby="step-name-title">
				<span class="step-icon" aria-hidden="true"><span class="material-symbols">badge</span></span>
				<h1 id="step-name-title" tabindex="-1">{m('onboarding.step1Title')}</h1>
				<p class="hint">{m('onboarding.step1Hint')}</p>
				<label class="field">
					<span class="label-text">{m('onboarding.displayNameLabel')}</span>
					<input
						type="text"
						bind:value={displayName}
						maxlength={TEXT_LIMITS.displayName}
						placeholder={m('onboarding.displayNamePlaceholder')}
					/>
				</label>
			</section>
		{:else if current === 'units'}
			<section aria-labelledby="step-units-title">
				<span class="step-icon" aria-hidden="true"><span class="material-symbols">straighten</span></span>
				<h1 id="step-units-title" tabindex="-1">{m('onboarding.step2Title')}</h1>
				<p class="hint">{m('onboarding.step2Hint')}</p>
				<div class="unit-tiles" role="radiogroup" aria-labelledby="step-units-title">
					<button
						type="button"
						class="choice unit-tile"
						class:selected={preferredUnit === 'km'}
						role="radio"
						aria-checked={preferredUnit === 'km'}
						onclick={() => (preferredUnit = 'km')}
					>
						<span class="unit-abbr" aria-hidden="true">km</span>
						<span class="choice-text">
							<span class="choice-name">{m('onboarding.unitKm')}</span>
							<span class="choice-desc unit-sample">{m('onboarding.unitKmSample')}</span>
						</span>
						<span class="choice-mark" aria-hidden="true"></span>
					</button>
					<button
						type="button"
						class="choice unit-tile"
						class:selected={preferredUnit === 'mi'}
						role="radio"
						aria-checked={preferredUnit === 'mi'}
						onclick={() => (preferredUnit = 'mi')}
					>
						<span class="unit-abbr" aria-hidden="true">mi</span>
						<span class="choice-text">
							<span class="choice-name">{m('onboarding.unitMi')}</span>
							<span class="choice-desc unit-sample">{m('onboarding.unitMiSample')}</span>
						</span>
						<span class="choice-mark" aria-hidden="true"></span>
					</button>
				</div>
			</section>
		{:else if current === 'goal'}
			<section aria-labelledby="step-goal-title">
				<span class="step-icon" aria-hidden="true"><span class="material-symbols">flag</span></span>
				<h1 id="step-goal-title" tabindex="-1">{m('onboarding.step3Title')}</h1>
				<p class="hint">{m('onboarding.step3Hint')}</p>
				<div class="goal-grid" role="radiogroup" aria-labelledby="step-goal-title">
					{#each PRIMARY_GOAL_VALUES as v (v)}
						<button
							type="button"
							class="choice goal-tile"
							class:selected={primaryGoal === v}
							role="radio"
							aria-checked={primaryGoal === v}
							onclick={() => (primaryGoal = v)}
						>
							<span class="goal-glyph" aria-hidden="true"><span class="material-symbols">{GOAL_ICON[v]}</span></span>
							<span class="choice-name">{m(`onboarding.goal.${v}`)}</span>
							<span class="choice-mark" aria-hidden="true"></span>
						</button>
					{/each}
				</div>
			</section>
		{:else if current === 'about'}
			<section aria-labelledby="step-about-title">
				<span class="step-icon" aria-hidden="true"><span class="material-symbols">person</span></span>
				<h1 id="step-about-title" tabindex="-1">{m('onboarding.step4Title')}</h1>
				<p class="hint">{m('onboarding.step4Hint')}</p>
				<div class="field-row">
					<label class="field">
						<span class="label-text">{m('onboarding.genderLabel')}</span>
						<select bind:value={gender}>
							<option value="">{m('onboarding.genderPreferNot')}</option>
							<option value="female">{m('onboarding.genderFemale')}</option>
							<option value="male">{m('onboarding.genderMale')}</option>
						</select>
					</label>
					<label class="field">
						<span class="label-text">{m('onboarding.dobLabel')}</span>
						<input type="date" bind:value={dateOfBirth} max={new Date().toISOString().slice(0, 10)} />
					</label>
				</div>
				<p class="field-note">{m('onboarding.dobNote')}</p>
				<label class="field">
					<span class="label-text">{m('onboarding.weightLabel', { unit: weightUnit })}</span>
					<input
						type="number"
						inputmode="decimal"
						min={weightMin}
						max={weightMax}
						step="0.1"
						bind:value={bodyWeight}
						placeholder={m('onboarding.weightPlaceholder', { example: weightUnit === 'lbs' ? 155 : 70 })}
						aria-invalid={weightOutOfRange}
					/>
					{#if weightOutOfRange}
						<span class="field-error" role="alert">
							{m('limits.weightOutOfRange', { min: weightMin, max: weightMax, unit: weightUnit })}
						</span>
					{/if}
				</label>
				{#if gender || dateOfBirth}
					<label class="consent-row">
						<input type="checkbox" bind:checked={healthDataConsent} />
						<span>{m('onboarding.healthConsent')}</span>
					</label>
				{/if}
			</section>
		{:else if current === 'privacy'}
			<section aria-labelledby="step-privacy-title">
				<span class="step-icon" aria-hidden="true"><span class="material-symbols">verified_user</span></span>
				<h1 id="step-privacy-title" tabindex="-1">{m('onboarding.step5Title')}</h1>
				<p class="hint">{m('onboarding.step5Hint')}</p>
				<div class="privacy-list" role="radiogroup" aria-labelledby="step-privacy-title">
					{#each [
						{ value: 'private', name: m('onboarding.privacyPrivate'), desc: m('onboarding.privacyPrivateDesc') },
						{ value: 'followers', name: m('onboarding.privacyFollowers'), desc: m('onboarding.privacyFollowersDesc') },
						{ value: 'public', name: m('onboarding.privacyPublic'), desc: m('onboarding.privacyPublicDesc') },
					] as const as option (option.value)}
						<button
							type="button"
							class="choice privacy-row"
							class:selected={privacyDefault === option.value}
							role="radio"
							aria-checked={privacyDefault === option.value}
							onclick={() => (privacyDefault = option.value)}
						>
							<span class="goal-glyph" aria-hidden="true"><span class="material-symbols">{PRIVACY_ICON[option.value]}</span></span>
							<span class="choice-text">
								<strong class="choice-name">{option.name}</strong>
								<span class="choice-desc">{option.desc}</span>
							</span>
							<span class="choice-mark" aria-hidden="true"></span>
						</button>
					{/each}
				</div>
			</section>
		{:else if current === 'notifications'}
			<section aria-labelledby="step-notifications-title">
				<span class="step-icon step-icon--bell" aria-hidden="true"><span class="material-symbols">notifications_active</span></span>
				<h1 id="step-notifications-title" tabindex="-1">{m('onboarding.step6Title')}</h1>
				<p class="hint">{m('onboarding.step6Hint')}</p>
				{#if !pushSupported}
					<p class="not-available">{m('onboarding.pushUnsupported')}</p>
				{:else if pushPermission() === 'denied'}
					<p class="not-available">{m('onboarding.pushBlocked')}</p>
				{:else if pushSubscribed}
					<p class="success-text">
						<span class="material-symbols" aria-hidden="true">check_circle</span>
						{m('onboarding.pushEnabled')}
					</p>
				{:else}
					<button
						type="button"
						class="btn btn-primary push-cta"
						onclick={handleEnablePush}
						disabled={pushBusy}
					>
						<span class="material-symbols" aria-hidden="true">notifications_active</span>
						{pushBusy ? m('onboarding.pushEnabling') : m('onboarding.pushEnable')}
					</button>
				{/if}
			</section>
		{:else if current === 'done'}
			<section class="finish" aria-labelledby="step-done-title">
				<span class="done-badge" aria-hidden="true">
					<span class="done-ring"></span>
					<span class="material-symbols">check</span>
				</span>
				<h1 id="step-done-title" tabindex="-1">{m('onboarding.step7Title')}</h1>
				<p class="hint">{m('onboarding.step7Hint')}</p>
				{#if primaryGoal}
					<button
						type="button"
						class="btn btn-primary create-plan-cta"
						onclick={() => finishAndExit(`/plans/new?type=training&goal=${primaryGoal}`)}
						disabled={saving}
					>
						<span class="material-symbols" aria-hidden="true">{GOAL_ICON[primaryGoal]}</span>
						{saving ? m('onboarding.saving') : m('onboarding.createPlanCta')}
					</button>
				{/if}
			</section>
		{/if}
		</div>
		{/key}

		{#if ready}
		<div class="nav-row">
			{#if step > 1}
				<button type="button" class="btn btn-outline nav-back" onclick={back} disabled={saving}>
					<span class="material-symbols" aria-hidden="true">arrow_back</span>
					{m('onboarding.back')}
				</button>
			{:else}
				<span></span>
			{/if}
			<div class="nav-right">
				{#if current === 'goal' || current === 'about' || current === 'notifications'}
					<button
						type="button"
						class="skip-step"
						onclick={skipStep}
						disabled={saving || (current === 'about' && weightOutOfRange)}
					>
						{m('onboarding.skip')}
					</button>
				{/if}
				{#if step < total}
					<button
						type="button"
						class="btn btn-primary nav-next"
						onclick={next}
						disabled={saving || (current === 'about' && weightOutOfRange)}
					>
						{m('onboarding.continue')}
						<span class="material-symbols" aria-hidden="true">arrow_forward</span>
					</button>
				{:else}
					<button
						type="button"
						class="btn nav-next {primaryGoal ? 'btn-outline' : 'btn-primary'}"
						onclick={() => finishAndExit()}
						disabled={saving}
					>
						{saving ? m('onboarding.saving') : m('onboarding.openDashboard')}
					</button>
				{/if}
			</div>
		</div>
		{/if}
	</main>
</AuthShell>

<style>
	/* Layout, the brand panel and the card chrome belong to AuthShell (the
	   same shell as sign-up, so the journey is one design from the landing
	   page into the app). What is here is the wizard's own furniture. */

	/* --- panel copy (inks measured on AuthShell's ramp) ------------------ */

	.panel-kicker {
		margin: 0 0 var(--space-sm);
		font-size: 0.78rem;
		font-weight: 700;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: #FFB59C;
	}

	.panel-title {
		margin: 0 0 var(--space-sm);
		font-size: clamp(1.8rem, 2.6vw, 2.4rem);
		font-weight: 800;
		line-height: 1.1;
		letter-spacing: -0.03em;
		text-wrap: balance;
	}

	.panel-sub {
		margin: 0 0 var(--space-xl);
		max-width: 26rem;
		font-size: 0.95rem;
		line-height: 1.55;
		color: rgba(255, 255, 255, 0.85);
	}

	.rail {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	.rail li {
		position: relative;
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		font-size: 0.92rem;
		color: rgba(255, 255, 255, 0.85);
	}

	/* The line joining each mark to the next. */
	.rail li:not(:last-child)::after {
		content: '';
		position: absolute;
		inset-inline-start: 0.8rem;
		top: 1.75rem;
		height: 0.35rem;
		width: 1px;
		background: rgba(255, 255, 255, 0.25);
	}

	.rail-mark {
		flex-shrink: 0;
		display: grid;
		place-items: center;
		width: 1.6rem;
		height: 1.6rem;
		border-radius: var(--radius-pill);
		border: 1px solid rgba(255, 255, 255, 0.3);
		font-size: 0.8rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		transition: background var(--transition-base), border-color var(--transition-base);
	}

	.rail-mark .material-symbols {
		font-size: 1rem;
	}

	.rail-done .rail-mark {
		border-color: transparent;
		background: rgba(255, 255, 255, 0.14);
		color: #FFB59C;
	}

	/* White disc, plum numeral: 11.18:1, and no text on a gradient. */
	.rail-now .rail-mark {
		border-color: transparent;
		background: #FFFFFF;
		color: #6E1450;
		box-shadow: 0 0 0 0.3rem rgba(255, 255, 255, 0.14);
	}

	.rail-now .rail-name {
		font-weight: 700;
		color: #FFFFFF;
	}

	/* --- card ------------------------------------------------------------ */

	.card-top {
		display: flex;
		align-items: center;
		gap: var(--space-md);
	}

	.progress-track {
		flex: 1;
		height: 0.4rem;
		border-radius: var(--radius-pill);
		background: var(--color-bg-tertiary);
		overflow: hidden;
	}

	.progress-fill {
		display: block;
		height: 100%;
		width: calc(var(--progress) * 100%);
		border-radius: inherit;
		background: linear-gradient(90deg, var(--brand-ember), var(--brand-magenta));
		transition: width 500ms cubic-bezier(0.22, 1, 0.36, 1);
	}

	.skip-all {
		flex-shrink: 0;
		background: none;
		border: none;
		padding: var(--space-2xs) 0;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		cursor: pointer;
		text-decoration: underline;
		text-underline-offset: 0.2em;
	}
	.skip-all:hover { color: var(--color-text); }
	.skip-all:disabled { opacity: 0.5; cursor: not-allowed; }

	.step-count {
		margin: var(--space-sm) 0 var(--space-lg);
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--color-text-tertiary);
	}

	/* The panel's kicker says the same thing beside the card on a desktop;
	   on a phone the panel is a band with no copy, so the card says it. */
	@media (min-width: 56rem) {
		.step-count {
			visibility: hidden;
			margin-bottom: var(--space-sm);
		}
	}

	/* Each step slides in from the side the reader is moving toward. The
	   frame is re-keyed per step, so this plays on every change; declared
	   only for visitors who accept motion. */
	@media (prefers-reduced-motion: no-preference) {
		.step-frame {
			animation: step-in 420ms cubic-bezier(0.22, 1, 0.36, 1) backwards;
		}
	}

	@keyframes step-in {
		from {
			opacity: 0;
			transform: translateX(calc(1.5rem * var(--from) * var(--dir-sign)));
		}
	}

	section { display: flex; flex-direction: column; gap: var(--space-md); }

	.step-icon {
		display: grid;
		place-items: center;
		width: 2.75rem;
		height: 2.75rem;
		border-radius: 0.9rem;
		background: var(--color-primary-light);
		color: var(--color-primary);
	}

	.step-icon .material-symbols {
		font-size: 1.5rem;
	}

	h1 {
		font-size: 1.75rem;
		font-weight: 800;
		line-height: 1.15;
		letter-spacing: -0.025em;
		margin: 0;
		text-wrap: balance;
	}

	.hint {
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		line-height: 1.55;
		margin: 0 0 var(--space-sm);
	}

	.loading-hint {
		color: var(--color-text-secondary);
		margin: var(--space-xl) 0;
	}

	.field { display: flex; flex-direction: column; gap: 0.4rem; }
	.field-row {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-md);
	}
	@media (min-width: 32rem) {
		.field-row { grid-template-columns: repeat(2, minmax(0, 1fr)); }
	}
	.label-text { font-size: 0.85rem; color: var(--color-text-secondary); font-weight: 600; }
	.field-note { font-size: 0.8rem; color: var(--color-text-secondary); line-height: 1.5; margin: calc(-1 * var(--space-xs)) 0 0; }
	.field-error { font-size: 0.8rem; color: var(--color-danger-text); line-height: 1.45; }
	.field input, .field select {
		min-height: 2.9rem;
		padding: 0.65rem 0.8rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 1rem;
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}
	.field input:focus, .field select:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-primary) 18%, transparent);
	}
	/* Keyboard-only focus retains a visible indicator per
	   WCAG 2.4.7 (Focus Visible) + 2.4.11 (Focus Appearance).
	   Pointer / touch focus loses the ring (handled by the :focus
	   rule above) so the form looks clean during mouse use. The
	   a11y_guards.test.ts guard pins that every
	   `:focus { outline:none }` selector has a matching
	   `:focus-visible` companion. */
	.field input:focus-visible, .field select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	/* --- choices --------------------------------------------------------- */

	/* One tile shape for every single-choice question: a whole-row target,
	   a radio mark that fills when chosen, and a ring rather than a colour
	   change alone, so the choice reads without relying on hue. */
	.choice {
		position: relative;
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		width: 100%;
		padding: var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: start;
		color: var(--color-text);
		font: inherit;
		font-size: 0.95rem;
		cursor: pointer;
		transition:
			border-color var(--transition-fast),
			background var(--transition-fast),
			box-shadow var(--transition-fast),
			transform var(--transition-fast);
	}

	.choice:hover {
		border-color: var(--color-primary);
		transform: translateY(-1px);
	}

	.choice.selected {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
		box-shadow: inset 0 0 0 1px var(--color-primary);
	}

	.choice-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}

	.choice-name { font-weight: 600; }
	.choice-desc { font-size: 0.85rem; color: var(--color-text-secondary); line-height: 1.45; }

	.choice-mark {
		flex-shrink: 0;
		width: 1.15rem;
		height: 1.15rem;
		margin-inline-start: auto;
		border-radius: var(--radius-pill);
		border: 2px solid var(--color-border);
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}

	.choice.selected .choice-mark {
		border-color: var(--color-primary);
		box-shadow: inset 0 0 0 0.2rem var(--color-surface);
		background: var(--color-primary);
	}

	.unit-tiles, .privacy-list { display: flex; flex-direction: column; gap: var(--space-sm); }
	@media (min-width: 32rem) {
		.unit-tiles { flex-direction: row; }
	}

	.unit-abbr {
		flex-shrink: 0;
		display: grid;
		place-items: center;
		width: 2.75rem;
		height: 2.75rem;
		border-radius: 0.8rem;
		background: var(--color-bg-tertiary);
		font-size: 1rem;
		font-weight: 800;
		letter-spacing: -0.02em;
		color: var(--color-text);
	}

	.choice.selected .unit-abbr,
	.choice.selected .goal-glyph {
		background: var(--color-primary);
		color: var(--color-on-primary);
	}

	.unit-sample { font-variant-numeric: tabular-nums; }

	.goal-grid {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-sm);
	}
	@media (min-width: 32rem) {
		.goal-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
	}

	.goal-glyph {
		flex-shrink: 0;
		display: grid;
		place-items: center;
		width: 2.4rem;
		height: 2.4rem;
		border-radius: 0.75rem;
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		transition: background var(--transition-fast), color var(--transition-fast);
	}

	.goal-glyph .material-symbols {
		font-size: 1.3rem;
	}

	.consent-row {
		display: flex;
		gap: 0.6rem;
		align-items: flex-start;
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		cursor: pointer;
	}
	.consent-row:has(input:checked) {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
	}
	.consent-row input { margin-top: 0.2rem; flex-shrink: 0; }

	.not-available {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		margin: 0;
	}

	.success-text {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.95rem;
		color: var(--color-success-text);
		margin: 0;
	}

	.push-cta,
	.create-plan-cta {
		align-self: flex-start;
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}

	/* --- finish ---------------------------------------------------------- */

	.finish {
		align-items: center;
		text-align: center;
		padding-top: var(--space-md);
	}

	.finish .create-plan-cta {
		align-self: center;
	}

	.done-badge {
		position: relative;
		display: grid;
		place-items: center;
		width: 4.5rem;
		height: 4.5rem;
		border-radius: var(--radius-pill);
		background: linear-gradient(140deg, var(--brand-ember), var(--brand-magenta));
		color: #FFFFFF;
		box-shadow: 0 1rem 2.5rem -0.75rem rgba(160, 30, 119, 0.6);
	}

	.done-badge .material-symbols {
		font-size: 2.4rem;
	}

	.done-ring {
		position: absolute;
		inset: 0;
		border-radius: inherit;
		border: 2px solid var(--brand-ember);
		opacity: 0;
	}

	/* Arrives once: the badge pops and a ring spreads out and fades. */
	@media (prefers-reduced-motion: no-preference) {
		.done-badge {
			animation: badge-pop 700ms cubic-bezier(0.34, 1.56, 0.64, 1) 120ms backwards;
		}
		.done-ring {
			animation: ring-out 1100ms ease-out 300ms;
		}
	}

	@keyframes badge-pop {
		from { transform: scale(0.4); opacity: 0; }
	}

	@keyframes ring-out {
		from { transform: scale(1); opacity: 0.8; }
		to { transform: scale(1.9); opacity: 0; }
	}

	/* --- navigation ------------------------------------------------------ */

	.nav-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		margin-top: var(--space-xl);
		padding-top: var(--space-lg);
		border-top: 1px solid var(--color-border);
	}
	.nav-right {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.nav-back,
	.nav-next {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		min-height: 2.75rem;
		border-radius: var(--radius-lg);
	}
	.nav-back .material-symbols,
	.nav-next .material-symbols {
		font-size: 1.15rem;
	}
	.skip-step {
		background: none;
		border: none;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		cursor: pointer;
		padding: 0.5rem 0.5rem;
	}
	.skip-step:hover { color: var(--color-text); }
	.skip-step:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
