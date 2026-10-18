<script lang="ts">
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { onMount } from 'svelte';
	import { lengthLimit } from '#lib/core/column_limits.ts';
	import { todayISO } from '#lib/training/training.ts';
	import { formatDate } from '#lib/format/time.ts';
	import { alignPlanStartIso, defaultPlanStartIso } from '#lib/training/plan_start.ts';
	import { racePlanPreset } from '#lib/training/race_plan_preset.ts';
	import { goto, afterNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import PlanEditor from '#lib/components/PlanEditor.svelte';
	import PlanOverlapDialog, { trimBlockedMessage } from '#lib/components/PlanOverlapDialog.svelte';
	import { attemptPlanCreate, clonedPlanEndIso, type OverlapPlan } from '#lib/training/plan_overlap.ts';
	import SessionPlanEditor from '#lib/components/SessionPlanEditor.svelte';
	import RoutineEditor from '#lib/components/RoutineEditor.svelte';
	import {
		fetchMyClubs,
		fetchClubTemplatesForClubs,
		clonePlanTemplate,
		createTrainingPlan,
		fetchMyOverlappingActivePlans,
		type PlanOverlapChoice,
		fetchGymExerciseNames,
		publishGymRoutineAsTemplate,
	} from '#lib/core/data.ts';
	import { STARTER_PLANS, starterById, instantiateStarter } from '#lib/training/starter_plans.ts';
	import { starterName, starterSummaryText } from '#lib/training/starter_labels.ts';
	import { PRIMARY_GOAL_VALUES, planPresetForGoal, type PrimaryGoal } from '#lib/settings/onboarding.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { TrainingPlan } from '#lib/types.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';

	interface TemplateOption {
		template: TrainingPlan;
		clubName: string;
	}

	type PlanKind = 'training' | 'session' | 'gym';

	// `?describe=<text>` (the coach's plan handoff) hands the AI plan box a
	// description to fill from. It is a training-plan request by definition,
	// so it picks that kind and skips the chooser. Capped to the box's own
	// maxlength; PlanEditor ignores it while the assistant is off.
	const describeParam =
		page.url.searchParams.get('describe')?.trim().slice(0, 600).trim() || undefined;

	function initialKind(): PlanKind {
		if (describeParam) return 'training';
		const t = page.url.searchParams.get('type');
		return t === 'session' || t === 'gym' ? t : 'training';
	}

	// `?club=<id>` (set by a club's Templates-tab "New …" links) targets the
	// new artifact at that club. Honoured one-step only by the session branch —
	// session_plans support a club-owned create; training + gym templates are
	// build-then-publish, so the club param is informational there.
	const clubId = page.url.searchParams.get('club');

	// An explicit `?type=` means the caller already chose the kind (a club's
	// contextual "New …" link) — skip the chooser so we don't ask twice. The
	// bare /plans/new entry (no type) shows the chooser to disambiguate.
	const explicitType = page.url.searchParams.get('type');
	const showChooser =
		!describeParam &&
		!(explicitType === 'training' || explicitType === 'session' || explicitType === 'gym');

	// `?goal=<primary_goal>` (the onboarding "create my training plan" CTA)
	// preselects the goal distance + walk-run toggle so a brand-new runner
	// lands on the right plan shape without hunting for the beginner checkbox.
	const goalParam = page.url.searchParams.get('goal');
	const goalPreset =
		goalParam && (PRIMARY_GOAL_VALUES as readonly string[]).includes(goalParam)
			? planPresetForGoal(goalParam as PrimaryGoal)
			: null;

	// `?raceDate=&raceName=&raceDistance=` (the race calendar's "train for
	// this race" CTA) sizes the plan so its final race week contains race
	// day. The URL carries the race's facts rather than the derived dates so
	// the arithmetic has one home — a hand-edited or bookmarked link is
	// re-derived against today, not replayed stale.
	const raceDateParam = page.url.searchParams.get('raceDate');
	const raceNameParam = page.url.searchParams.get('raceName');
	// Absent and empty both coerce to 0 through `Number`, so the parse has to
	// test the string, not the number — an "is this present" check written as
	// `Number.isFinite` silently reads a missing param as a zero-metre race.
	const raceDistanceParam = page.url.searchParams.get('raceDistance')?.trim();
	const raceDistanceM = (() => {
		if (!raceDistanceParam) return null;
		const n = Number(raceDistanceParam);
		return Number.isFinite(n) ? n : null;
	})();
	// `?notBefore=` (a race page's "Add to my season") floors the start after
	// the runner's current plan and its recovery days, so the new plan queues
	// behind it instead of overlapping it.
	const notBeforeParam = page.url.searchParams.get('notBefore')?.trim() || null;
	const racePreset = raceDateParam
		? racePlanPreset({
				raceDateIso: raceDateParam,
				distanceM: raceDistanceM,
				todayIso: todayISO(),
				notBeforeIso: notBeforeParam,
			})
		: null;
	// A refusal still renders the wizard on its own defaults — we just say
	// why the dates aren't the race's, rather than silently ignoring the link.
	// The name field is capped; a programmatic bind bypasses that, so clamp
	// what the URL hands us to the same budget.
	const initialName =
		racePreset?.ok && raceNameParam?.trim()
			? raceNameParam.trim().slice(0, lengthLimit('training_plans.name'))
			: undefined;

	const raceRefusalKey: MessageKey | null =
		!racePreset || racePreset.ok
			? null
			: racePreset.reason === 'past'
				? 'plansNew.racePast'
				: racePreset.reason === 'too_soon'
					? 'plansNew.raceTooSoon'
					: 'plansNew.raceUnreadable';

	let kind = $state<PlanKind>(initialKind());

	let templates = $state<TemplateOption[]>([]);
	let loadingTemplates = $state(true);
	let selectedTemplateId = $state('');
	let startDate = $state(defaultStartDate());
	let startSnapped = $state(false);
	let cloning = $state(false);
	let selectedStarterId = $state('');
	let creatingStarter = $state(false);
	let gymSuggestions = $state<string[]>([]);

	const headingKey = $derived(
		kind === 'session'
			? 'plansNew.headingSession'
			: kind === 'gym'
				? 'plansNew.headingGym'
				: 'plansNew.heading'
	);
	const taglineKey = $derived(
		kind === 'session'
			? 'plansNew.taglineSession'
			: kind === 'gym'
				? 'plansNew.taglineGym'
				: 'plansNew.tagline'
	);

	function onSessionCreated(id: string): void {
		// When created for a club, return to the Templates tab the link came
		// from so the new template is visible in its list; otherwise open it.
		if (clubId && backHref.startsWith('/clubs/')) goto(backHref);
		else goto(`/sessions/${id}`);
	}

	// Gym routines have no club-admin INSERT policy (unlike session_plans), so a
	// club-owned routine can only be minted through the admin-checked
	// publish_gym_routine_as_template RPC. When the editor was opened from a
	// club's Templates tab, publish the freshly-built routine to the club in the
	// same step (matching the session branch's one-step club create) and return
	// to that tab; the personal routine stays on the user's /gym/routines list,
	// mirroring how publishing a training plan leaves its source plan.
	async function onGymCreated(id: string): Promise<void> {
		if (clubId) {
			try {
				await publishGymRoutineAsTemplate(id, clubId);
			} catch (e) {
				console.error('publish gym routine as club template failed', e);
				showToast(m('plansNew.clubPublishFailed'), 'error');
				goto(`/gym/routines/${id}`);
				return;
			}
		}
		if (clubId && backHref.startsWith('/clubs/')) goto(backHref);
		else goto(`/gym/routines/${id}`);
	}

	// Back/cancel target. Defaults to /plans; when the user arrived from a
	// club's Templates tab (the "Adopt" link), return them there instead.
	let backHref = $state('/plans');
	let backLabel = $state(m('plansNew.backToPlans'));
	let backViaHistory = $state(false);
	let backCaptured = $state(false);
	afterNavigate(({ from }) => {
		if (backCaptured || !from) return;
		if (from.url.pathname === '/plans' || from.url.pathname.startsWith('/plans?')) {
			backViaHistory = true;
			backCaptured = true;
		} else if (
			from.url.pathname.startsWith('/clubs/') &&
			from.url.searchParams.get('tab') === 'templates'
		) {
			backHref = from.url.pathname + from.url.search;
			backLabel = m('plansNew.backToClubTemplates');
			backCaptured = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (backViaHistory) {
			e.preventDefault();
			history.back();
		}
	}

	function handleCancel(): void {
		if (backViaHistory) history.back();
		else goto(backHref);
	}

	/// Plan day 0 is the Sunday long run, so a plan starts on a Sunday
	/// (decisions § 735): the default is the Sunday at least a week out. A
	/// walk-run starter is the exemption and defaults to tomorrow, chosen in
	/// `onStarterChange` while the runner has not touched the date.
	function defaultStartDate(): string {
		return defaultPlanStartIso(todayISO(), false);
	}

	onMount(async () => {
		try {
			const clubs = await fetchMyClubs();
			const byClub = await fetchClubTemplatesForClubs(clubs.map((c) => c.id));
			templates = clubs.flatMap((c) =>
				(byClub.get(c.id) ?? []).map((template) => ({ template, clubName: c.name }))
			);
			// Pre-select the template a club's "Adopt" deep link points at
			// (/plans/new?from=<templateId>). Only honour it when it's one of
			// the user's loaded club templates — a stale or foreign id leaves
			// the picker on its placeholder rather than a phantom selection.
			const from = page.url.searchParams.get('from');
			if (from && templates.some((t) => t.template.id === from)) {
				selectedTemplateId = from;
			}
		} catch (e) {
			console.warn('fetch templates failed', e);
		} finally {
			loadingTemplates = false;
		}
		try {
			gymSuggestions = await fetchGymExerciseNames();
		} catch (e) {
			console.warn('fetch gym exercise names failed', e);
		}
	});

	// The template and starter paths ask the server to refuse an overlap and,
	// when it does, show the same dialog the wizard does; the runner's choice
	// is retried through `retryWithOverlap` (decisions § 2050).
	let overlapping = $state<OverlapPlan[]>([]);
	let overlapStart = $state('');
	let retryWithOverlap: ((overlap: PlanOverlapChoice) => Promise<void>) | null = null;

	function askOverlap(start: string, hits: OverlapPlan[], retry: (overlap: PlanOverlapChoice) => Promise<void>) {
		overlapStart = start;
		retryWithOverlap = retry;
		overlapping = hits;
	}

	function cancelOverlap() {
		overlapping = [];
		retryWithOverlap = null;
	}

	async function chooseOverlap(choice: 'replace' | 'trim') {
		const retry = retryWithOverlap;
		overlapping = [];
		retryWithOverlap = null;
		await retry?.(choice);
	}

	async function cloneSelected() {
		if (!selectedTemplateId || !startDate || cloning) return;
		const option = templates.find((t) => t.template.id === selectedTemplateId);
		if (!option) return;
		const start = startDate;
		const end = clonedPlanEndIso(option.template, start);
		const run = async (overlap: PlanOverlapChoice): Promise<void> => {
			cloning = true;
			try {
				const outcome = await attemptPlanCreate(
					() => clonePlanTemplate(option.template.id, start, overlap),
					() => fetchMyOverlappingActivePlans(start, end)
				);
				if (outcome.kind === 'overlap') {
					askOverlap(start, outcome.overlapping, run);
					return;
				}
				if (outcome.kind === 'trimBlocked') {
					showToast(trimBlockedMessage(outcome.overlapping, start), 'error');
					return;
				}
				showToast(m('plansNew.toastCreated'));
				goto(`/plans/${outcome.value}`);
			} catch (e) {
				showToast(m('plansNew.toastCloneFailed', { error: thrownMessage(e) }), 'error');
			} finally {
				cloning = false;
			}
		};
		await run('refuse');
	}

	let selectedStarterSummary = $derived(selectedStarterId ? starterSummaryText(selectedStarterId) : null);

	function starterWalkRun(): boolean {
		return starterById(selectedStarterId)?.beginnerWalkRun ?? false;
	}

	function onStarterChange() {
		const walkRun = starterWalkRun();
		if (startDate === defaultPlanStartIso(todayISO(), !walkRun)) {
			startDate = defaultPlanStartIso(todayISO(), walkRun);
		}
		alignStarterStart();
	}

	/// A date input cannot be limited to Sundays, so a picked weekday snaps
	/// forward to the upcoming Sunday, unless the starter is walk-run.
	function alignStarterStart() {
		if (!startDate || !selectedStarterId) return;
		const aligned = alignPlanStartIso(startDate, starterWalkRun());
		startSnapped = aligned !== startDate;
		startDate = aligned;
	}

	async function createFromStarter() {
		if (!selectedStarterId || !startDate || creatingStarter) return;
		alignStarterStart();
		const starterId = selectedStarterId;
		const start = startDate;
		const starter = starterById(starterId);
		const generated = instantiateStarter(starterId, start);
		if (!starter || !generated) return;
		const run = async (overlap: PlanOverlapChoice): Promise<void> => {
			creatingStarter = true;
			try {
				const outcome = await attemptPlanCreate(
					() =>
						createTrainingPlan({
							name: starterName(starterId),
							goalEvent: starter.goalEvent,
							goalDistanceM: generated.goalDistanceM,
							startDate: start,
							daysPerWeek: starter.daysPerWeek,
							generated,
							overlap
						}),
					() => fetchMyOverlappingActivePlans(start, generated.endDate)
				);
				if (outcome.kind === 'overlap') {
					askOverlap(start, outcome.overlapping, run);
					return;
				}
				if (outcome.kind === 'trimBlocked') {
					showToast(trimBlockedMessage(outcome.overlapping, start), 'error');
					return;
				}
				showToast(m('plansNew.toastCreated'));
				goto(`/plans/${outcome.value.id}`);
			} catch (e) {
				showToast(
					m('plansNew.toastCreateFailed', { error: thrownMessage(e) }),
					'error'
				);
			} finally {
				creatingStarter = false;
			}
		};
		await run('refuse');
	}
</script>

<svelte:head>
	<title>{m('plansNew.pageTitle')}</title>
</svelte:head>

<div class="page">
	<a href={backHref} class="back-link" onclick={handleBack}>
		<span class="material-symbols">arrow_back</span>
		{backLabel}
	</a>

	<p class="kicker">{m('plansNew.kicker')}</p>

	{#if showChooser}
		<div
			class="kind-chooser"
			role="group"
			aria-label={m('plansNew.chooserLabel')}
			aria-describedby="plan-kind-tagline"
		>
			<button
				type="button"
				class="kind-tab"
				class:active={kind === 'training'}
				aria-pressed={kind === 'training'}
				onclick={() => (kind = 'training')}
				data-testid="kind-training"
			>
				{m('plansNew.kindTraining')}
			</button>
			<button
				type="button"
				class="kind-tab"
				class:active={kind === 'session'}
				aria-pressed={kind === 'session'}
				onclick={() => (kind = 'session')}
				data-testid="kind-session"
			>
				{m('plansNew.kindSession')}
			</button>
			<button
				type="button"
				class="kind-tab"
				class:active={kind === 'gym'}
				aria-pressed={kind === 'gym'}
				onclick={() => (kind = 'gym')}
				data-testid="kind-gym"
			>
				{m('plansNew.kindGym')}
			</button>
		</div>
	{/if}

	<header class="page-header">
		<h1>{m(headingKey)}</h1>
		<p class="tagline" id="plan-kind-tagline">
			{m(taglineKey)}
		</p>
	</header>

	{#if kind === 'training'}
	{#if clubId}
		<p class="picker-hint club-target-note">{m('plansNew.clubPublishNote')}</p>
	{/if}
	<section class="starter-picker">
		<h2>{m('plansNew.starterHeading')}</h2>
		<p class="picker-hint" id="starter-hint">{m('plansNew.starterHint')}</p>
		<div class="picker-row">
			<label class="picker-field">
				<span>{m('plansNew.starterLabel')}</span>
				<select
					bind:value={selectedStarterId}
					onchange={onStarterChange}
					aria-describedby="starter-hint starter-summary"
				>
					<option value="">{m('plansNew.selectPlaceholder')}</option>
					{#each STARTER_PLANS as s (s.id)}
						<option value={s.id}>{starterName(s.id)}</option>
					{/each}
				</select>
			</label>
			<label class="picker-field">
				<span>{m('plansNew.startDateLabel')}</span>
				<input
					type="date"
					bind:value={startDate}
					onchange={alignStarterStart}
					aria-describedby="starter-start-date-hint"
				/>
				{#if startSnapped}
					<span class="field-note" role="status">{m('planEditor.movedToNextSunday')}</span>
				{/if}
			</label>
			<button
				class="btn btn-primary"
				type="button"
				disabled={!selectedStarterId || !startDate || creatingStarter}
				onclick={createFromStarter}
			>
				{#if creatingStarter}
					<span class="btn-spinner" aria-hidden="true"></span>
					{m('plansNew.creating')}
				{:else}
					{m('plansNew.createStarter')}
				{/if}
			</button>
		</div>
		<p class="picker-hint field-hint" id="starter-summary" data-testid="starter-summary" hidden={!selectedStarterSummary}>
			{selectedStarterSummary ?? ''}
		</p>
		<p class="picker-hint field-hint" id="starter-start-date-hint">{m('plansNew.startDateHint')}</p>
	</section>

	<section class="season-entry" data-testid="season-entry">
		<h2>{m('seasonPlanner.entryTitle')}</h2>
		<p class="picker-hint">{m('seasonPlanner.entryHint')}</p>
		<a class="btn btn-secondary" href="/plans/season">{m('seasonPlanner.entryLink')}</a>
	</section>

	{#if !loadingTemplates && templates.length > 0}
		<section class="template-picker">
			<h2>{m('plansNew.templateHeading')}</h2>
			<p class="picker-hint" id="template-hint">
				{m('plansNew.templateHint')}
			</p>
			<div class="picker-row">
				<label class="picker-field">
					<span>{m('plansNew.templateLabel')}</span>
					<select bind:value={selectedTemplateId} aria-describedby="template-hint">
						<option value="">{m('plansNew.selectPlaceholder')}</option>
						{#each templates as t (t.template.id)}
							<option value={t.template.id}>
								{t.template.name} — {t.clubName}
							</option>
						{/each}
					</select>
				</label>
				<label class="picker-field">
					<span>{m('plansNew.startDateLabel')}</span>
					<input type="date" bind:value={startDate} aria-describedby="template-start-date-hint" />
				</label>
				<button
					class="btn btn-primary"
					type="button"
					disabled={!selectedTemplateId || !startDate || cloning}
					onclick={cloneSelected}
				>
					{#if cloning}
						<span class="btn-spinner" aria-hidden="true"></span>
						{m('plansNew.cloning')}
					{:else}
						{m('plansNew.cloneTemplate')}
					{/if}
				</button>
			</div>
			<p class="picker-hint field-hint" id="template-start-date-hint">{m('plansNew.startDateHint')}</p>
		</section>
	{/if}

	<div class="or-rule"><span>{m('plansNew.orFromScratch')}</span></div>

	{#if racePreset?.ok}
		<p class="picker-hint race-preset-note" data-testid="race-preset-note">
			{m('plansNew.raceAnchored', { weeks: String(racePreset.preset.weeks) })}
		</p>
		{#if notBeforeParam}
			<p class="picker-hint race-preset-note" data-testid="race-preset-chained">
				{m('plansNew.raceChained', { date: formatDate(racePreset.preset.startDate) })}
			</p>
		{/if}
	{:else if raceRefusalKey}
		<p class="picker-hint race-preset-note" data-testid="race-preset-refusal">
			{m(raceRefusalKey)}
		</p>
	{/if}

	<PlanEditor
		oncreated={(plan) => goto(`/plans/${plan.id}`)}
		oncancel={handleCancel}
		initialGoalEvent={racePreset?.ok
			? (racePreset.preset.goalEvent ?? undefined)
			: goalPreset?.goalEvent}
		initialGoalDistanceM={racePreset?.ok && racePreset.preset.goalEvent == null ? raceDistanceM : null}
		initialBeginnerWalkRun={goalPreset?.beginnerWalkRun}
		{initialName}
		initialStartDate={racePreset?.ok ? racePreset.preset.startDate : undefined}
		initialWeeks={racePreset?.ok ? racePreset.preset.weeks : undefined}
		notBeforeIso={notBeforeParam}
		initialDescription={describeParam}
	/>
	{:else if kind === 'session'}
		<div class="form-branch">
			{#if clubId}
				<p class="picker-hint club-target-note">{m('plansNew.sessionForClub')}</p>
			{/if}
			<SessionPlanEditor {clubId} oncreated={onSessionCreated} oncancel={handleCancel} />
		</div>
	{:else}
		<div class="form-branch">
			{#if clubId}
				<p class="picker-hint club-target-note">{m('plansNew.clubPublishNote')}</p>
			{/if}
			<RoutineEditor suggestions={gymSuggestions} oncreated={onGymCreated} oncancel={handleCancel} />
		</div>
	{/if}
</div>

<PlanOverlapDialog
	{overlapping}
	startDate={overlapStart}
	onchoose={chooseOverlap}
	oncancel={cancelOverlap}
/>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	/* The session + gym branches are focused single-form editors — cap their
	   content so fields don't stretch the full viewport on a wide screen
	   (conventions § Web page padding). The training branch is a two-column
	   wizard (PlanEditor) and stays uncapped so its calendar pane keeps room. */
	.form-branch {
		max-width: 48rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		padding: var(--space-xs) 0;
		margin-bottom: var(--space-md);
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link .material-symbols {
		font-size: 1.1rem;
	}
	.page-header {
		margin-bottom: var(--space-xl);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm);
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 800;
		line-height: 1.2;
		margin: 0 0 var(--space-xs);
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 44rem;
	}

	.kind-chooser {
		display: inline-flex;
		/* A segmented control is one continuous track — it scrolls itself
		   rather than widening the document (WCAG 1.4.10). */
		max-width: 100%;
		overflow-x: auto;
		gap: 0.25rem;
		padding: 0.25rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		margin-bottom: var(--space-lg);
	}
	.kind-tab {
		appearance: none;
		border: none;
		background: transparent;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-weight: 600;
		/* Equal width per tab so the active highlight never shifts the row. */
		min-width: 8.5rem;
		text-align: center;
		white-space: nowrap;
		padding: 0.5rem 1rem;
		border-radius: var(--radius-md);
		cursor: pointer;
		transition: background 0.12s ease, color 0.12s ease;
	}
	.kind-tab:hover:not(.active) {
		color: var(--color-text);
		background: color-mix(in srgb, var(--color-text) 6%, transparent);
	}
	.kind-tab.active {
		background: var(--color-primary);
		color: var(--color-on-primary);
	}
	.club-target-note {
		margin-bottom: var(--space-md);
	}

	.template-picker,
	.starter-picker,
	.season-entry {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-lg);
	}
	.template-picker h2,
	.starter-picker h2,
	.season-entry h2 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0 0 0.2rem 0;
	}
	.field-note {
		display: block;
		margin-top: var(--space-2xs);
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		font-weight: 400;
	}
	.picker-hint {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0 0 var(--space-md) 0;
	}
	.field-hint {
		margin: var(--space-sm) 0 0 0;
		font-size: 0.85rem;
	}
	.picker-row {
		display: flex;
		gap: var(--space-md);
		flex-wrap: wrap;
		align-items: flex-end;
	}
	.picker-field {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		min-width: min(12rem, 100%);
	}
	.picker-field span {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.picker-field select,
	.picker-field input {
		padding: 0.45rem 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.9rem;
		transition: border-color var(--transition-fast);
	}
	.picker-field select:focus-visible,
	.picker-field input:focus-visible {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
	}

	.or-rule {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin: var(--space-lg) 0;
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}
	.or-rule::before,
	.or-rule::after {
		content: '';
		flex: 1;
		height: 1px;
		background: var(--color-border);
	}

	.btn-spinner {
		display: inline-block;
		width: 0.85em;
		height: 0.85em;
		margin-inline-end: 0.35em;
		border: 2px solid color-mix(in srgb, currentColor 40%, transparent);
		border-top-color: currentColor;
		border-radius: 50%;
		vertical-align: -0.1em;
		animation: btn-spin 0.6s linear infinite;
	}
	@keyframes btn-spin {
		to { transform: rotate(360deg); }
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
