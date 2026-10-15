<script lang="ts">
	import { goto } from '$app/navigation';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { fetchMyNutritionAssignmentsWithError, followNutritionPlan } from '#lib/core/data.ts';
	import { isoDateOf } from '#lib/nutrition/diary_day.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { NutritionPlan } from '#lib/types.ts';
	import MealPlanEditor from '#lib/components/MealPlanEditor.svelte';

	async function onSaved(plan: NutritionPlan, follow: boolean) {
		if (follow) {
			try {
				const current = await fetchMyNutritionAssignmentsWithError();
				if (current.error !== null) throw new Error(current.error);
				await followNutritionPlan(plan.id, isoDateOf(new Date()), current.assignments);
				showToast(m('nutrition.plan.followed', { name: plan.title }), 'success');
			} catch (e) {
				showToast(m('nutrition.plan.followFailed', { error: thrownMessage(e) }), 'error');
			}
		} else {
			showToast(m('nutrition.plan.saved'), 'success');
		}
		await goto(`/nutrition/plans/${plan.id}`);
	}
</script>

<svelte:head><title>{m('nutrition.plan.newTitle')} — Threkir</title></svelte:head>

<div class="page">
	<header class="page-header">
		<a class="back-link" href="/nutrition">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{m('nutrition.plan.back')}
		</a>
		<h1>{m('nutrition.plan.newTitle')}</h1>
	</header>

	<div class="editor-wrap">
		<MealPlanEditor offerFollow onsaved={(p, f) => void onSaved(p, f)} oncancel={() => goto('/nutrition')} />
	</div>
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 48rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.editor-wrap {
		margin-top: var(--space-md);
	}
</style>
