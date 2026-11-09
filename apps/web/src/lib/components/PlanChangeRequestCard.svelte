<script lang="ts">
	// One suggested change to a coach-assigned plan (issue #1215 Phase 2,
	// decisions § 2382), shown to its athlete and its coach as a system card:
	// a structured before → after diff, never AI text. The coach approves all
	// of it or the lines they keep ticked, or declines with an optional note;
	// the athlete can withdraw it or apply it themselves. Every write is an RPC
	// that re-checks the caller and the change.
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import {
		applyPlanChangeMyself,
		decidePlanChange,
		withdrawPlanChange,
		type PlanChangeRequest,
	} from '#lib/core/data.ts';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { fmtKm } from '#lib/format/units.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import {
		parsePlanChangeStatus,
		type PlanChangeLines,
		type PlanChangeWorkoutState,
	} from '#lib/training/plan_change.ts';
	import { parseISO, todayISO } from '#lib/training/training.ts';
	import { workoutKindLabel } from '#lib/training/workout_labels.ts';

	interface Props {
		request: PlanChangeRequest;
		lines: PlanChangeLines;
		viewerId: string;
		onchanged: () => void | Promise<void>;
	}
	let { request, lines, viewerId, onchanged }: Props = $props();

	const status = $derived(parsePlanChangeStatus(request.status));
	const isCoach = $derived(viewerId === request.coach_id);
	const pending = $derived(status === 'pending');

	let excluded = $state<Set<string>>(new Set());
	let note = $state('');
	let busy = $state(false);
	let confirmWithdraw = $state(false);

	const totalLines = $derived(lines.workouts.length + lines.weeks.length);
	const keptLines = $derived(totalLines - excluded.size);

	function statusLabel(): string {
		switch (status) {
			case 'pending':
				return isCoach ? m('planChange.waitingForYou') : m('planChange.waitingForCoach');
			case 'approved':
				return request.edited_by_coach ? m('planChange.approvedInPartByCoach') : m('planChange.approvedByCoach');
			case 'declined':
				return m('planChange.declinedByCoach');
			case 'withdrawn':
				return m('planChange.withdrawnByAthlete');
			case 'overridden':
				return m('planChange.appliedByAthlete');
			default:
				return '';
		}
	}

	function dayLabel(iso: string): string {
		return parseISO(iso).toLocaleDateString(activeFormatLocale(), {
			weekday: 'short',
			day: 'numeric',
			month: 'short',
		});
	}

	function describe(s: PlanChangeWorkoutState): string {
		const size =
			s.distanceM != null && s.distanceM > 0
				? ` · ${fmtKm(s.distanceM)}`
				: s.durationS != null && s.durationS > 0
					? ` · ${m('planChange.minutes', { n: Math.round(s.durationS / 60) })}`
					: '';
		return `${dayLabel(s.scheduledDate)} · ${workoutKindLabel(s.kind)}${size}`;
	}

	function toggle(id: string, keep: boolean): void {
		const next = new Set(excluded);
		if (keep) next.delete(id);
		else next.add(id);
		excluded = next;
	}

	async function run(action: () => Promise<void>, done: string): Promise<void> {
		if (busy) return;
		busy = true;
		try {
			await action();
			showToast(done);
			await onchanged();
		} catch (e) {
			showToast(m('planChange.failed', { error: errorCopy(e, m, 'plan change request') }), 'error');
		} finally {
			busy = false;
		}
	}

	function approve(): void {
		const partial = excluded.size > 0;
		const workoutIds = partial ? lines.workouts.map((l) => l.workoutId).filter((id) => !excluded.has(id)) : null;
		const weekIds = partial ? lines.weeks.map((l) => l.weekId).filter((id) => !excluded.has(id)) : null;
		void run(
			() => decidePlanChange(request.id, true, todayISO(), workoutIds, weekIds, note.trim() || null),
			m('planChange.approvedToast'),
		);
	}

	function decline(): void {
		void run(
			() => decidePlanChange(request.id, false, todayISO(), null, null, note.trim() || null),
			m('planChange.declinedToast'),
		);
	}

	function withdraw(): void {
		confirmWithdraw = false;
		void run(() => withdrawPlanChange(request.id), m('planChange.withdrawnToast'));
	}

	function applyMyself(): void {
		void run(() => applyPlanChangeMyself(request.id, todayISO()), m('planChange.appliedToast'));
	}
</script>

<section
	class="plan-change"
	class:pending
	aria-label={m('planChange.title')}
	data-testid="plan-change-request"
	data-status={request.status}
>
	<p class="title">
		<span class="material-symbols" aria-hidden="true">tune</span>
		{m('planChange.title')}
	</p>
	<p class="status" data-testid="plan-change-status">{statusLabel()}</p>

	<ul class="diff">
		{#each lines.workouts as l (l.workoutId)}
			<li>
				{#if isCoach && pending}
					<input
						type="checkbox"
						checked={!excluded.has(l.workoutId)}
						onchange={(e) => toggle(l.workoutId, e.currentTarget.checked)}
						aria-label={m('planChange.includeLine', { line: describe(l.before) })}
						disabled={busy}
						data-testid="plan-change-line-toggle"
					/>
				{/if}
				<span class="before">{describe(l.before)}</span>
				<span class="material-symbols" aria-hidden="true">arrow_forward</span>
				<span class="after">{l.after.skipped ? m('planChange.skipped') : describe(l.after)}</span>
			</li>
		{/each}
		{#each lines.weeks as w (w.weekId)}
			<li>
				{#if isCoach && pending}
					<input
						type="checkbox"
						checked={!excluded.has(w.weekId)}
						onchange={(e) => toggle(w.weekId, e.currentTarget.checked)}
						aria-label={m('planChange.includeLine', { line: m('planChange.weekLabel', { n: w.weekIndex + 1 }) })}
						disabled={busy}
						data-testid="plan-change-line-toggle"
					/>
				{/if}
				{m('planChange.weekTarget', {
					n: w.weekIndex + 1,
					from: fmtKm(w.beforeM ?? 0),
					to: fmtKm(w.afterM ?? 0),
				})}
			</li>
		{/each}
	</ul>
	{#if lines.unreadable > 0}
		<p class="note">{m('planChange.unreadable')}</p>
	{/if}
	{#if request.coach_note}
		<p class="coach-note" data-testid="plan-change-note">{m('planChange.coachNote', { note: request.coach_note })}</p>
	{/if}

	{#if pending && isCoach}
		<label class="note-field">
			<span>{m('planChange.noteLabel')}</span>
			<textarea
				bind:value={note}
				rows="2"
				maxlength="500"
				placeholder={m('planChange.notePlaceholder')}
				disabled={busy}
				data-testid="plan-change-note-input"
			></textarea>
		</label>
		<div class="actions">
			<button type="button" class="btn btn-secondary btn-sm" onclick={decline} disabled={busy} data-testid="plan-change-decline">
				{m('planChange.decline')}
			</button>
			<button
				type="button"
				class="btn btn-primary btn-sm"
				onclick={approve}
				disabled={busy || keptLines === 0}
				aria-busy={busy}
				data-testid="plan-change-approve"
			>
				{excluded.size > 0 ? m('planChange.approveSelected') : m('planChange.approve')}
			</button>
		</div>
	{:else if pending}
		<p class="note">{m('planChange.applyMyselfHint')}</p>
		<div class="actions">
			<button
				type="button"
				class="btn btn-secondary btn-sm"
				onclick={() => (confirmWithdraw = true)}
				disabled={busy}
				data-testid="plan-change-withdraw"
			>
				{m('planChange.withdraw')}
			</button>
			<button
				type="button"
				class="btn btn-outline btn-sm"
				onclick={applyMyself}
				disabled={busy}
				aria-busy={busy}
				data-testid="plan-change-apply-myself"
			>
				{m('planChange.applyMyself')}
			</button>
		</div>
	{/if}
</section>

<ConfirmDialog
	open={confirmWithdraw}
	danger
	data-testid="plan-change-withdraw-confirm"
	title={m('planChange.withdrawConfirmTitle')}
	message={m('planChange.withdrawConfirmMessage')}
	confirmLabel={m('planChange.withdraw')}
	cancelLabel={m('planChange.keep')}
	onconfirm={withdraw}
	oncancel={() => (confirmWithdraw = false)}
/>

<style>
	.plan-change {
		padding: 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		font-size: 0.9rem;
	}
	.title {
		display: flex;
		align-items: center;
		gap: 0.35rem;
		font-weight: 600;
		margin: 0;
	}
	.title .material-symbols {
		font-size: 1.1rem;
	}
	.status {
		margin: 0.2rem 0 0.4rem;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.diff {
		margin: 0;
		padding-inline-start: 1.1rem;
	}
	.diff li {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.35rem;
		padding: 0.15rem 0;
		overflow-wrap: anywhere;
	}
	.diff .before {
		color: var(--color-text-secondary);
		text-decoration: line-through;
	}
	.diff .material-symbols {
		font-size: 1rem;
		color: var(--color-text-secondary);
	}
	.note {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0.4rem 0;
	}
	.coach-note {
		margin: 0.4rem 0;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
	.note-field {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		margin-top: 0.5rem;
		font-size: 0.85rem;
	}
	.note-field textarea {
		width: 100%;
		font: inherit;
	}
	.actions {
		display: flex;
		gap: 0.5rem;
		justify-content: flex-end;
		flex-wrap: wrap;
		margin-top: 0.5rem;
	}
</style>
