<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import { fetchRuns, reschedulePlanAfterBreak } from '#lib/core/data.ts';
	import { isPlanOverlapError, thrownMessage } from '#lib/core/supabase_error.ts';
	import { formatDate } from '#lib/format/time.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { effective, loadSettings, updateUniversal } from '#lib/settings/settings.ts';
	import { formatISO, parseISO } from '#lib/training/training.ts';
	import {
		detectPlanBreak,
		isBreakDismissed,
		planBreakChange,
		type BreakChange,
		type BreakPlan,
		type BreakWeek,
		type BreakWorkout
	} from '#lib/training/plan_break.ts';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';

	/// A break of a week or more in the runner's own active plan (decisions
	/// § 2128): one calm offer to run the missed weeks again, previewed and
	/// applied in one transaction, or to keep the plan as it is. The host
	/// renders it only for the plan's owner.
	interface Props {
		plan: BreakPlan & { id: string };
		weeks: BreakWeek[];
		workouts: BreakWorkout[];
		today: string;
		onapplied: () => void | Promise<void>;
	}
	let { plan, weeks, workouts, today, onapplied }: Props = $props();

	let runDates = $state<string[] | null>(null);
	let dismissedPref = $state<unknown>(undefined);
	let hidden = $state(false);
	let busy = $state(false);
	let weeksChoice = $state(1);
	let pending = $state<BreakChange | null>(null);

	$effect(() => {
		const day = today;
		const uid = auth.user?.id;
		if (!uid) return;
		let stale = false;
		runDates = null;
		fetchRuns({
			limit: 1,
			columns: ['started_at'] as const,
			startedAtBefore: parseISO(day).toISOString(),
			throwOnError: true
		})
			.then((rows) => {
				if (!stale) runDates = rows.map((r) => formatISO(new Date(r.started_at)));
			})
			.catch((e) => console.error('plan break: latest run read failed', e));
		loadSettings(uid)
			.then((s) => {
				if (!stale) dismissedPref = effective<unknown>(s, 'plan_break_dismissed') ?? null;
			})
			.catch((e) => console.error('plan break: settings read failed', e));
		return () => {
			stale = true;
		};
	});

	let input = $derived(
		runDates == null ? null : { plan, weeks, workouts, runDatesIso: runDates, todayIso: today }
	);
	let found = $derived(input ? detectPlanBreak(input) : null);
	let shown = $derived(
		found != null &&
			!hidden &&
			dismissedPref !== undefined &&
			!isBreakDismissed(dismissedPref, plan.id, found.fromIso)
	);

	$effect(() => {
		if (found) weeksChoice = found.maxWeeks;
	});

	function propose(k: number): void {
		if (!input || busy) return;
		const change = planBreakChange(input, k);
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
		if (!change || !found || busy) return;
		busy = true;
		try {
			await reschedulePlanAfterBreak(plan.id, change, found.fromIso, today);
			pending = null;
			hidden = true;
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
		if (!uid || !found || busy) return;
		busy = true;
		try {
			await updateUniversal(uid, { plan_break_dismissed: { plan_id: plan.id, from: found.fromIso } });
			hidden = true;
		} catch (e) {
			showToast(m('planBreak.dismissFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			busy = false;
		}
	}
</script>

{#if shown && found}
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
{/if}

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
