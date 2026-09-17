<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { effective, updateUniversal } from '$lib/settings/settings';
	import { m } from '$lib/i18n/store.svelte';
	import { fetchLatestWeightKg, recordWeightKg } from '$lib/core/data';
	import {
		kgToDisplay,
		displayToKg,
		roundWeight,
		defaultWeightUnitForDistanceUnit,
		weightBoundsIn,
	} from '$lib/format/weight';
	import { valueLimit, withinValueLimit } from '$lib/core/column_limits';
	import { ACTIVITY_LEVELS, type ActivityLevel, type WeightGoal } from '$lib/nutrition/nutrition_targets';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import type { Updatable } from '$lib/core/database';
	import { createPrefsPage } from '$lib/settings/prefs_page.svelte';
	import PrefsPage from '$lib/components/settings/PrefsPage.svelte';

	// Demographics card has its own explicit save (GDPR Art 9 consent gate).
	let savingDemographics = $state(false);
	let demographicsSaved = $state(false);
	let weightUnit = $state<'kg' | 'lbs'>('kg');

	// Gender is special-category data under GDPR Art 9 and only persists under
	// the explicit Art 9(2)(a) consent `healthDataConsent` stamps. DOB is split
	// across two stores with two different rules (decisions § 718): the
	// `user_profiles` column is the AGE RECORD backing the under-18
	// discoverability floor — a child-protection purpose, so it is written
	// whenever the runner supplies a date, consent or not — while the
	// `user_settings.prefs` mirror is the Art 9 HEALTH-USE copy the coach + HR
	// reads consume, written only under consent and cleared on withdrawal.
	let gender = $state<'male' | 'female' | ''>('');
	let dateOfBirth = $state('');
	let healthDataConsent = $state(false);
	let healthDataConsentAt = $state<string | null>(null);
	// Height lives on user_profiles; weight is appended to the body_metrics
	// time-series on save. Both are shown in cm / the runner's weight unit but
	// stored canonically (cm, kg). Bound to <input type="number">, so these hold
	// a number (or null when empty) — never call string methods on them.
	let heightCm = $state<number | null>(null);
	let weightInput = $state<number | null>(null);
	// `min`/`max` on the inputs below are COSMETIC: the card saves from a
	// button's onclick, not a form submit, so the browser's constraint
	// validation never runs — the same trap issue #677 hit in the onboarding
	// wizard. These are the real gates, and both columns are CHECK-bounded, so
	// without them a typed 600 kg or 500 cm round-trips as a raw postgres
	// 23514 (decisions § 792).
	const weightBounds = $derived(weightBoundsIn('body_metrics.weight_kg', weightUnit));
	const heightBounds = valueLimit('user_profiles.height_cm');
	const weightOutOfRange = $derived(
		weightInput != null && !withinValueLimit('body_metrics.weight_kg', displayToKg(weightInput, weightUnit)),
	);
	const heightOutOfRange = $derived(
		heightCm != null && !withinValueLimit('user_profiles.height_cm', heightCm),
	);
	let loadedWeightKg = $state<number | null>(null);
	// Activity level + goal are nutrition preferences (not special-category),
	// so they auto-save to the prefs bag like the other preference pages.
	let nutritionActivityLevel = $state<ActivityLevel>('moderate');
	let nutritionGoal = $state<WeightGoal>('maintain');

	const prefs = createPrefsPage(async ({ settings, preferredUnit }) => {
		const storedWeightUnit = effective<string>(settings, 'weight_unit');
		weightUnit =
			storedWeightUnit === 'lbs' || storedWeightUnit === 'kg'
				? storedWeightUnit
				: defaultWeightUnitForDistanceUnit(preferredUnit);
		nutritionActivityLevel =
			effective<ActivityLevel>(settings, 'nutrition_activity_level', 'moderate') ?? 'moderate';
		nutritionGoal = effective<WeightGoal>(settings, 'nutrition_goal', 'maintain') ?? 'maintain';

		// Self-read via get_my_profile(): gender / date_of_birth /
		// health_data_consent_at are deny-by-default for direct authenticated
		// SELECTs (column lockdown, 20260707_001). A failed read must FAIL
		// CLOSED — otherwise the consent + demographics fields silently render
		// as unticked/blank defaults, which an explicit Save would then
		// round-trip back and clear the runner's real saved values.
		const { data: prof, error: profErr } = await supabase.rpc('get_my_profile');
		if (profErr) throw profErr;
		if (prof) {
			gender = prof.gender === 'male' || prof.gender === 'female' ? prof.gender : '';
			dateOfBirth = prof.date_of_birth ?? '';
			heightCm = prof.height_cm ?? null;
			healthDataConsentAt = (prof.health_data_consent_at as string | null) ?? null;
			// A consent stamp on the row means the box was ticked before; keep it
			// ticked so an edit does not ask for consent again.
			healthDataConsent = healthDataConsentAt != null;
		}

		// Latest weight is owner-only (body_metrics, no public read).
		loadedWeightKg = await fetchLatestWeightKg();
		weightInput =
			loadedWeightKg != null ? roundWeight(kgToDisplay(loadedWeightKg, weightUnit)) : null;
	});

	// Withdrawing consent (Art 7(3)) erases the saved height + the entire
	// weight time-series — irreversible, so confirm before running the save.
	// The DOB age record is the one field that survives a withdrawal (§ 718),
	// and since § 721 it survives it server-side: the RPC no longer nulls the
	// column, so nothing here re-asserts it.
	let showWithdrawConfirm = $state(false);
	function requestSaveDemographics() {
		if (!healthDataConsent && healthDataConsentAt != null) {
			showWithdrawConfirm = true;
			return;
		}
		saveDemographics();
	}

	async function saveDemographics() {
		if (!auth.user || prefs.phase !== 'ready') return;
		const heightVal = heightCm != null && heightCm > 0 ? heightCm : null;
		const weightDisplay = weightInput != null && weightInput > 0 ? weightInput : null;
		// DOB is deliberately absent from this gate: the column write is the
		// child-protection age record, not an Art 9 health use (§ 718).
		// Refusing the save left a minor who declined consent with a NULL DOB
		// and fully discoverable in people-search — the exact fail-open the
		// floor exists to close.
		const hasDemographic = !!(gender || heightVal != null || weightDisplay != null);
		if (hasDemographic && !healthDataConsent) {
			showToast(m('prefs.demographicsConsentRequired'), 'error');
			return;
		}
		// Checked here as well as on the button's disabled state so a value out
		// of the column's range cannot reach the insert through any other path.
		if (weightOutOfRange || heightOutOfRange) {
			showToast(
				weightOutOfRange
					? m('limits.weightOutOfRange', { ...weightBounds, unit: weightUnit })
					: m('limits.heightOutOfRange', heightBounds),
				'error',
			);
			return;
		}
		savingDemographics = true;
		demographicsSaved = false;
		try {
			if (healthDataConsent && healthDataConsentAt == null) {
				const { data: stampedAt, error: consentErr } =
					await supabase.rpc('grant_health_data_consent');
				if (consentErr) {
					showToast(m('prefs.saveFailed', { error: consentErr.message }), 'error');
					return;
				}
				if (stampedAt) healthDataConsentAt = stampedAt as string;
			}
			if (!healthDataConsent) {
				// Art 7(3): one SECURITY DEFINER RPC nulls the consent stamp +
				// gender + height and erases the weight series atomically.
				// Insert-or-update server-side, so a missing client-provisioned
				// profile row can't turn the withdrawal into a 0-row silent no-op
				// while the UI confirms success (issue #233).
				const { error: withdrawErr } = await supabase.rpc(
					'withdraw_health_data_consent',
				);
				if (withdrawErr) throw withdrawErr;
				healthDataConsentAt = null;
				loadedWeightKg = null;
				weightInput = null;
			}
			// One profile write on both arms. `date_of_birth` is the age record
			// and carries no consent term, because ending the Art 9 processing
			// does not end the child-safety discoverability floor (§ 718). gender
			// + height are the Art 9 fields and go null the moment consent is off.
			const profileUpdate: Updatable<'user_profiles'> = {
				date_of_birth: dateOfBirth || null,
				gender: healthDataConsent && gender ? gender : null,
				height_cm: healthDataConsent && heightVal != null ? heightVal : null,
			};
			// Row-count-verified: rows are client-provisioned, so a plain update
			// against a missing row matches 0 rows and reports success — the save
			// would silently vanish (issue #233).
			const { data: updatedRows, error } = await supabase
				.from('user_profiles')
				.update(profileUpdate)
				.eq('id', auth.user.id)
				.select('id');
			if (error) throw error;
			if (!updatedRows?.length) {
				const { error: insertErr } = await supabase
					.from('user_profiles')
					.insert({ id: auth.user.id, ...profileUpdate });
				if (insertErr) throw insertErr;
			}
			// The prefs-bag mirror is the Art 9 health-use copy (coach context,
			// HR-max derivation) — it follows consent in both directions, so a
			// withdrawal clears it here rather than leaving withdrawn
			// special-category data feeding those reads.
			await updateUniversal(auth.user.id, {
				date_of_birth: healthDataConsent && dateOfBirth ? dateOfBirth : null,
			});
			if (healthDataConsent && weightDisplay != null && weightDisplay > 0) {
				// Append a new measurement only when the value changed, so
				// re-saving the card doesn't pad the time-series.
				const kg = roundWeight(displayToKg(weightDisplay, weightUnit));
				if (loadedWeightKg == null || Math.abs(kg - loadedWeightKg) > 0.01) {
					await recordWeightKg(kg);
					loadedWeightKg = kg;
				}
			}
			demographicsSaved = true;
			showToast(m('prefs.demographicsSavedToast'), 'success');
			setTimeout(() => (demographicsSaved = false), 2000);
		} catch (e) {
			showToast(m('prefs.saveFailed', { error: (e as Error).message }), 'error');
		} finally {
			savingDemographics = false;
		}
	}
</script>

<PrefsPage heading={m('prefs.demographicsHeading')} tagline={m('prefs.bodyTagline')} page={prefs}>
	<!-- Gender, height and weight are special-category data under GDPR Art 9,
	     so the explicit-consent checkbox is the precondition for saving any of
	     them. The DOB field is deliberately NOT disabled with them: the column
	     it writes is the under-18 discoverability floor's age record, a
	     child-protection purpose that must stay reachable by a runner who
	     declines the health checkbox (§ 718). -->
	<section class="card" id="body-metrics">
		<p class="section-desc">{m('prefs.demographicsDesc')}</p>
		<p class="section-desc consent-notice" id="health-consent-notice">
			{m('prefs.demographicsConsentNotice')}
			<a href="/privacy">{m('prefs.privacyPolicyLink')}</a>{m('prefs.demographicsConsentNoticeTail')}
		</p>
		<label class="consent-checkbox">
			<input type="checkbox" bind:checked={healthDataConsent} aria-describedby="health-consent-notice" />
			<span>{m('prefs.demographicsConsent')}</span>
		</label>
		<div class="form-grid">
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.gender')}</span>
					<select bind:value={gender} disabled={!healthDataConsent} aria-describedby="gender-hint">
						<option value="">{m('prefs.genderPreferNotToSay')}</option>
						<option value="male">{m('prefs.genderMale')}</option>
						<option value="female">{m('prefs.genderFemale')}</option>
					</select>
				</label>
				<p class="hint" id="gender-hint">{m('prefs.genderHint')}</p>
			</div>
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.dateOfBirth')}</span>
					<input
						type="date"
						bind:value={dateOfBirth}
						max={new Date().toISOString().slice(0, 10)}
						aria-describedby="dob-purpose"
						data-testid="date-of-birth"
					/>
				</label>
				<p class="hint" id="dob-purpose">{m('prefs.dateOfBirthPurpose')}</p>
			</div>
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.heightCm')}</span>
					<input
						type="number"
						min={heightBounds.min}
						max={heightBounds.max}
						inputmode="numeric"
						bind:value={heightCm}
						disabled={!healthDataConsent}
						aria-invalid={heightOutOfRange}
						aria-describedby="height-hint"
						data-testid="height-cm"
					/>
					{#if heightOutOfRange}
						<span class="field-error" data-testid="height-cm-error">
							{m('limits.heightOutOfRange', heightBounds)}
						</span>
					{/if}
				</label>
				<p class="hint" id="height-hint">{m('prefs.heightHint')}</p>
			</div>
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.weight')} ({weightUnit})</span>
					<input
						type="number"
						min={weightBounds.min}
						max={weightBounds.max}
						inputmode="decimal"
						bind:value={weightInput}
						disabled={!healthDataConsent}
						aria-invalid={weightOutOfRange}
						aria-describedby="weight-hint"
						data-testid="weight"
					/>
					{#if weightOutOfRange}
						<span class="field-error" data-testid="weight-error">
							{m('limits.weightOutOfRange', { ...weightBounds, unit: weightUnit })}
						</span>
					{/if}
				</label>
				<p class="hint" id="weight-hint">{m('prefs.weightHint')}</p>
			</div>
		</div>
		{#if healthDataConsentAt}
			<p class="section-hint">
				{m('prefs.consentRecordedOn', { date: new Date(healthDataConsentAt).toLocaleDateString() })}
			</p>
		{/if}
		<!-- Unlike the other preference pages, demographics do NOT auto-save:
		     they are Art 9 special-category data, so persisting them is a
		     deliberate, consent-gated action behind this button. -->
		<button
			class="btn btn-primary btn-save"
			type="button"
			onclick={requestSaveDemographics}
			disabled={savingDemographics || weightOutOfRange || heightOutOfRange}
			data-testid="save-demographics"
		>
			{savingDemographics ? m('prefs.saving') : demographicsSaved ? m('prefs.demographicsSavedBtn') : m('prefs.saveDemographics')}
		</button>
	</section>

	<!-- Activity level + weight goal feed the Mifflin-St Jeor target on
	     /nutrition. Effort labels, not body measurements, so they auto-save
	     and aren't consent-gated. -->
	<section class="card">
		<h2>{m('prefs.nutritionTargetsHeading')}</h2>
		<div class="form-grid">
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.activityLevel')}</span>
					<select
						bind:value={nutritionActivityLevel}
						onchange={() => prefs.save({ nutrition_activity_level: nutritionActivityLevel })}
						aria-describedby="activity-level-hint"
						data-testid="activity-level"
					>
						{#each ACTIVITY_LEVELS as lvl (lvl.key)}
							<option value={lvl.key}>{m(`prefs.activity_${lvl.key}`)}</option>
						{/each}
					</select>
				</label>
				<p class="hint" id="activity-level-hint">{m('prefs.activityLevelHint')}</p>
			</div>
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.weightGoal')}</span>
					<select
						bind:value={nutritionGoal}
						onchange={() => prefs.save({ nutrition_goal: nutritionGoal })}
						aria-describedby="weight-goal-hint"
						data-testid="weight-goal"
					>
						<option value="lose">{m('prefs.goalLose')}</option>
						<option value="maintain">{m('prefs.goalMaintain')}</option>
						<option value="gain">{m('prefs.goalGain')}</option>
					</select>
				</label>
				<p class="hint" id="weight-goal-hint">{m('prefs.weightGoalHint')}</p>
			</div>
		</div>
		<p class="section-hint">{m('prefs.nutritionTargetsHint')}</p>
	</section>
</PrefsPage>

<ConfirmDialog
	open={showWithdrawConfirm}
	title={m('prefs.withdrawConsentTitle')}
	message={m('prefs.withdrawConsentMessage')}
	confirmLabel={m('prefs.withdrawConsentConfirm')}
	onconfirm={() => {
		showWithdrawConfirm = false;
		saveDemographics();
	}}
	oncancel={() => (showWithdrawConfirm = false)}
	danger
/>

<style>
	.btn-save { width: auto; }
</style>
