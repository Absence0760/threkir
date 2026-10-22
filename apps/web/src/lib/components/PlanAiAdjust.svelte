<script lang="ts">
	// "Adjust with AI" on /plans/[id] (decisions § 1979). The AI is the
	// interface, never the planner: the server turns the runner's request into
	// validated edit operations, this component applies them with the
	// deterministic plan helpers, grades the result against the original with
	// the ACWR bands, shows the before/after diff, and saves nothing until the
	// runner presses "Apply AI-suggested changes" — twice, when the edit makes
	// the plan harder. Every failure leaves the plan and the manual Adjust
	// options exactly as they were.
	import { onMount, tick } from 'svelte';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import { applyAiPlanEdits, fetchPrecedingPlan } from '#lib/core/data.ts';
	import { AI_CONSENT_HREF } from '#lib/core/ai_disclosure.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { fmtKm } from '#lib/format/units.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import {
		applyPlanEditOps,
		blockRaces,
		planEditLoadCheck,
		type PlanEditApplication,
		type PlanEditLoadCheck,
		type WorkoutState,
	} from '#lib/training/plan_edit/apply.ts';
	import {
		MAX_PLAN_EDIT_REQUEST_CHARS,
		type PlanEditNote,
		type PlanEditOp,
		type PlanEditSnapshot,
	} from '#lib/training/plan_edit/ops.ts';
	import { aiPlanEditPayload, planEditBlock } from '#lib/training/plan_edit/season.ts';
	import { PlanEditError, requestPlanEdits } from '#lib/training/plan_edit_client.ts';
	import type { PlanRace } from '#lib/training/plan_races.ts';
	import { recentRunVolume, type RunForVolume } from '#lib/training/plan_ramp.ts';
	import { parseISO } from '#lib/training/training.ts';
	import { workoutKindLabel } from '#lib/training/workout_labels.ts';
	import type { PlanWeek, PlanWorkout, TrainingPlan } from '#lib/types.ts';

	interface Props {
		plan: TrainingPlan;
		weeks: PlanWeek[];
		workouts: PlanWorkout[];
		recentRuns: RunForVolume[];
		today: string;
		/// A change request handed over by the Coach's link; runs once on mount.
		initialRequest?: string;
		onclose: () => void;
		onapplied: () => void | Promise<void>;
	}
	let { plan, weeks, workouts, recentRuns, today, initialRequest, onclose, onapplied }: Props =
		$props();

	let request = $state('');
	let busy = $state(false);
	let saving = $state(false);
	let error = $state<{ message: string; consent: boolean } | null>(null);
	let notes = $state<PlanEditNote[]>([]);
	let dropped = $state(0);
	let result = $state<{ application: PlanEditApplication; check: PlanEditLoadCheck } | null>(null);
	let noChanges = $state(false);
	let confirmHarder = $state(false);
	let heading = $state<HTMLHeadingElement>();
	/// What the result was graded from, and the day it was graded against.
	let basis: { ops: PlanEditOp[]; nearby: PlanRace[] } | null = null;
	let gradedDay = '';
	let dayChanged = $state(false);

	function snapshot(): PlanEditSnapshot {
		return {
			plan: {
				start_date: plan.start_date,
				end_date: plan.end_date,
				goal_distance_m: plan.goal_distance_m,
				goal_time_seconds: plan.goal_time_seconds,
			},
			weeks: weeks.map((w) => ({
				id: w.id,
				week_index: w.week_index,
				phase: w.phase,
				target_volume_m: w.target_volume_m,
			})),
			workouts: workouts.map((w) => ({ ...w })),
		};
	}

	function errorFor(e: unknown): { message: string; consent: boolean } {
		const kind = e instanceof PlanEditError ? e.kind : 'unavailable';
		if (kind === 'consent') return { message: m('planDetail.aiAdjustErrorConsent'), consent: true };
		if (kind === 'daily_limit') return { message: m('planDetail.aiAdjustErrorDailyLimit'), consent: false };
		if (kind === 'nothing_to_adjust') return { message: m('planDetail.aiAdjustErrorNothing'), consent: false };
		return { message: m('planDetail.aiAdjustErrorFallback'), consent: false };
	}

	async function suggest(): Promise<void> {
		const text = request.trim();
		if (!text || busy || saving) return;
		busy = true;
		error = null;
		result = null;
		noChanges = false;
		notes = [];
		dropped = 0;
		try {
			// The block before this one: a B/C race at its end has a recovery
			// window reaching into this plan, which a scale-up must not undo,
			// and `apply_ai_plan_edits` re-checks it (decisions § 2230).
			const [proposal, preceding] = await Promise.all([
				requestPlanEdits(plan.id, text, today),
				fetchPrecedingPlan(plan.start_date),
			]);
			notes = proposal.notes;
			dropped = proposal.dropped;
			basis = {
				ops: proposal.ops,
				nearby: preceding
					? blockRaces(planEditBlock(preceding.plan, preceding.weeks, preceding.workouts).snapshot)
					: [],
			};
			dayChanged = false;
			grade();
		} catch (e) {
			if (!(e instanceof PlanEditError)) {
				console.error('AI plan edit request failed', { message: thrownMessage(e) });
			}
			error = errorFor(e);
		} finally {
			busy = false;
		}
		await tick();
		heading?.focus();
	}

	/// Apply the operations and grade the result against `today`, recording
	/// the day it describes.
	function grade(): void {
		if (!basis) return;
		gradedDay = today;
		const before = snapshot();
		const application = applyPlanEditOps(before, basis.ops, today, basis.nearby);
		if (application.workouts.length === 0 && application.weeks.length === 0) {
			noChanges = true;
			result = null;
			return;
		}
		const check = planEditLoadCheck(before, application.after, recentRunVolume(recentRuns, Date.now()), today);
		result = { application, check };
	}

	/// The page's `today` moves at local midnight. Changes graded against the
	/// day before would include a workout now in the past, which
	/// `apply_ai_plan_edits` refuses whole, so re-grade against the new day and
	/// ask for another look instead of applying (decisions § 2230).
	function dayTurned(): boolean {
		if (gradedDay === today) return false;
		dayChanged = true;
		grade();
		return true;
	}

	function onApplyClick(): void {
		if (!result || result.check.verdict === 'reject') return;
		if (dayTurned()) return;
		if (result.check.verdict === 'confirm') confirmHarder = true;
		else void persist();
	}

	async function persist(): Promise<void> {
		confirmHarder = false;
		if (dayTurned()) return;
		if (!result || result.check.verdict === 'reject' || saving) return;
		saving = true;
		const { application, check } = result;
		try {
			// One transaction for every change, re-checked server-side
			// (`apply_ai_plan_edits`, decisions § 2230): a swap passing through
			// an occupied day, a skip and a week target land together or not
			// at all.
			await applyAiPlanEdits(
				plan.id,
				today,
				false,
				aiPlanEditPayload({
					scope: 'plan',
					blocks: [{ planId: plan.id, name: plan.name, application, check }],
					verdict: check.verdict,
				}),
			);
			showToast(m('planDetail.aiAdjustApplied'));
			result = null;
			await onapplied();
		} catch (e) {
			showToast(m('planDetail.bulkFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			saving = false;
		}
	}

	function dayLabel(iso: string): string {
		return parseISO(iso).toLocaleDateString(activeFormatLocale(), {
			weekday: 'short',
			day: 'numeric',
			month: 'short',
		});
	}

	function describe(s: WorkoutState): string {
		const size = s.distanceM != null && s.distanceM > 0 ? ` · ${fmtKm(s.distanceM)}` : '';
		return `${dayLabel(s.scheduledDate)} · ${workoutKindLabel(s.kind)}${size}`;
	}

	onMount(() => {
		const handed = initialRequest?.trim().slice(0, MAX_PLAN_EDIT_REQUEST_CHARS) ?? '';
		if (handed) {
			request = handed;
			void suggest();
		}
	});
</script>

<section class="ai-adjust" aria-labelledby="ai-adjust-title" data-testid="ai-adjust">
	<h3 id="ai-adjust-title" tabindex="-1" bind:this={heading}>{m('planDetail.aiAdjustTitle')}</h3>
	<p class="hint" id="ai-adjust-hint">{m('planDetail.aiAdjustHint')}</p>
	<label class="visually-hidden" for="ai-adjust-request">{m('planDetail.aiAdjustTitle')}</label>
	<textarea
		id="ai-adjust-request"
		bind:value={request}
		rows="2"
		maxlength={MAX_PLAN_EDIT_REQUEST_CHARS}
		placeholder={m('planDetail.aiAdjustPlaceholder')}
		aria-describedby="ai-adjust-hint"
		disabled={busy || saving}
	></textarea>
	<div class="actions">
		<button type="button" class="btn btn-secondary btn-sm" onclick={onclose} disabled={saving}>
			{m('planDetail.replanCancel')}
		</button>
		<button
			type="button"
			class="btn btn-outline btn-sm"
			onclick={suggest}
			disabled={busy || saving || !request.trim()}
			aria-busy={busy}
		>
			{busy ? m('planDetail.aiAdjustWorking') : m('planDetail.aiAdjustSubmit')}
		</button>
	</div>

	{#if error}
		<p class="error" role="alert">
			{error.message}
			{#if error.consent}
				<a href={AI_CONSENT_HREF}>{m('planDetail.aiAdjustErrorConsentLink')}</a>
			{/if}
		</p>
	{/if}

	{#if dayChanged && result}
		<p class="note" role="status" data-testid="ai-adjust-day-changed">{m('coachChat.planEditDayChanged')}</p>
	{/if}

	{#if notes.includes('unsupported')}
		<p class="note" role="status">{m('planDetail.aiAdjustUnsupported')}</p>
	{:else if noChanges}
		<p class="note" role="status">{m('planDetail.aiAdjustNoChanges')}</p>
	{/if}

	{#if result}
		<div class="preview" role="status">
			<p class="preview-title">{m('planDetail.aiAdjustPreviewTitle')}</p>
			<ul class="diff">
				{#each result.application.workouts as c (c.workoutId)}
					<li>
						<span class="before">{describe(c.before)}</span>
						<span class="material-symbols" aria-hidden="true">arrow_forward</span>
						<span class="after">
							{c.after.skipped ? m('planDetail.aiAdjustSkipped') : describe(c.after)}
						</span>
					</li>
				{/each}
				{#each result.application.weeks as w (w.weekId)}
					<li>
						{m('planDetail.aiAdjustWeekVolume', {
							n: w.weekIndex + 1,
							from: fmtKm(w.beforeVolumeM ?? 0),
							to: fmtKm(w.afterVolumeM ?? 0),
						})}
					</li>
				{/each}
			</ul>
			{#if dropped > 0 || notes.includes('too_many_ops')}
				<p class="note">{m('planDetail.aiAdjustDropped')}</p>
			{/if}
			{#if result.check.verdict === 'reject'}
				<p class="error" role="alert" data-testid="ai-adjust-rejected">
					{m('planDetail.aiAdjustRejected', {
						weeks: result.check.raisedWeeks
							.filter((w) => w.after === 'high')
							.map((w) => w.weekIndex + 1)
							.join(', '),
					})}
				</p>
			{:else if result.check.verdict === 'confirm'}
				<ul class="warnings" data-testid="ai-adjust-warnings">
					{#each result.check.raisedWeeks as w (w.weekIndex)}
						<li>{m('planDetail.aiAdjustWarnBand', { n: w.weekIndex + 1 })}</li>
					{/each}
					{#each result.check.stackedDays as d (d.join('|'))}
						<li>{m('planDetail.aiAdjustWarnStacked', { first: dayLabel(d[0]), second: dayLabel(d[1]) })}</li>
					{/each}
				</ul>
			{/if}
			<p class="note">{m('planDetail.aiAdjustReview')}</p>
			{#if result.check.verdict !== 'reject'}
				<div class="actions">
					<button
						type="button"
						class="btn btn-primary btn-sm"
						onclick={onApplyClick}
						disabled={saving}
						aria-busy={saving}
					>
						{m('planDetail.aiAdjustApply')}
					</button>
				</div>
			{/if}
		</div>
	{/if}
</section>

<ConfirmDialog
	open={confirmHarder}
	danger
	data-testid="ai-adjust-confirm"
	title={m('planDetail.aiAdjustConfirmTitle')}
	message={m('planDetail.aiAdjustConfirmMessage')}
	confirmLabel={m('planDetail.aiAdjustConfirmButton')}
	cancelLabel={m('planDetail.replanCancel')}
	onconfirm={persist}
	oncancel={() => (confirmHarder = false)}
/>

<style>
	.ai-adjust {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}
	h3 {
		margin: 0 0 0.25rem;
		font-size: 1rem;
	}
	.hint,
	.note {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0.25rem 0 0.5rem;
	}
	textarea {
		width: 100%;
		box-sizing: border-box;
		font: inherit;
		font-size: 0.9rem;
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: 0.5rem;
		color: var(--color-text);
		resize: vertical;
	}
	.actions {
		display: flex;
		gap: 0.5rem;
		justify-content: flex-end;
		flex-wrap: wrap;
		margin-top: 0.5rem;
	}
	.error {
		margin-top: 0.5rem;
		color: var(--color-danger-text);
		font-size: 0.9rem;
	}
	.error a {
		color: inherit;
		font-weight: 600;
	}
	.preview {
		margin-top: var(--space-md);
	}
	.preview-title {
		font-weight: 600;
		margin: 0 0 0.25rem;
	}
	.diff,
	.warnings {
		margin: 0;
		padding-inline-start: 1.1rem;
		font-size: 0.9rem;
	}
	.diff li {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.35rem;
		padding: 0.15rem 0;
	}
	.diff .before {
		color: var(--color-text-secondary);
		text-decoration: line-through;
	}
	.diff .material-symbols {
		font-size: 1rem;
		color: var(--color-text-secondary);
	}
	.warnings {
		color: var(--color-warning-text);
		margin-top: 0.5rem;
	}
</style>
