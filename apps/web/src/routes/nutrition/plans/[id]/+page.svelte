<script lang="ts">
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { smartBack } from '#lib/util/smart_back.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import {
		deleteNutritionPlan,
		fetchMyNutritionAssignmentsWithError,
		fetchNutritionPlan,
		followNutritionPlan,
		planAssignmentOf,
		stopFollowingNutritionPlan,
	} from '#lib/core/data.ts';
	import { activeAssignmentForDate } from '#lib/nutrition/meal_plan.ts';
	import { isoDateOf } from '#lib/nutrition/diary_day.ts';
	import { formatDate } from '#lib/format/time.ts';
	import type { NutritionPlan, NutritionPlanAssignment } from '#lib/types.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import Modal from '#lib/components/Modal.svelte';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import DangerZone from '#lib/components/DangerZone.svelte';
	import MealPlanEditor from '#lib/components/MealPlanEditor.svelte';

	let plan = $state<NutritionPlan | null>(null);
	let assignments = $state<NutritionPlanAssignment[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let busy = $state(false);
	let editing = $state(false);
	let confirmingDelete = $state(false);

	const back = smartBack();
	const planId = $derived(page.params.id ?? '');
	const isAuthor = $derived(!!plan && !!auth.user && plan.author_id === auth.user.id);
	const today = $derived(isoDateOf(new Date()));
	const current = $derived.by(() => {
		const a = activeAssignmentForDate(assignments.map(planAssignmentOf), today);
		return a ? (assignments.find((x) => x.id === a.id) ?? null) : null;
	});
	const followingThis = $derived(current !== null && current.plan_id === planId);

	async function load() {
		loading = true;
		loadError = null;
		try {
			const [planRes, assignRes] = await Promise.all([
				fetchNutritionPlan(planId),
				fetchMyNutritionAssignmentsWithError(),
			]);
			const error = planRes.error ?? assignRes.error;
			if (error !== null) {
				loadError = error;
				plan = null;
				return;
			}
			plan = planRes.plan;
			assignments = assignRes.assignments;
		} catch (e) {
			loadError = thrownMessage(e);
			plan = null;
		} finally {
			loading = false;
		}
	}

	onMount(async () => {
		await auth.ready();
		if (!auth.user) {
			loading = false;
			return;
		}
		await load();
	});

	async function follow() {
		if (!plan || busy) return;
		busy = true;
		try {
			await followNutritionPlan(plan.id, today, assignments);
			showToast(m('nutrition.plan.followed', { name: plan.title }), 'success');
		} catch (e) {
			showToast(m('nutrition.plan.followFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			busy = false;
		}
		await load();
	}

	async function stop() {
		if (!plan || !current || busy) return;
		busy = true;
		try {
			await stopFollowingNutritionPlan(current, today);
			showToast(m('nutrition.plan.stopped', { name: plan.title }), 'success');
		} catch (e) {
			showToast(m('nutrition.plan.stopFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			busy = false;
		}
		await load();
	}

	async function doDelete() {
		if (!plan) return;
		try {
			await deleteNutritionPlan(plan.id);
			confirmingDelete = false;
			showToast(m('nutrition.plan.deleted'), 'success');
			await goto('/nutrition');
		} catch (e) {
			confirmingDelete = false;
			showToast(m('nutrition.plan.deleteFailed', { error: thrownMessage(e) }), 'error');
		}
	}

	function grams(v: number | null): string {
		return v === null ? m('nutrition.targets.unset') : `${Math.round(v)} g`;
	}
</script>

<svelte:head><title>{plan?.title ?? m('nutrition.plan.sectionTitle')} — Threkir</title></svelte:head>

<div class="page">
	<a class="back-link" href="/nutrition" onclick={back.handle}>
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('nutrition.plan.back')}
	</a>

	{#if loading}
		<p class="sr-only" role="status">{m('nutrition.loading')}</p>
	{:else if loadError !== null}
		<div class="load-error" role="alert" data-testid="plan-load-error">
			<p>{m('nutrition.plan.loadFailed')}</p>
			{#if loadError}<p class="load-error-detail">{loadError}</p>{/if}
			<button class="btn btn-outline" type="button" onclick={() => void load()}>{m('nutrition.retry')}</button>
		</div>
	{:else if !plan}
		<p class="not-found" data-testid="plan-not-found">{m('nutrition.plan.notFound')}</p>
	{:else}
		<header class="detail-header">
			<div>
				<h1 data-testid="plan-detail-title">{plan.title}</h1>
				<p class="head-sub">{m(`nutrition.plan.phase_${plan.goal_phase}`)}</p>
				{#if followingThis && current}
					<p class="following" data-testid="plan-detail-following">
						<span class="material-symbols" aria-hidden="true">check</span>
						{m('nutrition.plan.followingSince', { date: formatDate(current.start_date) })}
					</p>
				{/if}
			</div>
			<div class="head-actions">
				{#if followingThis}
					<button class="btn btn-outline" type="button" disabled={busy} onclick={() => void stop()} data-testid="plan-stop">
						{m('nutrition.plan.stopFollowing')}
					</button>
				{:else}
					<button class="btn btn-primary" type="button" disabled={busy} onclick={() => void follow()} data-testid="plan-detail-follow">
						{m('nutrition.plan.follow')}
					</button>
				{/if}
				{#if isAuthor}
					<button class="btn btn-secondary" type="button" onclick={() => (editing = true)} data-testid="plan-edit">
						<span class="material-symbols" aria-hidden="true">edit</span>
						{m('nutrition.plan.edit')}
					</button>
				{/if}
			</div>
		</header>

		<section class="card-elevated targets-card" data-testid="plan-targets">
			<table class="targets-table">
				<thead>
					<tr>
						<th scope="col"><span class="visually-hidden">{m('nutrition.plan.macroColumn')}</span></th>
						<th scope="col">{m('nutrition.plan.everyDayHeading')}</th>
						<th scope="col">{m('nutrition.plan.trainingColumn')}</th>
					</tr>
				</thead>
				<tbody>
					<tr>
						<th scope="row">{m('nutrition.calories')}</th>
						<td>{Math.round(plan.target_calories)} kcal</td>
						<td>{Math.round(plan.training_calories ?? plan.target_calories)} kcal</td>
					</tr>
					<tr>
						<th scope="row">{m('nutrition.protein')}</th>
						<td>{grams(plan.target_protein_g)}</td>
						<td>{grams(plan.target_protein_g)}</td>
					</tr>
					<tr>
						<th scope="row">{m('nutrition.carbs')}</th>
						<td>{grams(plan.target_carbs_g)}</td>
						<td>{grams(plan.training_carbs_g ?? plan.target_carbs_g)}</td>
					</tr>
					<tr>
						<th scope="row">{m('nutrition.fat')}</th>
						<td>{grams(plan.target_fat_g)}</td>
						<td>{grams(plan.target_fat_g)}</td>
					</tr>
				</tbody>
			</table>
			<p class="section-hint">{m('nutrition.plan.trainingHint')}</p>
		</section>

		{#if plan.notes}
			<p class="notes">{plan.notes}</p>
		{/if}

		{#if isAuthor}
			<DangerZone heading={m('nutrition.plan.dangerHeading')} description={m('nutrition.plan.dangerDescription')}>
				<button class="btn btn-danger" type="button" onclick={() => (confirmingDelete = true)} data-testid="plan-delete">
					{m('nutrition.plan.deletePlan')}
				</button>
			</DangerZone>
		{/if}
	{/if}
</div>

{#if plan}
	<Modal open={editing} title={m('nutrition.plan.editTitle')} narrow onclose={() => (editing = false)}>
		{#if editing}
			<MealPlanEditor
				{plan}
				onsaved={(saved) => {
					plan = saved;
					editing = false;
					showToast(m('nutrition.plan.saved'), 'success');
				}}
				oncancel={() => (editing = false)}
			/>
		{/if}
	</Modal>
{/if}

<ConfirmDialog
	open={confirmingDelete}
	title={m('nutrition.plan.deleteTitle')}
	message={m('nutrition.plan.deleteMessage', { name: plan?.title ?? '' })}
	confirmLabel={m('nutrition.plan.deletePlan')}
	onconfirm={doDelete}
	oncancel={() => (confirmingDelete = false)}
	danger
/>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		max-width: 48rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.detail-header {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-md);
	}
	.detail-header h1 {
		margin: 0;
		overflow-wrap: anywhere;
	}
	.head-sub {
		margin: var(--space-2xs) 0 0;
		color: var(--color-text-secondary);
	}
	.following {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		margin: var(--space-xs) 0 0;
		font-weight: 600;
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
	}
	.head-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.targets-table {
		width: 100%;
		border-collapse: collapse;
		font-variant-numeric: tabular-nums;
	}
	.targets-table th,
	.targets-table td {
		text-align: start;
		padding: var(--space-xs) var(--space-sm);
		border-bottom: 1px solid var(--color-border);
	}
	.targets-table thead th {
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
		font-weight: 600;
	}
	.section-hint {
		margin: var(--space-sm) 0 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.notes {
		margin: 0;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
	.load-error {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-sm);
	}
	.load-error p {
		margin: 0;
	}
	.load-error-detail {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
</style>
