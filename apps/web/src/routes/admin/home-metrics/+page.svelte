<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import {
		amIAdmin,
		fetchCoachEngagementWeeks,
		fetchPlanCompletionWeeks,
		type CoachEngagementWeek,
		type PlanCompletionWeek,
	} from '#lib/core/data.ts';
	import { m as t, currentLocale } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { HOME_REDESIGN_DATE, formatPct, formatWeekStart, isCurrentWeek, weekContains } from './home_metrics.ts';

	let isAdmin = $state<boolean | null>(null);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let coachWeeks = $state<CoachEngagementWeek[]>([]);
	let planWeeks = $state<PlanCompletionWeek[]>([]);
	const now = new Date();

	const coachEmpty = $derived(coachWeeks.every((w) => w.active_runners === 0));
	const planEmpty = $derived(planWeeks.every((w) => w.scheduled_days === 0));

	function weekLabel(weekStart: string): string {
		return formatWeekStart(weekStart, currentLocale());
	}

	function pct(value: number | null): string {
		return formatPct(value, currentLocale()) ?? t('admin.homeMetrics.noPct');
	}

	function isRedesign(weekStart: string): boolean {
		return weekContains(weekStart, HOME_REDESIGN_DATE);
	}

	async function load() {
		loadError = null;
		try {
			[coachWeeks, planWeeks] = await Promise.all([fetchCoachEngagementWeeks(), fetchPlanCompletionWeeks()]);
		} catch (e) {
			loadError = t('admin.homeMetrics.loadFailed', { error: errorCopy(e, t, 'admin.homeMetrics.loadFailed') });
		}
	}

	onMount(async () => {
		await auth.ready();
		isAdmin = await amIAdmin();
		if (isAdmin) await load();
		loading = false;
	});
</script>

<svelte:head><title>{t('admin.homeMetrics.title')}</title></svelte:head>

{#snippet weekCell(weekStart: string)}
	<th scope="row">
		{weekLabel(weekStart)}
		{#if isRedesign(weekStart)}
			<span class="chip chip-accent" data-testid="home-metrics-redesign">{t('admin.homeMetrics.redesign')}</span>
		{/if}
		{#if isCurrentWeek(weekStart, now)}
			<span class="chip">{t('admin.homeMetrics.inProgress')}</span>
		{/if}
	</th>
{/snippet}

<div class="page">
	{#if loading}
		<p class="muted">…</p>
	{:else if !isAdmin}
		<div class="card-elevated not-authorized" data-testid="home-metrics-not-authorized">
			<h1>{t('admin.homeMetrics.notAuthorized')}</h1>
			<p class="muted">{t('admin.homeMetrics.notAuthorizedHint')}</p>
		</div>
	{:else}
		<header>
			<h1>{t('admin.homeMetrics.title')}</h1>
			<p class="muted">{t('admin.homeMetrics.subtitle')}</p>
			<p class="muted note">
				{t('admin.homeMetrics.redesignNote', { date: weekLabel(HOME_REDESIGN_DATE) })}
			</p>
		</header>

		{#if loadError}
			<EmptyState icon="error" tone="danger" title={loadError} role="alert" data-testid="home-metrics-load-error" />
		{:else}
			<section class="card-elevated" aria-labelledby="home-metrics-coach-heading">
				<h2 id="home-metrics-coach-heading">{t('admin.homeMetrics.coachHeading')}</h2>
				<p class="muted hint">{t('admin.homeMetrics.coachHint')}</p>
				<p class="muted hint" data-testid="home-metrics-coach-note">{t('admin.homeMetrics.coachEntryNote')}</p>
				{#if coachEmpty}
					<EmptyState
						icon="chat"
						headingLevel={3}
						title={t('admin.homeMetrics.coachEmpty')}
						data-testid="home-metrics-coach-empty"
					/>
				{:else}
					<div class="table-scroll">
						<table data-testid="home-metrics-coach">
							<thead>
								<tr>
									<th scope="col">{t('admin.homeMetrics.colWeek')}</th>
									<th scope="col" class="num">{t('admin.homeMetrics.colActive')}</th>
									<th scope="col" class="num">{t('admin.homeMetrics.colCoached')}</th>
									<th scope="col" class="num">{t('admin.homeMetrics.colPct')}</th>
								</tr>
							</thead>
							<tbody>
								{#each coachWeeks as w (w.week_start)}
									<tr
										class:redesign={isRedesign(w.week_start)}
										data-testid="home-metrics-coach-row"
										data-week={w.week_start}
									>
										{@render weekCell(w.week_start)}
										<td class="num">{w.active_runners}</td>
										<td class="num">{w.coached_runners}</td>
										<td class="num pct">{pct(w.coached_pct)}</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
				{/if}
			</section>

			<section class="card-elevated" aria-labelledby="home-metrics-plan-heading">
				<h2 id="home-metrics-plan-heading">{t('admin.homeMetrics.planHeading')}</h2>
				<p class="muted hint">{t('admin.homeMetrics.planHint')}</p>
				{#if planEmpty}
					<EmptyState
						icon="event_available"
						headingLevel={3}
						title={t('admin.homeMetrics.planEmpty')}
						data-testid="home-metrics-plan-empty"
					/>
				{:else}
					<div class="table-scroll">
						<table data-testid="home-metrics-plan">
							<thead>
								<tr>
									<th scope="col">{t('admin.homeMetrics.colWeek')}</th>
									<th scope="col" class="num">{t('admin.homeMetrics.colScheduled')}</th>
									<th scope="col" class="num">{t('admin.homeMetrics.colCompleted')}</th>
									<th scope="col" class="num">{t('admin.homeMetrics.colPct')}</th>
								</tr>
							</thead>
							<tbody>
								{#each planWeeks as w (w.week_start)}
									<tr
										class:redesign={isRedesign(w.week_start)}
										data-testid="home-metrics-plan-row"
										data-week={w.week_start}
									>
										{@render weekCell(w.week_start)}
										<td class="num">{w.scheduled_days}</td>
										<td class="num">{w.completed_days}</td>
										<td class="num pct">{pct(w.completed_pct)}</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
				{/if}
			</section>
		{/if}
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	header h1,
	.not-authorized h1 {
		margin: 0 0 0.25rem;
		font-size: 1.4rem;
	}
	header p {
		margin: 0 0 var(--space-xs);
	}
	h2 {
		margin: 0 0 var(--space-xs);
		font-size: 1.05rem;
	}
	section {
		padding: var(--space-lg);
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.hint,
	.note {
		font-size: 0.85rem;
	}
	.hint {
		margin: 0 0 var(--space-sm);
	}
	.not-authorized {
		padding: var(--space-xl);
		text-align: center;
	}
	.table-scroll {
		overflow-x: auto;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.9rem;
	}
	th,
	td {
		padding: var(--space-sm);
		border-bottom: 1px solid var(--color-border);
		text-align: start;
		vertical-align: top;
	}
	thead th {
		color: var(--color-text-secondary);
		font-weight: 600;
	}
	tbody th {
		font-weight: 500;
		white-space: nowrap;
	}
	tr.redesign th,
	tr.redesign td {
		border-top: 2px solid var(--color-primary);
	}
	.num {
		text-align: end;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.pct {
		font-weight: 600;
	}
	.chip {
		display: inline-block;
		margin-inline-start: 0.3rem;
		padding: 0.1rem 0.45rem;
		border-radius: var(--radius-sm);
		background: var(--chip-bg);
		color: var(--chip-fg);
		font-size: 0.78rem;
		font-weight: 500;
	}
	.chip-accent {
		background: var(--color-primary);
		color: var(--color-on-primary);
	}
</style>
