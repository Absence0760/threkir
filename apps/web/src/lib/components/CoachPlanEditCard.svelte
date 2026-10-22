<script lang="ts">
	// The Coach's plan-edit proposal as a card inside the chat (decisions
	// § 2230, superseding the "review and apply on the plan page" part of
	// § 1979). The Coach's reply carries a `[Adjust my plan](/plans/<id>?adjust=…)`
	// link; this card sends that plan id and request to `/api/coach/plan-edit`,
	// which reads the plan under the runner's JWT and validates every operation
	// against it (`validatePlanEditOps`). The deterministic helpers apply them,
	// every changed block is graded with the ACWR bands, and the runner sees a
	// before/after diff. Nothing changes until Apply, which writes every change
	// in one transaction (`apply_ai_plan_edits`, re-checked server-side); Discard
	// writes nothing. With blocks chained after the plan and a uniform scale to
	// carry, the runner chooses This block only (the default) or the following
	// blocks too. Everything here renders as text; no model output reaches
	// {@html} (decisions § 110).
	import { onMount } from 'svelte';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import { AI_CONSENT_HREF } from '#lib/core/ai_disclosure.ts';
	import {
		applyAiPlanEdits,
		fetchMyPlansWithError,
		fetchPlan,
		fetchPrecedingPlan,
		fetchRuns,
	} from '#lib/core/data.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { fmtKm } from '#lib/format/units.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import type { WorkoutState } from '#lib/training/plan_edit/apply.ts';
	import type { PlanEditNote, PlanEditOp } from '#lib/training/plan_edit/ops.ts';
	import {
		aiPlanEditPayload,
		offersSeasonScope,
		planEditBlock,
		planSeasonEdit,
		type PlanEditBlock,
		type PlanEditScope,
		type SeasonEdit,
	} from '#lib/training/plan_edit/season.ts';
	import { PlanEditError, requestPlanEdits } from '#lib/training/plan_edit_client.ts';
	import { plansFollowing } from '#lib/training/plan_current.ts';
	import { recentRunVolume, type RunForVolume } from '#lib/training/plan_ramp.ts';
	import { parseISO, todayISO } from '#lib/training/training.ts';
	import { workoutKindLabel } from '#lib/training/workout_labels.ts';

	interface Props {
		planId: string;
		request: string;
		/// A reply that just arrived proposes at once; an older one in the
		/// thread waits for the runner, so reopening a chat spends no message.
		auto: boolean;
	}
	let { planId, request, auto }: Props = $props();

	type Phase = 'idle' | 'loading' | 'ready' | 'applied' | 'discarded' | 'error';
	let phase = $state<Phase>('idle');
	let error = $state<{ message: string; consent: boolean } | null>(null);
	let notes = $state<PlanEditNote[]>([]);
	let dropped = $state(0);
	let noChanges = $state(false);
	let edits = $state<{ plan: SeasonEdit; season: SeasonEdit | null } | null>(null);
	let scope = $state<PlanEditScope>('plan');
	let saving = $state(false);
	let confirmHarder = $state(false);
	/// Set when Apply found the day had turned since the changes were worked
	/// out: they were graded again against the new day and need a fresh look.
	let dayChanged = $state(false);
	/// The day the changes were graded against, sent as `p_today` on Apply.
	let today = '';
	/// What the grade was built from, kept so a new day can re-grade it
	/// without asking the Coach again.
	let basis: {
		ops: PlanEditOp[];
		blocks: { primary: PlanEditBlock; following: PlanEditBlock[]; preceding: PlanEditBlock | null };
		runs: RunForVolume[];
	} | null = null;

	let shown = $derived(edits ? (scope === 'season' && edits.season ? edits.season : edits.plan) : null);

	function errorFor(e: unknown): { message: string; consent: boolean } {
		const kind = e instanceof PlanEditError ? e.kind : 'unavailable';
		if (kind === 'consent') return { message: m('planDetail.aiAdjustErrorConsent'), consent: true };
		if (kind === 'daily_limit') return { message: m('planDetail.aiAdjustErrorDailyLimit'), consent: false };
		if (kind === 'nothing_to_adjust' || kind === 'not_found') {
			return { message: m('coachChat.planEditNothing'), consent: false };
		}
		return { message: m('coachChat.planEditFailed'), consent: false };
	}

	async function loadBlocks(): Promise<{
		primary: PlanEditBlock;
		following: PlanEditBlock[];
		preceding: PlanEditBlock | null;
	}> {
		const [primaryRes, mine] = await Promise.all([fetchPlan(planId), fetchMyPlansWithError()]);
		if (primaryRes.error) throw new Error(primaryRes.error);
		if (mine.error) throw new Error(mine.error);
		const plan = primaryRes.plan;
		if (!plan || plan.status !== 'active' || plan.end_date < today) {
			throw new PlanEditError('nothing_to_adjust');
		}
		// The set `apply_ai_plan_edits` accepts with p_include_following: the
		// runner's active, non-template plans that start after this one ends.
		const active = mine.plans.filter((p) => p.status === 'active' && !p.is_template && p.id !== plan.id);
		const later = plansFollowing(plan, active).slice(1);
		const [reads, before] = await Promise.all([
			Promise.all(later.map((p) => fetchPlan(p.id))),
			fetchPrecedingPlan(plan.start_date),
		]);
		const following: PlanEditBlock[] = [];
		for (const r of reads) {
			if (r.error) throw new Error(r.error);
			if (r.plan) following.push(planEditBlock(r.plan, r.weeks, r.workouts));
		}
		return {
			primary: planEditBlock(plan, primaryRes.weeks, primaryRes.workouts),
			following,
			preceding: before ? planEditBlock(before.plan, before.weeks, before.workouts) : null,
		};
	}

	async function propose(): Promise<void> {
		if (phase === 'loading') return;
		phase = 'loading';
		error = null;
		edits = null;
		noChanges = false;
		dayChanged = false;
		basis = null;
		scope = 'plan';
		today = todayISO();
		try {
			const [proposal, blocks, runs] = await Promise.all([
				requestPlanEdits(planId, request, today),
				loadBlocks(),
				fetchRuns({ limit: 50 }),
			]);
			notes = proposal.notes;
			dropped = proposal.dropped;
			basis = { ops: proposal.ops, blocks, runs };
			grade();
			phase = 'ready';
		} catch (e) {
			if (!(e instanceof PlanEditError)) {
				console.error('[coach] plan edit proposal failed', { message: thrownMessage(e) });
			}
			error = errorFor(e);
			phase = 'error';
		}
	}

	/// Apply the operations and grade every block against `today`. Each
	/// operation's target is re-checked for editability on that day, so a
	/// workout that has become past drops out rather than reaching the RPC.
	function grade(): void {
		if (!basis) return;
		const { ops, blocks, runs } = basis;
		// Measured now, so a re-grade on a new day has a new day's baseline.
		const recent = recentRunVolume(runs, Date.now());
		const input = {
			primary: blocks.primary,
			ops,
			following: blocks.following,
			preceding: blocks.preceding,
			recent,
			todayIso: today,
		};
		const plan = planSeasonEdit({ ...input, scope: 'plan' });
		const first = plan.blocks[0].application;
		if (first.workouts.length === 0 && first.weeks.length === 0) {
			noChanges = true;
			edits = null;
			return;
		}
		const season = offersSeasonScope(blocks.primary, ops, blocks.following, today, blocks.preceding)
			? planSeasonEdit({ ...input, scope: 'season' })
			: null;
		if (!season) scope = 'plan';
		edits = { plan, season };
	}

	/// The changes were graded against the day they were worked out on. After
	/// local midnight that day is yesterday: a workout dated yesterday would
	/// still read as editable, the grade would describe the wrong week, and
	/// `p_today` (accepted within a day of the server's date) would let the RPC
	/// write a workout that is now in the past. Re-grade against the new day
	/// and show the result instead of applying.
	function dayTurned(): boolean {
		const now = todayISO();
		if (now === today) return false;
		today = now;
		dayChanged = true;
		grade();
		return true;
	}

	function onApplyClick(): void {
		if (!shown || shown.verdict === 'reject' || saving) return;
		if (dayTurned()) return;
		if (shown.verdict === 'confirm') confirmHarder = true;
		else void persist();
	}

	async function persist(): Promise<void> {
		confirmHarder = false;
		if (dayTurned()) return;
		const edit = shown;
		if (!edit || edit.verdict === 'reject' || saving) return;
		saving = true;
		try {
			await applyAiPlanEdits(planId, today, edit.scope === 'season', aiPlanEditPayload(edit));
			phase = 'applied';
			showToast(m('planDetail.aiAdjustApplied'));
		} catch (e) {
			showToast(m('planDetail.bulkFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			saving = false;
		}
	}

	function discard(): void {
		edits = null;
		phase = 'discarded';
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
		if (auto) void propose();
	});
</script>

<section class="plan-edit-card" aria-label={m('coachChat.planEditTitle')} data-testid="coach-plan-edit">
	<p class="title">
		<span class="material-symbols" aria-hidden="true">tune</span>
		{m('coachChat.planEditTitle')}
	</p>

	{#if dayChanged && phase === 'ready'}
		<p class="note" role="status" data-testid="coach-plan-edit-day-changed">{m('coachChat.planEditDayChanged')}</p>
	{/if}

	{#if phase === 'idle'}
		<button type="button" class="btn btn-outline btn-sm" onclick={propose}>
			{m('coachChat.planEditReview')}
		</button>
	{:else if phase === 'loading'}
		<p class="note" role="status" aria-busy="true">{m('coachChat.planEditWorking')}</p>
	{:else if phase === 'error' && error}
		<p class="error" role="alert">
			{error.message}
			{#if error.consent}
				<a href={AI_CONSENT_HREF}>{m('planDetail.aiAdjustErrorConsentLink')}</a>
			{/if}
		</p>
		<button type="button" class="btn btn-secondary btn-sm" onclick={propose}>
			{m('coachChat.planEditRetry')}
		</button>
	{:else if phase === 'applied'}
		<p class="note" role="status">{m('coachChat.planEditApplied')}</p>
	{:else if phase === 'discarded'}
		<p class="note" role="status">{m('coachChat.planEditDiscarded')}</p>
	{:else if notes.includes('unsupported')}
		<p class="note" role="status">{m('planDetail.aiAdjustUnsupported')}</p>
	{:else if noChanges}
		<p class="note" role="status">{m('planDetail.aiAdjustNoChanges')}</p>
	{:else if shown && edits}
		{#if edits.season}
			<fieldset class="scope" data-testid="coach-plan-edit-scope">
				<legend>{m('coachChat.planEditScopeLegend')}</legend>
				<label>
					<input type="radio" name="scope-{planId}" value="plan" bind:group={scope} disabled={saving} />
					{m('coachChat.planEditScopeBlock')}
				</label>
				<label>
					<input type="radio" name="scope-{planId}" value="season" bind:group={scope} disabled={saving} />
					{m('coachChat.planEditScopeSeason')}
				</label>
			</fieldset>
		{/if}
		<div role="status">
			{#each shown.blocks as b (b.planId)}
				<div class="block" data-testid="coach-plan-edit-block">
					{#if shown.blocks.length > 1}
						<p class="block-name">{b.name}</p>
					{/if}
					<ul class="diff">
						{#each b.application.workouts as c (c.workoutId)}
							<li>
								<span class="before">{describe(c.before)}</span>
								<span class="material-symbols" aria-hidden="true">arrow_forward</span>
								<span class="after">
									{c.after.skipped ? m('planDetail.aiAdjustSkipped') : describe(c.after)}
								</span>
							</li>
						{/each}
						{#each b.application.weeks as w (w.weekId)}
							<li>
								{m('planDetail.aiAdjustWeekVolume', {
									n: w.weekIndex + 1,
									from: fmtKm(w.beforeVolumeM ?? 0),
									to: fmtKm(w.afterVolumeM ?? 0),
								})}
							</li>
						{/each}
					</ul>
					{#if b.check.verdict === 'reject'}
						<p class="error" data-testid="coach-plan-edit-rejected">
							{m('planDetail.aiAdjustRejected', {
								weeks: b.check.raisedWeeks
									.filter((w) => w.after === 'high')
									.map((w) => w.weekIndex + 1)
									.join(', '),
							})}
						</p>
					{:else if b.check.verdict === 'confirm'}
						<ul class="warnings">
							{#each b.check.raisedWeeks as w (w.weekIndex)}
								<li>{m('planDetail.aiAdjustWarnBand', { n: w.weekIndex + 1 })}</li>
							{/each}
							{#each b.check.stackedDays as d (d.join('|'))}
								<li>
									{m('planDetail.aiAdjustWarnStacked', { first: dayLabel(d[0]), second: dayLabel(d[1]) })}
								</li>
							{/each}
						</ul>
					{/if}
				</div>
			{/each}
		</div>
		{#if dropped > 0 || notes.includes('too_many_ops')}
			<p class="note">{m('planDetail.aiAdjustDropped')}</p>
		{/if}
		{#if shown.verdict === 'reject' && edits.season && scope === 'season'}
			<p class="note">{m('coachChat.planEditRejectedSeason')}</p>
		{/if}
		<p class="note">{m('planDetail.aiAdjustReview')}</p>
		<div class="actions">
			<button type="button" class="btn btn-secondary btn-sm" onclick={discard} disabled={saving}>
				{m('coachChat.planEditDiscard')}
			</button>
			{#if shown.verdict !== 'reject'}
				<button
					type="button"
					class="btn btn-primary btn-sm"
					onclick={onApplyClick}
					disabled={saving}
					aria-busy={saving}
				>
					{m('coachChat.planEditApply')}
				</button>
			{/if}
		</div>
	{/if}
</section>

<ConfirmDialog
	open={confirmHarder}
	danger
	data-testid="coach-plan-edit-confirm"
	title={m('planDetail.aiAdjustConfirmTitle')}
	message={m('planDetail.aiAdjustConfirmMessage')}
	confirmLabel={m('planDetail.aiAdjustConfirmButton')}
	cancelLabel={m('coachChat.cancel')}
	onconfirm={persist}
	oncancel={() => (confirmHarder = false)}
/>

<style>
	.plan-edit-card {
		margin-top: 0.6rem;
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
		margin: 0 0 0.5rem;
	}
	.title .material-symbols {
		font-size: 1.1rem;
	}
	.note {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0.4rem 0;
	}
	.error {
		color: var(--color-danger-text);
		margin: 0.4rem 0;
	}
	.error a {
		color: inherit;
		font-weight: 600;
	}
	.scope {
		border: none;
		margin: 0 0 0.5rem;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}
	.scope legend {
		font-weight: 600;
		padding: 0;
		margin-bottom: 0.25rem;
	}
	.scope label {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		min-height: 2rem;
	}
	.block + .block {
		margin-top: 0.5rem;
	}
	.block-name {
		font-weight: 600;
		margin: 0 0 0.2rem;
	}
	.diff,
	.warnings {
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
	.warnings {
		color: var(--color-warning-text);
		margin-top: 0.4rem;
	}
	.actions {
		display: flex;
		gap: 0.5rem;
		justify-content: flex-end;
		flex-wrap: wrap;
		margin-top: 0.5rem;
	}
</style>
