<script lang="ts">
	import { effective } from '$lib/settings/settings';
	import { m, currentLocale } from '$lib/i18n/store.svelte';
	import {
		MAX_HR_BPM_MIN,
		MAX_HR_BPM_MAX,
		isUsableMaxHrBpm,
		RESTING_HR_BPM_MIN,
		RESTING_HR_BPM_MAX,
		isUsableRestingHrBpm,
	} from '$lib/training/hr_zones';
	import { numberInputValue } from '$lib/settings/number_input';
	import {
		WEEKLY_GOAL_KEY,
		WEEKLY_GOAL_MAX,
		WEEKLY_GOAL_MIN,
		isUsableWeeklyGoalInput,
		weeklyGoalFromInput,
		weeklyGoalToInput,
	} from '$lib/settings/weekly_goal';
	import { formatDecimal, formatInteger } from '$lib/format/number';
	import { createPrefsPage } from '$lib/settings/prefs_page.svelte';
	import PrefsPage from '$lib/components/settings/PrefsPage.svelte';

	let preferredUnit = $state<'km' | 'mi'>('km');

	let weeklyGoalStoredM = $state<number | null>(null);
	let weeklyGoalInput = $state<number | null>(null);
	const weeklyGoalTyped = $derived(
		typeof weeklyGoalInput === 'number' && Number.isFinite(weeklyGoalInput) ? weeklyGoalInput : null,
	);
	const weeklyGoalOutOfRange = $derived(
		weeklyGoalTyped !== null && !isUsableWeeklyGoalInput(weeklyGoalTyped),
	);

	// Measured resting + max HR. max_hr_bpm overrides the Tanaka
	// 208 − 0.7 × age estimate for HR-zone derivation — the reason a
	// beta-blocked runner whose formula HR-max is wrong needs to set it.
	let restingHr = $state('');
	let maxHr = $state('');
	// `min`/`max` on these inputs are COSMETIC: the fields autosave onblur and
	// never reach a form submit, so the browser's constraint validation never
	// runs. Both keys are jsonb prefs with no column and no CHECK, so these
	// predicates are the only thing between a typo and readers that silently
	// ignore it (decisions § 1407 / § 1409).
	const maxHrParsed = $derived(numberInputValue(maxHr));
	const maxHrOutOfRange = $derived(maxHrParsed !== null && !isUsableMaxHrBpm(maxHrParsed));
	const maxHrBounds = { min: MAX_HR_BPM_MIN, max: MAX_HR_BPM_MAX };
	const restingHrParsed = $derived(numberInputValue(restingHr));
	const restingHrOutOfRange = $derived(
		restingHrParsed !== null && !isUsableRestingHrBpm(restingHrParsed),
	);
	const restingHrBounds = { min: RESTING_HR_BPM_MIN, max: RESTING_HR_BPM_MAX };

	let z1 = $state('');
	let z2 = $state('');
	let z3 = $state('');
	let z4 = $state('');
	let z5 = $state('');
	// Opt-out: drop gym load from the run fitness/fatigue/form curve so the
	// dashboard readiness stays run-only. Default off (gym counts).
	let excludeGymFromReadiness = $state(false);

	// Race-fueling intake rates — the per-hour carbs + fluid the roadbook fuel
	// plan scales onto each leg. Defaults 60 g/hr + 500 ml/hr (fuel_plan.ts).
	let carbsPerHour = $state('60');
	let fluidPerHour = $state('500');
	let coachPersonality = $state<'supportive' | 'drill_sergeant' | 'analytical'>('supportive');

	const prefs = createPrefsPage(async ({ settings, preferredUnit: unit }) => {
		preferredUnit = unit;
		weeklyGoalStoredM = effective<number>(settings, WEEKLY_GOAL_KEY) ?? null;
		weeklyGoalInput = weeklyGoalToInput(weeklyGoalStoredM, unit);
		restingHr = (effective<number>(settings, 'resting_hr_bpm') ?? '')?.toString() ?? '';
		maxHr = (effective<number>(settings, 'max_hr_bpm') ?? '')?.toString() ?? '';
		const zones = effective<Record<string, number>>(settings, 'hr_zones');
		if (zones) {
			z1 = zones.z1?.toString() ?? '';
			z2 = zones.z2?.toString() ?? '';
			z3 = zones.z3?.toString() ?? '';
			z4 = zones.z4?.toString() ?? '';
			z5 = zones.z5?.toString() ?? '';
		}
		excludeGymFromReadiness = effective<boolean>(settings, 'exclude_gym_from_readiness', false) === true;
		carbsPerHour = (effective<number>(settings, 'carbs_per_hour', 60) ?? 60).toString();
		fluidPerHour = (effective<number>(settings, 'fluid_per_hour', 500) ?? 500).toString();
		coachPersonality = effective(settings, 'coach_personality', 'supportive') ?? 'supportive';
	});

	function saveWeeklyGoal() {
		if (weeklyGoalOutOfRange) return;
		weeklyGoalStoredM = weeklyGoalFromInput(weeklyGoalTyped, preferredUnit, weeklyGoalStoredM);
		prefs.save({ [WEEKLY_GOAL_KEY]: weeklyGoalStoredM });
	}

	function saveMaxHr() {
		if (maxHrOutOfRange) return;
		prefs.save({ max_hr_bpm: maxHrParsed });
	}

	function saveRestingHr() {
		if (restingHrOutOfRange) return;
		prefs.save({ resting_hr_bpm: restingHrParsed });
	}

	// HR zones are a single jsonb object — rebuilt from the five fields on each
	// blur (null when all blank). Health-adjacent but not Art 9 special
	// category, and carry no consent gate, so auto-saving keeps that posture.
	function saveHrZones() {
		const z =
			z1 || z2 || z3 || z4 || z5
				? {
						z1: parseInt(z1, 10) || 0,
						z2: parseInt(z2, 10) || 0,
						z3: parseInt(z3, 10) || 0,
						z4: parseInt(z4, 10) || 0,
						z5: parseInt(z5, 10) || 0,
					}
				: null;
		prefs.save({ hr_zones: z });
	}
</script>

<PrefsPage heading={m('prefs.trainingHeading')} tagline={m('prefs.trainingTagline')} page={prefs}>
	<section class="card" id="weekly-distance-goal">
		<h2>{m('prefs.weeklyGoalHeading')}</h2>
		<div class="form-grid">
			<label>
				<span class="label-text">{m('prefs.weeklyDistanceGoal', { unit: preferredUnit })}</span>
				<input
					type="number"
					inputmode="decimal"
					step="0.1"
					min={WEEKLY_GOAL_MIN}
					max={WEEKLY_GOAL_MAX}
					bind:value={weeklyGoalInput}
					placeholder={m('prefs.weeklyDistanceGoalPlaceholder', {
						example: preferredUnit === 'mi' ? '25' : '40',
					})}
					aria-invalid={weeklyGoalOutOfRange}
					data-testid="weekly-distance-goal"
					onblur={saveWeeklyGoal}
				/>
				{#if weeklyGoalOutOfRange}
					<span class="field-error" data-testid="weekly-distance-goal-error">
						{m('prefs.weeklyDistanceGoalOutOfRange', {
							min: formatDecimal(WEEKLY_GOAL_MIN, 1, currentLocale()),
							max: formatInteger(WEEKLY_GOAL_MAX, currentLocale()),
							unit: preferredUnit,
						})}
					</span>
				{/if}
			</label>
		</div>
	</section>

	<section class="card" id="heart-rate-zones">
		<h2>{m('prefs.heartRateZonesHeading')}</h2>
		<p class="section-desc">{m('prefs.heartRateZonesDesc')}</p>
		<div class="form-grid">
			<label>
				<span class="label-text">{m('prefs.restingHr')}</span>
				<input type="number" bind:value={restingHr} min={RESTING_HR_BPM_MIN} max={RESTING_HR_BPM_MAX} placeholder={m('prefs.restingHrPlaceholder')} aria-invalid={restingHrOutOfRange} data-testid="resting-hr" onblur={saveRestingHr} />
				{#if restingHrOutOfRange}
					<span class="field-error" data-testid="resting-hr-error">{m('limits.restingHrOutOfRange', restingHrBounds)}</span>
				{/if}
			</label>
			<label>
				<span class="label-text">{m('prefs.maxHr')}</span>
				<input type="number" bind:value={maxHr} min={MAX_HR_BPM_MIN} max={MAX_HR_BPM_MAX} placeholder={m('prefs.maxHrPlaceholder')} aria-invalid={maxHrOutOfRange} data-testid="max-hr" onblur={saveMaxHr} />
				{#if maxHrOutOfRange}
					<span class="field-error" data-testid="max-hr-error">{m('limits.maxHrOutOfRange', maxHrBounds)}</span>
				{/if}
			</label>
		</div>
		<p class="section-desc">{m('prefs.zonesUpperBoundDesc')}</p>
		<div class="form-grid zones">
			<label><span class="label-text">{m('prefs.zone1Recovery')}</span><input type="number" bind:value={z1} placeholder="130" onblur={saveHrZones} /></label>
			<label><span class="label-text">{m('prefs.zone2Easy')}</span><input type="number" bind:value={z2} placeholder="145" onblur={saveHrZones} /></label>
			<label><span class="label-text">{m('prefs.zone3Tempo')}</span><input type="number" bind:value={z3} placeholder="160" onblur={saveHrZones} /></label>
			<label><span class="label-text">{m('prefs.zone4Threshold')}</span><input type="number" bind:value={z4} placeholder="175" onblur={saveHrZones} /></label>
			<label><span class="label-text">{m('prefs.zone5Max')}</span><input type="number" bind:value={z5} placeholder="195" onblur={saveHrZones} /></label>
		</div>
		<label class="checkbox-row">
			<input type="checkbox" bind:checked={excludeGymFromReadiness} onchange={() => prefs.save({ exclude_gym_from_readiness: excludeGymFromReadiness })} />
			<span>
				{m('prefs.excludeGymFromReadiness')}
				<span class="hint">{m('prefs.excludeGymFromReadinessHint')}</span>
			</span>
		</label>
	</section>

	<section class="card">
		<h2>{m('prefs.raceFuelingHeading')}</h2>
		<div class="form-grid">
			<label>
				<span class="label-text">{m('prefs.carbsPerHour')}</span>
				<input
					type="number"
					min="0"
					max="200"
					inputmode="numeric"
					bind:value={carbsPerHour}
					data-testid="carbs-per-hour"
					onblur={() => prefs.save({ carbs_per_hour: carbsPerHour ? parseInt(carbsPerHour, 10) || null : null })}
				/>
			</label>
			<label>
				<span class="label-text">{m('prefs.fluidPerHour')}</span>
				<input
					type="number"
					min="0"
					max="3000"
					inputmode="numeric"
					bind:value={fluidPerHour}
					data-testid="fluid-per-hour"
					onblur={() => prefs.save({ fluid_per_hour: fluidPerHour ? parseInt(fluidPerHour, 10) || null : null })}
				/>
			</label>
		</div>
	</section>

	<section class="card">
		<h2>{m('prefs.aiCoachHeading')}</h2>
		<div class="form-grid">
			<label>
				<span class="label-text">{m('prefs.coachPersonality')}</span>
				<select bind:value={coachPersonality} onchange={() => prefs.save({ coach_personality: coachPersonality })}>
					<option value="supportive">{m('prefs.coachSupportive')}</option>
					<option value="drill_sergeant">{m('prefs.coachDrillSergeant')}</option>
					<option value="analytical">{m('prefs.coachAnalytical')}</option>
				</select>
			</label>
		</div>
	</section>
</PrefsPage>
