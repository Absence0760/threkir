<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import MetricLabel from '#lib/components/MetricLabel.svelte';
	import { fetchPlanRecapSources } from '#lib/core/data.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { formatDate, formatDateShort } from '#lib/format/time.ts';
	import { fmtKm } from '#lib/format/units.svelte.ts';
	import { fmtHms, todayISO } from '#lib/training/training.ts';
	import {
		assemblePlanRecap,
		type PlanRecap,
		type RecapPlan,
		type RecapWorkout
	} from '#lib/training/plan_recap.ts';

	/// The end-of-plan recap (issue #1186), for a plan the runner has filed as
	/// completed. Generic on purpose: a walk-run graduation header renders
	/// above it, and this card only reads the plan, its workouts and the
	/// runner's own runs and records.
	interface Props {
		plan: RecapPlan & { name: string };
		workouts: RecapWorkout[];
	}
	let { plan, workouts }: Props = $props();

	let sources = $state<Awaited<ReturnType<typeof fetchPlanRecapSources>> | null>(null);
	let loadError = $state<string | null>(null);

	async function load(): Promise<void> {
		loadError = null;
		try {
			sources = await fetchPlanRecapSources(plan.start_date, plan.end_date);
		} catch (e) {
			// L4: the plan page stands without its recap.
			console.error('fetchPlanRecapSources failed', { message: thrownMessage(e) });
			loadError = thrownMessage(e);
		}
	}
	onMount(load);

	const recap = $derived<PlanRecap | null>(
		sources === null
			? null
			: assemblePlanRecap({ plan, workouts, runs: sources.runs, records: sources.records, todayIso: todayISO() })
	);

	function timeValue(sec: number): string {
		const total = Math.round(sec / 60);
		return m('planRecap.timeValue', { h: Math.floor(total / 60), m: total % 60 });
	}

	const BRACKET_LABEL: Record<string, MessageKey> = {
		'1_mile': 'planRecap.bracketMile',
		'5k': 'planRecap.bracket5k',
		'8k': 'planRecap.bracket8k',
		'10k': 'planRecap.bracket10k',
		'12k': 'planRecap.bracket12k',
		half_marathon: 'planRecap.bracketHalf',
		marathon: 'planRecap.bracketMarathon'
	};

	function bracketLabel(key: string): string {
		const label = BRACKET_LABEL[key];
		return label ? m(label) : key;
	}

	const nextHref = $derived.by(() => {
		if (!recap) return '/plans/new?type=training';
		const params = new URLSearchParams({ type: 'training', start: recap.next.startIso });
		if (recap.next.seed5kSec != null) params.set('recent5k', String(recap.next.seed5kSec));
		return `/plans/new?${params.toString()}`;
	});
</script>

<section class="plan-recap" aria-labelledby="plan-recap-title" data-testid="plan-recap">
	<h3 id="plan-recap-title">
		<span class="material-symbols" aria-hidden="true">flag</span>
		{m('planRecap.title', { name: plan.name })}
	</h3>

	{#if loadError !== null}
		<p class="plan-recap-error" role="alert">{m('planRecap.loadFailed')}</p>
		<button type="button" class="btn btn-outline btn-sm" onclick={load}>{m('planRecap.retry')}</button>
	{:else if recap === null}
		<p class="plan-recap-muted" aria-busy="true">{m('planRecap.loading')}</p>
	{:else}
		<dl class="plan-recap-stats">
			<div data-testid="plan-recap-sessions">
				<dt>{m('planRecap.sessionsLabel')}</dt>
				<dd>
					<strong>{m('planRecap.sessionsValue', { done: recap.sessions.completed, total: recap.sessions.total })}</strong>
					<span>{m('planRecap.sessionsPct', { pct: recap.sessions.pct })}</span>
					{#if recap.sessions.missed > 0}
						<span>{m('planRecap.missed', { count: recap.sessions.missed })}</span>
					{/if}
					{#if recap.sessions.skipped > 0}
						<span>{m('planRecap.skipped', { count: recap.sessions.skipped })}</span>
					{/if}
				</dd>
			</div>
			<div data-testid="plan-recap-volume">
				<dt>{recap.volume.basis === 'time' ? m('planRecap.timeLabel') : m('planRecap.distanceLabel')}</dt>
				<dd>
					<strong>
						{m('planRecap.volumeValue', {
							done: recap.volume.basis === 'time' ? timeValue(recap.volume.done) : fmtKm(recap.volume.done),
							planned: recap.volume.basis === 'time' ? timeValue(recap.volume.planned) : fmtKm(recap.volume.planned)
						})}
					</strong>
				</dd>
			</div>
			{#if recap.longRuns.planned > 0}
				<div data-testid="plan-recap-long-runs">
					<dt>{m('planRecap.longRunsLabel')}</dt>
					<dd>
						<strong>{m('planRecap.sessionsValue', { done: recap.longRuns.done, total: recap.longRuns.planned })}</strong>
						{#if recap.longRuns.first != null && recap.longRuns.longest != null && recap.longRuns.longest > recap.longRuns.first}
							<span>{m('planRecap.longRunsRange', { first: fmtKm(recap.longRuns.first), longest: fmtKm(recap.longRuns.longest) })}</span>
						{:else if recap.longRuns.longest != null}
							<span>{m('planRecap.longRunsLongest', { longest: fmtKm(recap.longRuns.longest) })}</span>
						{/if}
					</dd>
				</div>
			{/if}
			{#if recap.race}
				<div data-testid="plan-recap-race">
					<dt>{recap.race.name ?? m('planRecap.raceLabel')} · {formatDateShort(recap.race.date)}</dt>
					<dd>
						{#if recap.race.run}
							<strong>
								{recap.race.run.isDnf
									? m('planRecap.raceDnf')
									: m('planRecap.raceRun', {
											time: fmtHms(recap.race.run.durationS),
											distance: fmtKm(recap.race.run.distanceM)
										})}
							</strong>
							{#if recap.race.vdot != null}
								<span><MetricLabel metric="vdot" /> {recap.race.vdot.toFixed(1)}</span>
							{/if}
						{:else if recap.race.raced}
							<strong>{m('planRecap.raceNoRun')}</strong>
						{:else}
							<strong>{m('planRecap.raceNotRun')}</strong>
						{/if}
					</dd>
				</div>
			{/if}
		</dl>

		<h4>{m('planRecap.recordsLabel')}</h4>
		{#if recap.records.length === 0}
			<p class="plan-recap-muted" data-testid="plan-recap-no-records">{m('planRecap.recordsNone')}</p>
		{:else}
			<ul class="plan-recap-records" data-testid="plan-recap-records">
				{#each recap.records as r (r.distance)}
					<li>
						<span class="material-symbols" aria-hidden="true">emoji_events</span>
						<span>{bracketLabel(r.distance)}</span>
						<strong>{fmtHms(r.timeS)}</strong>
						<span class="plan-recap-muted">{formatDateShort(r.date)}</span>
					</li>
				{/each}
			</ul>
		{/if}

		<h4>{m('planRecap.nextTitle')}</h4>
		<div class="plan-recap-next" data-testid="plan-recap-next">
			{#if recap.next.recovery}
				<p data-testid="plan-recap-recovery">
					{m('planRecap.recovery', { days: recap.next.recovery.days, date: formatDate(recap.next.recovery.untilIso) })}
				</p>
			{/if}
			<p>
				{recap.next.seed5kSec != null
					? m('planRecap.nextPlanSeeded', {
							date: formatDate(recap.next.startIso),
							time: fmtHms(recap.next.seed5kSec)
						})
					: m('planRecap.nextPlan', { date: formatDate(recap.next.startIso) })}
			</p>
			<a class="btn btn-primary btn-sm" href={nextHref} data-testid="plan-recap-next-plan">
				{m('planRecap.nextPlanCta')}
				<span class="material-symbols" aria-hidden="true">arrow_forward</span>
			</a>
		</div>
	{/if}
</section>

<style>
	.plan-recap {
		margin: var(--space-md) 0;
		padding: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid color-mix(in srgb, var(--color-primary) 30%, var(--color-border));
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.plan-recap h3 {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		margin: 0 0 var(--space-md);
		font-size: 1.1rem;
	}
	.plan-recap h3 .material-symbols {
		color: var(--color-primary);
	}
	.plan-recap h4 {
		margin: var(--space-lg) 0 var(--space-xs);
		font-size: 0.95rem;
	}
	.plan-recap-stats {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(11rem, 1fr));
		gap: var(--space-md);
		margin: 0;
	}
	.plan-recap-stats dt {
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
		overflow-wrap: anywhere;
	}
	.plan-recap-stats dd {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		margin: var(--space-2xs) 0 0;
	}
	.plan-recap-stats dd span {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.plan-recap-records {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.plan-recap-records li {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
	}
	.plan-recap-records .material-symbols {
		color: var(--color-primary);
	}
	.plan-recap-muted {
		color: var(--color-text-secondary);
		margin: 0;
	}
	.plan-recap-error {
		color: var(--color-danger-text);
		margin: 0 0 var(--space-sm);
	}
	.plan-recap-next p {
		margin: 0 0 var(--space-sm);
	}
	.plan-recap-next .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
</style>
