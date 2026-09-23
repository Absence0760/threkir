<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { activeFormatLocale } from '$lib/format/time';
	import { fmtKm, formatDistance } from '$lib/format/units.svelte';
	import { workoutKindLabel } from '$lib/training/workout_labels';
	import { weekLead, type LeadActivity } from '$lib/training/week_lead';
	import type { WeekStart } from '$lib/training/current_week';
	import type { PlanWorkout } from '$lib/types';

	interface Props {
		activities: LeadActivity[];
		/// The active plan's workouts, or null when there is no active plan —
		/// which is what hides the next-session half, not an empty list.
		planWorkouts: PlanWorkout[] | null;
		weekStart: WeekStart;
		now: Date;
		onopensession?: (w: PlanWorkout) => void;
	}
	let { activities, planWorkouts, weekStart, now, onopensession }: Props = $props();

	let lead = $derived(weekLead({ activities, planWorkouts, weekStart, now }));

	let planPct = $derived(
		lead.comparison?.kind === 'plan'
			? Math.min(100, Math.round((lead.distanceM / lead.comparison.targetM) * 100))
			: null,
	);

	function whenLabel(iso: string, inDays: number | null): string {
		if (inDays === 0) return m('dash.today');
		if (inDays === 1) return m('dash.leadTomorrow');
		const [y, mo, d] = iso.split('-').map(Number);
		return new Date(y, (mo ?? 1) - 1, d ?? 1).toLocaleDateString(activeFormatLocale(), {
			weekday: 'short',
			day: 'numeric',
			month: 'short',
		});
	}
</script>

<section class="week-lead" aria-labelledby="week-lead-title" data-testid="dash-week-lead">
	<div class="week-lead-week">
		<h2 id="week-lead-title">{m('dash.leadTitle')}</h2>
		{#if lead.count === 0}
			<p class="week-lead-value week-lead-value-empty">{m('dash.weekEmptyValue')}</p>
		{:else}
			<p class="week-lead-value" data-testid="dash-week-lead-distance">
				{formatDistance(lead.distanceM)}
				<span class="week-lead-count">
					{lead.count === 1
						? m('dash.activityCountOne', { n: lead.count })
						: m('dash.activityCountOther', { n: lead.count })}
				</span>
			</p>
		{/if}
		{#if lead.comparison?.kind === 'plan'}
			<div
				class="week-lead-meter"
				role="progressbar"
				aria-valuemin="0"
				aria-valuemax="100"
				aria-valuenow={planPct}
				aria-label={m('dash.leadPlanProgressAria')}
			>
				<span class="week-lead-meter-fill" style="width: {planPct}%"></span>
			</div>
			<p class="week-lead-vs" data-testid="dash-week-lead-vs">
				{m('dash.leadVsPlan', {
					done: formatDistance(lead.distanceM),
					target: formatDistance(lead.comparison.targetM),
				})}
			</p>
		{:else if lead.comparison?.kind === 'average'}
			<p class="week-lead-vs" data-testid="dash-week-lead-vs">
				{lead.comparison.weeks === 1
					? m('dash.leadVsAverageOne', { avg: formatDistance(lead.comparison.averageM) })
					: m('dash.leadVsAverageOther', {
							weeks: lead.comparison.weeks,
							avg: formatDistance(lead.comparison.averageM),
						})}
			</p>
		{/if}
	</div>

	{#if planWorkouts}
		<div class="week-lead-next" data-testid="dash-week-lead-next">
			<span class="week-lead-kicker">{m('dash.leadNextSession')}</span>
			{#if lead.next}
				{@const w = lead.next}
				<button type="button" class="week-lead-session" onclick={() => onopensession?.(w)}>
					<span class="material-symbols" aria-hidden="true">directions_run</span>
					<span class="week-lead-session-body">
						<span class="week-lead-session-when">{whenLabel(w.scheduled_date, lead.nextInDays)}</span>
						<span class="week-lead-session-kind">
							{workoutKindLabel(w.kind)}{#if w.target_distance_m != null}
								&middot; {fmtKm(w.target_distance_m)}{/if}
						</span>
					</span>
					<span class="material-symbols" aria-hidden="true">chevron_right</span>
				</button>
			{:else}
				<p class="week-lead-quiet">{m('dash.leadNoNextSession')}</p>
			{/if}
		</div>
	{/if}

	<div class="week-lead-actions">
		<a class="btn btn-primary" href="/runs/new" data-testid="dash-week-lead-add">
			<span class="material-symbols" aria-hidden="true">add</span>
			{m('dash.addARun')}
		</a>
	</div>
</section>

<style>
	.week-lead {
		display: grid;
		grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr) auto;
		align-items: center;
		gap: var(--space-md) var(--space-lg);
		padding: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}
	.week-lead h2 {
		margin: 0;
		font-size: 0.8rem;
		font-weight: 600;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--color-text-secondary);
	}
	.week-lead-week,
	.week-lead-next {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		min-width: 0;
	}
	.week-lead-value {
		margin: 0;
		font-size: 1.6rem;
		font-weight: 700;
		color: var(--color-text);
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: var(--space-xs) var(--space-sm);
	}
	.week-lead-value-empty {
		font-size: 1.15rem;
		color: var(--color-text-secondary);
	}
	.week-lead-count {
		font-size: 0.9rem;
		font-weight: 500;
		color: var(--color-text-secondary);
	}
	.week-lead-meter {
		height: 6px;
		border-radius: var(--radius-pill);
		background: var(--color-border);
		overflow: hidden;
	}
	.week-lead-meter-fill {
		display: block;
		height: 100%;
		background: var(--color-primary);
	}
	.week-lead-vs,
	.week-lead-quiet {
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.week-lead-kicker {
		font-size: 0.8rem;
		font-weight: 600;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--color-text-secondary);
	}
	.week-lead-session {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		width: 100%;
		min-height: 44px;
		padding: var(--space-sm) var(--space-md);
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		color: var(--color-text);
		font: inherit;
		text-align: start;
		cursor: pointer;
	}
	.week-lead-session:hover {
		border-color: var(--color-primary);
	}
	.week-lead-session > .material-symbols:first-child {
		color: var(--color-primary);
	}
	.week-lead-session-body {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-width: 0;
	}
	.week-lead-session-when {
		font-weight: 600;
	}
	.week-lead-session-kind {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.week-lead-actions {
		display: flex;
		justify-content: flex-end;
	}

	@media (max-width: 720px) {
		.week-lead {
			grid-template-columns: minmax(0, 1fr);
			padding: var(--space-md);
		}
		.week-lead-actions {
			justify-content: stretch;
		}
		.week-lead-actions .btn {
			flex: 1;
			justify-content: center;
		}
	}
</style>
