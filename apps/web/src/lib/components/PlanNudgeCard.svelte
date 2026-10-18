<script lang="ts">
	import { goto } from '$app/navigation';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { updateUniversal } from '#lib/settings/settings.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { formatISO, isWorkoutCompleted, isWorkoutSkipped } from '#lib/training/training.ts';
	import {
		buildReplanWeeks,
		DISMISSED_NUDGES_KEY,
		planNudge,
		withDismissedNudge,
		type PlanNudge
	} from '#lib/training/plan_nudges.ts';
	import type { PlanWeek, PlanWorkout, TrainingPlan } from '#lib/types.ts';

	/// The one plan card Home shows unprompted (`planNudge`): an existing
	/// re-plan proposal worth a look (the anchored one opens through the plain
	/// re-plan review, which prefers it), or the rest-day-runs note. Review opens
	/// the plan's own preview; nothing here proposes or writes a change. Both
	/// Review and Dismiss file the occurrence in `plan_nudges_dismissed`, so
	/// it is not offered again on any device until a new week brings one.
	interface Props {
		plan: TrainingPlan;
		weeks: PlanWeek[];
		workouts: PlanWorkout[];
		runs: { started_at: string; distance_m: number | null }[];
		dismissed: string[];
		today: string;
		/// The host's veto: true renders nothing, whatever the plan says
		/// (another card that outranks this one is showing).
		hidden?: boolean;
	}
	let { plan, weeks, workouts, runs, dismissed, today, hidden = false }: Props = $props();

	let filed = $state<string[] | null>(null);
	let saved = $derived(filed ?? dismissed);

	/// Auxiliary (L4): a malformed row must cost the card, never Home.
	let nudge = $derived.by((): PlanNudge | null => {
		if (hidden) return null;
		try {
			const byWeek = new Map<string, PlanWorkout[]>();
			for (const w of workouts) {
				const list = byWeek.get(w.week_id) ?? [];
				list.push(w);
				byWeek.set(w.week_id, list);
			}
			const runRows = runs.map((r) => ({
				date: formatISO(new Date(r.started_at)),
				distanceM: r.distance_m ?? 0
			}));
			const replanWeeks = buildReplanWeeks({
				startDate: plan.start_date,
				today,
				runs: runRows,
				weeks: weeks.map((w) => ({
					weekIndex: w.week_index,
					phase: w.phase,
					targetVolumeM: w.target_volume_m,
					workouts: (byWeek.get(w.id) ?? []).map((x) => ({
						id: x.id,
						scheduledDate: x.scheduled_date,
						kind: x.kind,
						targetDistanceM: x.target_distance_m,
						completed: isWorkoutCompleted(x),
						skipped: isWorkoutSkipped(x),
						answered: x.missed_ack_at != null
					}))
				}))
			});
			return planNudge({
				planId: plan.id,
				status: plan.status,
				isTemplate: plan.is_template,
				startDate: plan.start_date,
				endDate: plan.end_date,
				today,
				weeks: replanWeeks,
				runDates: runRows.map((r) => r.date),
				dismissed: saved
			});
		} catch (e) {
			console.error('Working out the plan card failed', e);
			return null;
		}
	});

	async function file(key: string): Promise<boolean> {
		const uid = auth.user?.id;
		if (!uid) return false;
		const previous = saved;
		const next = withDismissedNudge(previous, key);
		filed = next;
		try {
			await updateUniversal(uid, { [DISMISSED_NUDGES_KEY]: next });
			return true;
		} catch (e) {
			filed = previous;
			console.error('Saving the dismissed plan card failed', e);
			return false;
		}
	}

	async function dismiss(n: PlanNudge): Promise<void> {
		if (!(await file(n.key))) showToast(m('planNudge.dismissFailed'), 'error');
	}

	function review(n: PlanNudge): void {
		void file(n.key);
		const which = n.kind === 'adaptive_under' ? 'adaptive' : 'replan';
		void goto(`/plans/${plan.id}?review=${which}`);
	}
</script>

{#if nudge}
	{@const n = nudge}
	<section class="plan-nudge" aria-labelledby="plan-nudge-title" data-testid="plan-nudge" data-kind={n.kind}>
		<span class="material-symbols plan-nudge-icon" aria-hidden="true">
			{n.kind === 'rest_day_runs' ? 'self_improvement' : 'tune'}
		</span>
		<div class="plan-nudge-body">
			<h3 id="plan-nudge-title">
				{n.kind === 'anchor_under'
					? m('planNudge.anchorUnderTitle')
					: n.kind === 'anchor_return'
						? m('planNudge.anchorReturnTitle')
						: n.kind === 'adaptive_under'
							? m('planNudge.underTitle')
							: n.kind === 'ease_over'
								? m('planNudge.easeTitle')
								: m('planNudge.restTitle')}
			</h3>
			<p>
				{n.kind === 'anchor_under'
					? m('planNudge.anchorUnderBody')
					: n.kind === 'anchor_return'
						? m('planNudge.anchorReturnBody', { n: n.weeks })
						: n.kind === 'adaptive_under'
							? m('planNudge.underBody', { n: n.weeks, total: n.ofWeeks })
							: n.kind === 'ease_over'
								? m('planNudge.easeBody')
								: m('planNudge.restBody', { n: n.weeks, total: n.ofWeeks })}
			</p>
		</div>
		<div class="plan-nudge-actions">
			<button
				type="button"
				class="btn btn-secondary btn-sm"
				aria-label={m('planNudge.dismissAria')}
				onclick={() => dismiss(n)}
			>
				{m('planNudge.dismiss')}
			</button>
			{#if n.kind !== 'rest_day_runs'}
				<button type="button" class="btn btn-primary btn-sm" onclick={() => review(n)}>
					{m('planNudge.review')}
				</button>
			{/if}
		</div>
	</section>
{/if}

<style>
	.plan-nudge {
		display: flex;
		align-items: flex-start;
		gap: var(--space-md);
		flex-wrap: wrap;
		padding: var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.plan-nudge-icon {
		color: var(--color-primary);
	}
	.plan-nudge-body {
		flex: 1 1 10rem;
		min-width: 0;
		overflow-wrap: anywhere;
	}
	.plan-nudge-body h3 {
		margin: 0;
		font-size: 1rem;
	}
	.plan-nudge-body p {
		margin: var(--space-xs) 0 0;
		color: var(--color-text-secondary);
	}
	.plan-nudge-actions {
		display: flex;
		gap: var(--space-sm);
		align-self: center;
		flex-wrap: wrap;
	}
</style>
