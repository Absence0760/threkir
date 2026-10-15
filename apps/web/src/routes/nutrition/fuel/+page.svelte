<script lang="ts">
	// The fuelling plan for one run, without a route: the page the Coach's
	// fuelling handoff links to (decisions § 1975). The Coach writes only the
	// duration and any per-hour rate the runner stated; every parameter is
	// validated by parseFuelHandoff, the totals come from the same
	// buildFuelPlan the roadbook uses, and a rate the link does not carry is the
	// runner's own saved one. Nothing here is sent anywhere.
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { loadSettings, effective } from '#lib/settings/settings.ts';
	import { supabase } from '#lib/core/supabase.ts';
	import { fetchLatestWeightKg } from '#lib/core/data.ts';
	import { healthUseWeightKg } from '#lib/core/health_consent.ts';
	import { coachFuelEnabled } from '#lib/nutrition/coach_fuel_flag.ts';
	import {
		buildFuelPlan,
		DEFAULT_CARBS_PER_HOUR_G,
		DEFAULT_FLUID_PER_HOUR_ML,
		GEL_CARBS_G,
		HEAT_FLUID_FACTOR
	} from '#lib/routes/fuel_plan.ts';
	import {
		FUEL_MAX_CARBS_PER_HOUR_G,
		FUEL_MAX_FLUID_PER_HOUR_ML,
		parseClockDurationS,
		parseFuelHandoff,
		resolveFluidRate,
		resolveFuelRate,
		type FuelRateSource
	} from '#lib/routes/fuel_params.ts';

	const enabled = coachFuelEnabled();

	let carbsPrefG = $state<number | null>(null);
	let fluidPrefMl = $state<number | null>(null);
	// A weight the Art 9 gate lets the fluid rate use, or null (decisions
	// § 1976). Read only for the signed-in runner's own record.
	let consentedWeightKg = $state<number | null>(null);

	$effect(() => {
		if (enabled) void loadPrefs();
	});

	async function loadPrefs() {
		await auth.ready();
		if (!auth.user) return;
		try {
			const [settings, weight, profileRes] = await Promise.all([
				loadSettings(auth.user.id),
				fetchLatestWeightKg(),
				supabase.rpc('get_my_profile', undefined, { get: true }).maybeSingle(),
			]);
			carbsPrefG = effective<number>(settings, 'carbs_per_hour') ?? null;
			fluidPrefMl = effective<number>(settings, 'fluid_per_hour') ?? null;
			consentedWeightKg = healthUseWeightKg(profileRes.data, weight);
		} catch (e) {
			// The defaults still give a plan; the source label says which rate
			// the totals used, so a failed read is visible rather than silent.
			console.error('fuel page: settings load failed', e);
		}
	}

	const handoff = $derived(parseFuelHandoff(page.url.searchParams));

	const carbs = $derived(resolveFuelRate(handoff.carbsPerHourG, carbsPrefG, DEFAULT_CARBS_PER_HOUR_G));
	const fluid = $derived(
		resolveFluidRate({
			useWeight: handoff.useWeight,
			weightKg: consentedWeightKg,
			linkValue: handoff.fluidPerHourMl,
			pref: fluidPrefMl,
			fallback: DEFAULT_FLUID_PER_HOUR_ML
		})
	);

	const plan = $derived(
		handoff.durationS == null
			? null
			: buildFuelPlan(
					[
						{ projectedElapsedS: 0, legDistM: 0, services: [] },
						{ projectedElapsedS: handoff.durationS, legDistM: 0, services: [] }
					],
					{
						carbsPerHourG: carbs.value,
						fluidPerHourMl: fluid.value,
						heatFactor: handoff.heat ? HEAT_FLUID_FACTOR : 1
					}
				)
	);

	function clockOf(seconds: number | null): string {
		if (seconds == null) return '';
		const h = Math.floor(seconds / 3600);
		const mm = Math.floor((seconds % 3600) / 60);
		return `${h}:${String(mm).padStart(2, '0')}`;
	}

	function updateParam(key: string, value: string | null) {
		const url = new URL(page.url.href);
		if (value == null || value === '') url.searchParams.delete(key);
		else url.searchParams.set(key, value);
		goto(`${url.pathname}${url.search}`, { replace: true, keepFocus: true, noScroll: true });
	}

	function onDurationChange(e: Event) {
		const secs = parseClockDurationS((e.currentTarget as HTMLInputElement).value);
		updateParam('duration', secs == null ? null : String(secs));
	}

	function onRateChange(key: 'carbs' | 'fluid', e: Event) {
		updateParam(key, (e.currentTarget as HTMLInputElement).value.trim() || null);
	}

	function sourceLabel(source: FuelRateSource): string {
		if (source === 'fromWeight') return m('fuelPlan.sourceWeight');
		if (source === 'fromLink') return m('fuelPlan.sourceLink');
		if (source === 'fromSettings') return m('fuelPlan.sourceSettings');
		return m('fuelPlan.sourceDefault');
	}
</script>

<svelte:head><title>{m('fuelPlan.title')} — Threkir</title></svelte:head>

<div class="fuel-page">
	<header class="page-header">
		<h1>{m('fuelPlan.title')}</h1>
		<p class="head-sub">{m('fuelPlan.intro')}</p>
	</header>

	{#if !enabled}
		<section class="card-elevated" data-testid="fuel-unavailable">
			<p>{m('fuelPlan.unavailable')}</p>
		</section>
	{:else}
		<section class="card-elevated fuel-inputs">
			<div class="form-grid">
				<label class="field">
					<span class="label-text">{m('fuelPlan.duration')}</span>
					<input
						type="text"
						inputmode="numeric"
						placeholder="2:30"
						value={clockOf(handoff.durationS)}
						onchange={onDurationChange}
						data-testid="fuel-duration"
					/>
				</label>
				<label class="field">
					<span class="label-text">{m('prefs.carbsPerHour')}</span>
					<input
						type="number"
						min="0"
						max={FUEL_MAX_CARBS_PER_HOUR_G}
						inputmode="numeric"
						value={carbs.value}
						onchange={(e) => onRateChange('carbs', e)}
						data-testid="fuel-carbs-rate"
					/>
					<span class="rate-source" data-testid="fuel-carbs-source">{sourceLabel(carbs.source)}</span>
				</label>
				<label class="field">
					<span class="label-text">{m('prefs.fluidPerHour')}</span>
					<input
						type="number"
						min="0"
						max={FUEL_MAX_FLUID_PER_HOUR_ML}
						inputmode="numeric"
						value={fluid.value}
						disabled={fluid.source === 'fromWeight'}
						onchange={(e) => onRateChange('fluid', e)}
						data-testid="fuel-fluid-rate"
					/>
					<span class="rate-source" data-testid="fuel-fluid-source">{sourceLabel(fluid.source)}</span>
				</label>
			</div>
			<label class="heat-toggle">
				<input
					type="checkbox"
					checked={handoff.heat}
					onchange={(e) => updateParam('heat', (e.currentTarget as HTMLInputElement).checked ? '1' : null)}
					data-testid="fuel-heat"
				/>
				{m('fuelPlan.heat', { factor: String(HEAT_FLUID_FACTOR) })}
			</label>
			<label class="heat-toggle">
				<input
					type="checkbox"
					checked={handoff.useWeight}
					disabled={consentedWeightKg == null}
					aria-describedby="fuel-weight-hint"
					onchange={(e) => updateParam('bw', (e.currentTarget as HTMLInputElement).checked ? '1' : null)}
					data-testid="fuel-weight"
				/>
				{m('fuelPlan.weightToggle')}
			</label>
			<p class="section-hint" id="fuel-weight-hint" data-testid="fuel-weight-hint">
				{consentedWeightKg == null ? m('fuelPlan.weightUnavailable') : m('fuelPlan.weightHint')}
			</p>
		</section>

		{#if plan == null}
			<p class="muted" data-testid="fuel-needs-duration">{m('fuelPlan.needsDuration')}</p>
		{:else}
			<section class="card-elevated fuel-totals" data-testid="fuel-totals">
				<ul class="total-list">
					<li>
						<span class="term">{m('fuelPlan.totalCarbs')}</span>
						<span class="value" data-testid="fuel-total-carbs">
							{m('roadbook.carbsValue', { grams: String(Math.round(plan.totalCarbsG)) })}
						</span>
					</li>
					<li>
						<span class="term">{m('fuelPlan.gels', { grams: String(GEL_CARBS_G) })}</span>
						<span class="value" data-testid="fuel-gels">{plan.legs[0].carryToNextAid?.gels ?? 0}</span>
					</li>
					<li>
						<span class="term">{m('fuelPlan.totalFluid')}</span>
						<span class="value" data-testid="fuel-total-fluid">
							{m('roadbook.fluidValue', { ml: String(Math.round(plan.totalFluidMl)) })}
						</span>
					</li>
				</ul>
				<p class="section-hint">{m('fuelPlan.disclaimer')}</p>
			</section>
		{/if}

		<p class="fuel-links">
			{m('fuelPlan.roadbookHint')}
			<a href="/routes">{m('fuelPlan.openRoutes')}</a>
			·
			<a href="/settings/training">{m('fuelPlan.changeRates')}</a>
		</p>
	{/if}
</div>

<style>
	.fuel-page {
		max-width: 720px;
		margin: 0 auto;
		padding: var(--space-lg);
	}

	.page-header {
		margin-bottom: var(--space-lg);
	}

	.page-header h1 {
		margin: 0;
		font-size: 1.6rem;
	}

	.head-sub {
		margin: 0.3rem 0 0;
		color: var(--color-text-secondary);
		font-size: 0.95rem;
	}

	section {
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}

	.form-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(11rem, 1fr));
		gap: var(--space-md);
	}

	.field {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}

	.label-text {
		font-size: 0.9rem;
		font-weight: 600;
	}

	.rate-source {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.heat-toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		margin-top: var(--space-md);
	}

	.total-list {
		list-style: none;
		margin: 0;
		padding: 0;
	}

	.total-list li {
		display: flex;
		justify-content: space-between;
		gap: var(--space-sm);
		padding: 0.4rem 0;
		border-bottom: 1px solid var(--color-border);
	}

	.total-list li:last-child {
		border-bottom: none;
	}

	.term {
		color: var(--color-text-secondary);
	}

	.value {
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}

	.section-hint {
		margin: var(--space-sm) 0 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.fuel-links {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}

	.muted {
		color: var(--color-text-secondary);
	}
</style>
