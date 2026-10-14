<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { NutritionPlan } from '#lib/types.ts';
	import NutritionPlanCard from './NutritionPlanCard.svelte';

	interface Props {
		plans: NutritionPlan[];
		/// The plan governing the viewed day, if any.
		followingPlanId: string | null;
		/// Following is a today-onward action, so it is offered only on today.
		canFollow: boolean;
		busyPlanId: string | null;
		onfollow: (plan: NutritionPlan) => void;
		onnew: () => void;
	}

	let { plans, followingPlanId, canFollow, busyPlanId, onfollow, onnew }: Props = $props();
</script>

{#if plans.length > 0}
	<section class="card-elevated plans-card" data-testid="nutrition-plans">
		<div class="card-head">
			<span class="section-label">{m('nutrition.plan.sectionTitle')}</span>
			<button class="btn btn-outline btn-sm" type="button" onclick={onnew} data-testid="plan-new">
				<span class="material-symbols" aria-hidden="true">add</span>
				{m('nutrition.plan.new')}
			</button>
		</div>
		<ul class="plan-list">
			{#each plans as plan (plan.id)}
				<NutritionPlanCard
					{plan}
					following={plan.id === followingPlanId}
					{canFollow}
					busy={busyPlanId !== null}
					{onfollow}
				/>
			{/each}
		</ul>
	</section>
{/if}

<style>
	.plans-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.plan-list {
		list-style: none;
		margin: 0;
		padding: 0;
	}
</style>
