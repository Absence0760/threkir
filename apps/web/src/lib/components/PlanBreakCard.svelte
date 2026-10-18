<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import { reschedulePlanAfterBreak } from '#lib/core/data.ts';
	import { PLAN_BREAK_DISMISSED_KEY } from '#lib/core/plan_break_context.ts';
	import type { BreakContext } from '#lib/training/plan_break_state.ts';
	import { isPlanOverlapError, thrownMessage } from '#lib/core/supabase_error.ts';
	import { formatDate } from '#lib/format/time.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { updateUniversal } from '#lib/settings/settings.ts';
	import {
		planBreakChange,
		type BreakChange,
		type BreakPlan,
		type BreakWeek,
		type BreakWorkout,
		type PlanBreak
	} from '#lib/training/plan_break.ts';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';

	/// A break of a week or more in the runner's own active plan (decisions
	/// § 2128): one calm offer to run the missed weeks again, previewed and
	/// applied in one transaction, or to keep the plan as it is. The host
	/// owns the break state (`breakState`) because the offer outranks the
	/// missed-workout prompt and the plan nudge, and renders this only while
	/// `showing`, for the plan's owner. `onanswered` hands the host the
	/// answer so it can stop showing the offer.
	interface Props {
		plan: BreakPlan & { id: string };
		weeks: BreakWeek[];
		workouts: BreakWorkout[];
		today: string;
		found: PlanBreak;
		context: BreakContext;
		onanswered: (pref: { plan_id: string; from: string; until: string }) => void;
		onapplied: () => void | Promise<void>;
	}
	let { plan, weeks, workouts, today, found, context, onanswered, onapplied }: Props = $props();

	let busy = $state(false);
	let weeksChoice = $state(1);
	let pending = $state<BreakChange | null>(null);

	$effect(() => {
		weeksChoice = found.maxWeeks;
	});

	let input = $derived({ plan, weeks, workouts, runDatesIso: context.runDatesIso, todayIso: today });
	let answer = $derived({ plan_id: plan.id, from: found.fromIso, until: today });

	function propose(k: number): void {
		if (busy) return;
		let change: BreakChange | null;
		try {
			change = planBreakChange(input, k);
		} catch (e) {
			console.error('plan break: working out the change failed', e);
			change = null;
		}
		if (!change) {
			showToast(m('planBreak.unavailable'), 'error');
			return;
		}
		pending = change;
	}

	function preview(change: BreakChange): string {
		const lines = [m('planBreak.previewRepeat', { n: change.weeks })];
		if (change.dropWeekIds.length > 0) {
			lines.push(m('planBreak.previewDropped', { n: change.dropWeekIds.length }));
			lines.push(m('planBreak.previewRaceDay', { date: formatDate(change.endIso) }));
		} else {
			lines.push(m('planBreak.previewEnd', { date: formatDate(change.endIso) }));
		}
		lines.push(m('planBreak.previewPast'));
		return lines.join(' ');
	}

	async function apply(): Promise<void> {
		const change = pending;
		if (!change || busy) return;
		busy = true;
		try {
			await reschedulePlanAfterBreak(plan.id, change, found.fromIso, today);
			pending = null;
			onanswered(answer);
			showToast(m('planBreak.applied', { date: formatDate(change.endIso) }));
			await onapplied();
		} catch (e) {
			pending = null;
			showToast(
				isPlanOverlapError(e)
					? m('planDetail.planOverlap')
					: m('planBreak.failed', { error: thrownMessage(e) }),
				'error'
			);
		} finally {
			busy = false;
		}
	}

	async function dismiss(): Promise<void> {
		const uid = auth.user?.id;
		if (!uid || busy) return;
		busy = true;
		try {
			await updateUniversal(uid, { [PLAN_BREAK_DISMISSED_KEY]: answer });
			onanswered(answer);
		} catch (e) {
			showToast(m('planBreak.dismissFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			busy = false;
		}
	}
</script>

<section class="plan-break" aria-labelledby="plan-break-title" data-testid="plan-break-card">
	<span class="material-symbols plan-break-icon" aria-hidden="true">history</span>
	<div class="plan-break-body">
		<h3 id="plan-break-title">{m('planBreak.title')}</h3>
		<p>{m('planBreak.body', { days: found.days, date: formatDate(found.fromIso) })}</p>
		<p class="plan-break-hint">
			{found.raceDateIso
				? m('planBreak.hintRace', { date: formatDate(found.raceDateIso) })
				: m('planBreak.hintNoRace')}
		</p>
		<div class="plan-break-actions">
			<button
				type="button"
				class="btn btn-primary btn-sm"
				disabled={busy}
				data-testid="plan-break-repeat"
				onclick={() => propose(1)}
			>
				{m('planBreak.repeat')}
			</button>
			{#if found.maxWeeks >= 2}
				<span class="plan-break-weeks">
					<label for="plan-break-weeks">{m('planBreak.weeksLabel')}</label>
					<input
						id="plan-break-weeks"
						type="number"
						min="1"
						max={found.maxWeeks}
						step="1"
						bind:value={weeksChoice}
						data-testid="plan-break-weeks"
					/>
					<button
						type="button"
						class="btn btn-secondary btn-sm"
						disabled={busy}
						data-testid="plan-break-more"
						onclick={() => propose(weeksChoice)}
					>
						{found.raceDateIso ? m('planBreak.shortenBuild') : m('planBreak.pushBack')}
					</button>
				</span>
			{/if}
			<button
				type="button"
				class="btn btn-outline btn-sm"
				disabled={busy}
				data-testid="plan-break-dismiss"
				onclick={dismiss}
			>
				{m('planBreak.dismiss')}
			</button>
		</div>
	</div>
</section>

<ConfirmDialog
	open={pending != null}
	title={m('planBreak.confirmTitle')}
	message={pending ? preview(pending) : ''}
	confirmLabel={m('planBreak.confirmApply')}
	onconfirm={apply}
	oncancel={() => (pending = null)}
	data-testid="plan-break-confirm"
/>

<style>
	.plan-break {
		display: flex;
		align-items: flex-start;
		gap: var(--space-md);
		margin: var(--space-md) 0;
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.plan-break-icon {
		color: var(--color-primary);
	}
	.plan-break-body {
		flex: 1;
		min-width: 0;
	}
	.plan-break-body h3 {
		margin: 0;
		font-size: 1rem;
	}
	.plan-break-body p {
		margin: var(--space-xs) 0 0;
		color: var(--color-text-secondary);
	}
	.plan-break-actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin-top: var(--space-md);
	}
	.plan-break-weeks {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.plan-break-weeks input {
		width: 4rem;
	}
</style>
