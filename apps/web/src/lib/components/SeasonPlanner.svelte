<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { AI_CONSENT_HREF } from '#lib/core/ai_disclosure.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { formatDistance, getUnit } from '#lib/format/units.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { createTrainingPlan, fetchMyOverlappingActivePlans, type PlanOverlapChoice } from '#lib/core/data.ts';
	import { loadPlanCalibration } from '#lib/training/plan_calibration_load.ts';
	import { coachEnabled } from '#lib/coach/coach_flag.ts';
	import { aiPlanEnabled } from '#lib/training/ai_plan_flag.ts';
	import PlanOverlapDialog, { trimBlockedMessage } from '#lib/components/PlanOverlapDialog.svelte';
	import type { OverlapPlan } from '#lib/training/plan_overlap.ts';
	import { fmtHms, formatISO, parseISO, type TrainingGender } from '#lib/training/training.ts';
	import { raceGoalInputSeconds } from '#lib/training/race_goal_input.ts';
	import { RACE_GOAL_MAX_HOURS } from '#lib/training/plan_races.ts';
	import { PlanRequestError, type PlanRequestErrorKind } from '#lib/training/plan_request_client.ts';
	import { requestSeasonRaces, seasonAssumptionMessageKey } from '#lib/training/season_request_client.ts';
	import type { SeasonRace, SeasonRacePriority } from '#lib/training/season_types.ts';
	import {
		SEASON_RACE_NAME_MAX,
		buildSeason,
		type SeasonBuildResult,
		type SeasonRefusal,
		type SeasonUnplacedReason,
	} from '#lib/training/season_plan.ts';
	import { createSeasonPlans, type SeasonCreated } from '#lib/training/season_create.ts';

	interface RaceRow {
		key: number;
		name: string;
		date: string;
		distance: number | null;
		priority: SeasonRacePriority;
		hours: number | null;
		minutes: number | null;
		seconds: number | null;
	}

	const METRES_PER_MILE = 1609.344;
	const unit = $derived(getUnit());
	const perUnit = $derived(unit === 'mi' ? METRES_PER_MILE : 1000);

	let viewerGender = $state<TrainingGender>(null);
	let viewerAge = $state<number | null>(null);
	let viewerExtraRecovery = $state(false);
	onMount(async () => {
		if (!auth.user) return;
		const c = await loadPlanCalibration(auth.user.id);
		viewerGender = c.gender;
		viewerAge = c.age;
		viewerExtraRecovery = c.extraRecovery;
	});

	const showAssistant = coachEnabled() && aiPlanEnabled();
	let request = $state('');
	let requestBusy = $state(false);
	let requestError = $state<{ key: MessageKey; consent: boolean } | null>(null);
	let requestFound = $state(false);
	let requestAssumptions = $state<MessageKey[]>([]);

	let nextKey = 0;
	let rows = $state<RaceRow[]>([]);
	let daysPerWeek = $state(4);
	let rowError = $state<string | null>(null);

	let built = $state<SeasonBuildResult | null>(null);
	let builtFor = $state('');
	const currentKey = $derived(JSON.stringify({ rows, daysPerWeek, unit }));
	const preview = $derived(built && builtFor === currentKey ? built : null);

	let creating = $state(false);
	let created = $state<SeasonCreated[]>([]);
	let failedIndex = $state<number | null>(null);
	let createError = $state<string | null>(null);
	let overlapping = $state<OverlapPlan[]>([]);

	const REQUEST_ERROR_KEYS: Record<PlanRequestErrorKind, MessageKey> = {
		consent: 'seasonPlanner.errorConsent',
		daily_limit: 'seasonPlanner.errorDailyLimit',
		not_understood: 'seasonPlanner.errorNotUnderstood',
		invalid: 'seasonPlanner.errorInvalid',
		not_authenticated: 'seasonPlanner.errorSignIn',
		unavailable: 'seasonPlanner.errorUnavailable',
	};
	const REFUSAL_KEYS: Record<SeasonRefusal, MessageKey> = {
		empty: 'seasonPlanner.refusedEmpty',
		invalid_race: 'seasonPlanner.refusedInvalid',
		race_not_ahead: 'seasonPlanner.refusedNotAhead',
		no_a_race: 'seasonPlanner.refusedNoA',
		first_too_soon: 'seasonPlanner.refusedFirstTooSoon',
		a_races_too_close: 'seasonPlanner.refusedTooClose',
	};
	const UNPLACED_KEYS: Record<SeasonUnplacedReason, MessageKey> = {
		before_first_plan: 'seasonPlanner.unplacedBefore',
		between_plans: 'seasonPlanner.unplacedBetween',
		after_last_plan: 'seasonPlanner.unplacedAfter',
		same_day: 'seasonPlanner.unplacedSameDay',
	};
	const PRIORITY_KEYS: Record<SeasonRacePriority, MessageKey> = {
		A: 'seasonPlanner.priorityA',
		B: 'seasonPlanner.priorityB',
		C: 'seasonPlanner.priorityC',
	};

	function todayIso(): string {
		return formatISO(new Date());
	}

	function fmtDay(iso: string): string {
		return parseISO(iso).toLocaleDateString(activeFormatLocale(), { dateStyle: 'medium' });
	}

	function rowFrom(race: SeasonRace): RaceRow {
		const goal = race.goalTimeSec;
		return {
			key: nextKey++,
			name: race.name.slice(0, SEASON_RACE_NAME_MAX),
			date: race.date,
			distance: Math.round((race.distanceM / perUnit) * 100) / 100,
			priority: race.priority,
			hours: goal ? Math.floor(goal / 3600) : null,
			minutes: goal ? Math.floor((goal % 3600) / 60) : null,
			seconds: goal ? goal % 60 : null,
		};
	}

	function addRace() {
		rows = [
			...rows,
			{ key: nextKey++, name: '', date: '', distance: null, priority: rows.length === 0 ? 'A' : 'B', hours: null, minutes: null, seconds: null },
		];
	}

	function removeRace(key: number) {
		rows = rows.filter((r) => r.key !== key);
	}

	async function findRaces() {
		const text = request.trim();
		if (!text || requestBusy) return;
		requestBusy = true;
		requestError = null;
		requestFound = false;
		requestAssumptions = [];
		try {
			const result = await requestSeasonRaces(text, todayIso());
			requestAssumptions = result.assumptions
				.map(seasonAssumptionMessageKey)
				.filter((k): k is MessageKey => k !== null);
			if (result.races.length === 0) {
				requestError = { key: 'seasonPlanner.errorNotUnderstood', consent: false };
				if (rows.length === 0) addRace();
				return;
			}
			rows = result.races.map(rowFrom);
			requestFound = true;
		} catch (e) {
			if (!(e instanceof PlanRequestError)) {
				console.error('Season request failed', { message: thrownMessage(e) });
			}
			const kind: PlanRequestErrorKind = e instanceof PlanRequestError ? e.kind : 'unavailable';
			requestError = { key: REQUEST_ERROR_KEYS[kind], consent: kind === 'consent' };
			if (rows.length === 0) addRace();
		} finally {
			requestBusy = false;
		}
	}

	function racesFromRows(): SeasonRace[] | null {
		const races: SeasonRace[] = [];
		for (let i = 0; i < rows.length; i++) {
			const r = rows[i];
			const goal = raceGoalInputSeconds(r.hours, r.minutes, r.seconds);
			if (!r.name.trim() || !r.date || r.distance == null || !(r.distance > 0) || !goal.ok) {
				rowError = m('seasonPlanner.rowInvalid', { n: i + 1 });
				return null;
			}
			races.push({
				name: r.name.trim(),
				date: r.date,
				distanceM: r.distance * perUnit,
				priority: r.priority,
				goalTimeSec: goal.seconds,
			});
		}
		return races;
	}

	function confirmRaces() {
		rowError = null;
		createError = null;
		created = [];
		failedIndex = null;
		const races = racesFromRows();
		if (!races) {
			built = null;
			return;
		}
		built = buildSeason({
			races,
			todayIso: todayIso(),
			daysPerWeek,
			gender: viewerGender,
			age: viewerAge,
			extraRecovery: viewerExtraRecovery,
		});
		builtFor = currentKey;
	}

	async function runCreate(firstOverlap: PlanOverlapChoice) {
		if (!preview?.ok || creating) return;
		const drafts = preview.plans;
		const from = failedIndex ?? 0;
		creating = true;
		createError = null;
		overlapping = [];
		try {
			const outcome = await createSeasonPlans(
				drafts,
				{ from, firstOverlap, created },
				{
					create: (d, overlap) =>
						createTrainingPlan({
							name: d.name,
							goalEvent: d.goalEvent,
							goalDistanceM: d.goalDistanceM,
							goalTimeSec: d.goalTimeSec,
							startDate: d.startDate,
							daysPerWeek: d.daysPerWeek,
							generated: d.generated,
							overlap,
						}),
					lookupOverlaps: (start, end) => fetchMyOverlappingActivePlans(start, end),
				}
			);
			if (outcome.kind === 'overlap') {
				overlapping = outcome.overlapping;
			} else if (outcome.kind === 'trimBlocked') {
				createError = trimBlockedMessage(outcome.overlapping, drafts[0].startDate);
			} else if (outcome.kind === 'blocked') {
				createError = m('seasonPlanner.blocked', {
					plan: drafts[outcome.index].name,
					existing: outcome.overlapping.map((p) => p.name).join(', '),
				});
			} else if (outcome.kind === 'failed') {
				created = outcome.created;
				failedIndex = outcome.failedIndex;
				const error = thrownMessage(outcome.error);
				const remaining = drafts.slice(outcome.failedIndex).map((d) => d.name).join(', ');
				createError =
					outcome.created.length === 0
						? m('seasonPlanner.failedNone', { error })
						: m('seasonPlanner.failedPartial', {
								created: outcome.created.map((c) => drafts[c.index].name).join(', '),
								failed: remaining,
								error,
							});
			} else {
				showToast(m('seasonPlanner.createdToast', { count: outcome.created.length }), 'success');
				await goto(`/plans/${outcome.created[0].id}`);
			}
		} catch (e) {
			console.error('Season create failed', { message: thrownMessage(e) });
			createError = m('seasonPlanner.failedNone', { error: thrownMessage(e) });
		} finally {
			creating = false;
		}
	}
</script>

<div class="season-planner">
	{#if showAssistant}
		<section class="panel" aria-labelledby="season-describe-title">
			<h2 id="season-describe-title">{m('seasonPlanner.describeTitle')}</h2>
			<p class="hint" id="season-describe-hint">{m('seasonPlanner.describeHint')}</p>
			<label class="visually-hidden" for="season-describe">{m('seasonPlanner.describeTitle')}</label>
			<textarea
				id="season-describe"
				bind:value={request}
				rows="3"
				maxlength="1200"
				placeholder={m('seasonPlanner.describePlaceholder')}
				aria-describedby="season-describe-hint"
				disabled={requestBusy}
			></textarea>
			<button
				type="button"
				class="btn btn-secondary"
				onclick={findRaces}
				disabled={requestBusy || !request.trim()}
				aria-busy={requestBusy}
			>
				{requestBusy ? m('seasonPlanner.describeWorking') : m('seasonPlanner.describeButton')}
			</button>
			{#if requestError}
				<p class="error" role="alert" data-testid="season-request-error">
					{m(requestError.key)}
					{#if requestError.consent}
						<a href={AI_CONSENT_HREF}>{m('seasonPlanner.errorConsentLink')}</a>
					{/if}
				</p>
			{/if}
			{#if requestFound || requestAssumptions.length > 0}
				<div class="note" role="status" data-testid="season-request-found">
					{#if requestFound}
						<p>{m('seasonPlanner.describeFound')}</p>
					{/if}
					{#if requestAssumptions.length > 0}
						<ul data-testid="season-assumptions">
							{#each requestAssumptions as key (key)}
								<li>{m(key)}</li>
							{/each}
						</ul>
					{/if}
				</div>
			{/if}
		</section>
	{/if}

	<section class="panel" aria-labelledby="season-races-title">
		<h2 id="season-races-title">{m('seasonPlanner.racesTitle')}</h2>
		<p class="hint" id="season-priority-hint">{m('seasonPlanner.racesHint')}</p>
		<p class="visually-hidden" id="season-name-hint">{m('seasonPlanner.raceNameHint')}</p>
		<p class="visually-hidden" id="season-date-hint">{m('seasonPlanner.raceDateHint')}</p>
		<p class="visually-hidden" id="season-distance-hint">{m('seasonPlanner.raceDistanceHint')}</p>
		<p class="visually-hidden" id="season-goal-hint">{m('seasonPlanner.raceGoalHint')}</p>
		{#if rows.length === 0}
			<p class="empty">{m('seasonPlanner.noRaces')}</p>
		{/if}
		<ol class="race-list">
			{#each rows as row, i (row.key)}
				<li>
					<fieldset class="race" data-testid="season-race">
						<legend>{m('seasonPlanner.raceLegend', { n: i + 1 })}</legend>
						<div class="race-grid">
							<div class="field name">
								<label for="season-race-{row.key}-name">{m('seasonPlanner.raceName')}</label>
								<input
									id="season-race-{row.key}-name"
									type="text"
									bind:value={row.name}
									maxlength={SEASON_RACE_NAME_MAX}
									aria-describedby="season-name-hint"
									required
								/>
							</div>
							<div class="field">
								<label for="season-race-{row.key}-date">{m('seasonPlanner.raceDate')}</label>
								<input id="season-race-{row.key}-date" type="date" bind:value={row.date} min={todayIso()} aria-describedby="season-date-hint" required />
							</div>
							<div class="field">
								<label for="season-race-{row.key}-distance">{m('seasonPlanner.raceDistance', { unit })}</label>
								<input
									id="season-race-{row.key}-distance"
									type="number"
									min="0.1"
									step="any"
									inputmode="decimal"
									bind:value={row.distance}
									aria-describedby="season-distance-hint"
									required
								/>
							</div>
							<div class="field">
								<label for="season-race-{row.key}-priority">{m('seasonPlanner.racePriority')}</label>
								<select id="season-race-{row.key}-priority" bind:value={row.priority} aria-describedby="season-priority-hint">
									{#each ['A', 'B', 'C'] as const as p (p)}
										<option value={p}>{m(PRIORITY_KEYS[p])}</option>
									{/each}
								</select>
							</div>
							<div class="field goal">
								<span class="goal-label" id="season-race-{row.key}-goal">{m('seasonPlanner.raceGoal')}</span>
								<div class="goal-inputs" role="group" aria-labelledby="season-race-{row.key}-goal" aria-describedby="season-goal-hint">
									<label class="visually-hidden" for="season-race-{row.key}-h">{m('seasonPlanner.goalHours')}</label>
									<input id="season-race-{row.key}-h" type="number" min="0" max={RACE_GOAL_MAX_HOURS} bind:value={row.hours} placeholder={m('seasonPlanner.goalHoursShort')} aria-describedby="season-goal-hint" />
									<span aria-hidden="true">:</span>
									<label class="visually-hidden" for="season-race-{row.key}-m">{m('seasonPlanner.goalMinutes')}</label>
									<input id="season-race-{row.key}-m" type="number" min="0" max="59" bind:value={row.minutes} placeholder={m('seasonPlanner.goalMinutesShort')} aria-describedby="season-goal-hint" />
									<span aria-hidden="true">:</span>
									<label class="visually-hidden" for="season-race-{row.key}-s">{m('seasonPlanner.goalSeconds')}</label>
									<input id="season-race-{row.key}-s" type="number" min="0" max="59" bind:value={row.seconds} placeholder={m('seasonPlanner.goalSecondsShort')} aria-describedby="season-goal-hint" />
								</div>
							</div>
						</div>
						<button type="button" class="btn btn-outline remove" onclick={() => removeRace(row.key)}>
							{m('seasonPlanner.removeRace', { n: i + 1 })}
						</button>
					</fieldset>
				</li>
			{/each}
		</ol>
		<button type="button" class="btn btn-secondary" onclick={addRace}>{m('seasonPlanner.addRace')}</button>

		<div class="field days">
			<label for="season-days">{m('seasonPlanner.daysPerWeek')}</label>
			<select id="season-days" bind:value={daysPerWeek} aria-describedby="season-days-hint">
				{#each [3, 4, 5, 6, 7] as d (d)}
					<option value={d}>{d}</option>
				{/each}
			</select>
			<p class="hint" id="season-days-hint">{m('seasonPlanner.daysPerWeekHint')}</p>
		</div>

		{#if rowError}
			<p class="error" role="alert">{rowError}</p>
		{/if}
		<button type="button" class="btn btn-primary" onclick={confirmRaces} disabled={rows.length === 0}>
			{m('seasonPlanner.previewButton')}
		</button>
	</section>

	{#if preview}
		<section class="panel" aria-labelledby="season-preview-title" data-testid="season-preview">
			<h2 id="season-preview-title">{m('seasonPlanner.previewTitle')}</h2>
			{#if !preview.ok}
				<p class="error" role="alert" data-testid="season-refusal">
					{m(REFUSAL_KEYS[preview.reason], { races: preview.races.join(', ') })}
				</p>
			{:else}
				<p class="hint">{m('seasonPlanner.previewHint', { count: preview.plans.length })}</p>
				<ol class="plan-list">
					{#each preview.plans as plan, i (plan.endDate)}
						<li class="plan" data-testid="season-plan">
							<h3>{plan.name}</h3>
							<p>{m('seasonPlanner.planWindow', { start: fmtDay(plan.startDate), end: fmtDay(plan.endDate), weeks: plan.weeks })}</p>
							<p>
								{m('seasonPlanner.planGoal', { distance: formatDistance(plan.goalDistanceM), date: fmtDay(plan.endDate) })}
								{#if plan.goalTimeSec}
									· {m('seasonPlanner.planGoalTime', { time: fmtHms(plan.goalTimeSec) })}
								{/if}
							</p>
							{#if plan.races.length > 0}
								<p class="sub">{m('seasonPlanner.planRaces')}</p>
								<ul>
									{#each plan.races as race (race.date)}
										<li>
											{m('seasonPlanner.planRaceLine', {
												priority: race.priority,
												name: race.name,
												date: fmtDay(race.date),
												distance: formatDistance(race.distanceM),
											})}
										</li>
									{/each}
								</ul>
							{/if}
							{#if created.some((c) => c.index === i)}
								<p class="done">{m('seasonPlanner.planCreated')}</p>
							{/if}
						</li>
						{#if preview.gaps[i]}
							<li class="gap">
								{m('seasonPlanner.recoveryLine', {
									race: preview.gaps[i].afterRace,
									days: preview.gaps[i].days,
									from: fmtDay(preview.gaps[i].from),
									to: fmtDay(preview.gaps[i].to),
								})}
							</li>
						{/if}
					{/each}
				</ol>
				{#if preview.unplaced.length > 0}
					<div class="note" data-testid="season-unplaced">
						<p class="sub">{m('seasonPlanner.unplacedTitle')}</p>
						<ul>
							{#each preview.unplaced as u (u.race.name + u.race.date)}
								<li>{m(UNPLACED_KEYS[u.reason], { race: u.race.name, date: fmtDay(u.race.date) })}</li>
							{/each}
						</ul>
						<p>{m('seasonPlanner.unplacedHint')}</p>
					</div>
				{/if}
				{#if createError}
					<p class="error" role="alert" data-testid="season-create-error">{createError}</p>
				{/if}
				<button
					type="button"
					class="btn btn-primary"
					onclick={() => runCreate('refuse')}
					disabled={creating}
					aria-busy={creating}
				>
					{#if creating}
						{m('seasonPlanner.creating')}
					{:else if failedIndex !== null}
						{m('seasonPlanner.retry')}
					{:else}
						{m('seasonPlanner.createButton', { count: preview.plans.length })}
					{/if}
				</button>
			{/if}
		</section>
	{/if}
</div>

{#if preview?.ok}
	<PlanOverlapDialog
		{overlapping}
		startDate={preview.plans[0].startDate}
		onchoose={(choice) => runCreate(choice)}
		oncancel={() => (overlapping = [])}
	/>
{/if}

<style>
	.season-planner {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		max-width: 48rem;
	}
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md) var(--space-lg);
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-sm);
	}
	h2 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0;
	}
	h3 {
		font-size: 1rem;
		font-weight: 700;
		margin: 0;
	}
	.hint,
	.empty {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0;
	}
	textarea {
		width: 100%;
		box-sizing: border-box;
		padding: 0.5rem 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font: inherit;
	}
	.race-list,
	.plan-list {
		list-style: none;
		margin: 0;
		padding: 0;
		width: 100%;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.race {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-sm) var(--space-md);
		margin: 0;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-sm);
	}
	legend {
		font-weight: 600;
		font-size: 0.9rem;
		padding: 0 var(--space-2xs);
	}
	.race-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(10rem, 100%), 1fr));
		gap: var(--space-sm);
		width: 100%;
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		min-width: 0;
	}
	.field.name {
		grid-column: 1 / -1;
	}
	.field label,
	.goal-label {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.field input,
	.field select {
		padding: 0.45rem 0.6rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 0.9rem;
		min-width: 0;
	}
	.goal-inputs {
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
	}
	.goal-inputs input {
		width: 4.5rem;
	}
	.days {
		margin-top: var(--space-sm);
	}
	.plan {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-sm) var(--space-md);
	}
	.plan p {
		margin: var(--space-2xs) 0 0;
		font-size: 0.9rem;
	}
	.plan ul,
	.note ul {
		margin: var(--space-2xs) 0 0;
		padding-inline-start: 1.2rem;
		font-size: 0.9rem;
	}
	.gap {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		padding-inline-start: var(--space-md);
	}
	.sub {
		font-weight: 600;
	}
	.done {
		font-weight: 600;
	}
	.note {
		background: var(--color-primary-light);
		border-radius: var(--radius-md);
		padding: var(--space-sm) var(--space-md);
		font-size: 0.9rem;
		width: 100%;
		box-sizing: border-box;
	}
	.note p {
		margin: 0;
	}
	.error {
		color: var(--color-danger-text);
		font-size: 0.9rem;
		margin: 0;
	}
</style>
