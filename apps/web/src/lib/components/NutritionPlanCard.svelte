<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { NutritionPlan } from '#lib/types.ts';

	interface Props {
		plan: NutritionPlan;
		following: boolean;
		canFollow: boolean;
		busy: boolean;
		onfollow: (plan: NutritionPlan) => void;
	}

	let { plan, following, canFollow, busy, onfollow }: Props = $props();
</script>

<li class="plan-row" data-testid="nutrition-plan-row">
	<a class="plan-main" href={`/nutrition/plans/${plan.id}`}>
		<span class="plan-title">{plan.title}</span>
		<span class="plan-meta">
			{m(`nutrition.plan.phase_${plan.goal_phase}`)} · {m('nutrition.plan.kcalPerDay', { n: Math.round(plan.target_calories) })}
		</span>
	</a>
	{#if following}
		<span class="following-badge" data-testid="plan-following-badge">
			<span class="material-symbols" aria-hidden="true">check</span>
			{m('nutrition.plan.followingBadge')}
		</span>
	{:else if canFollow}
		<button
			class="btn btn-primary btn-sm"
			type="button"
			disabled={busy}
			onclick={() => onfollow(plan)}
			aria-label={m('nutrition.plan.followNamed', { name: plan.title })}
			data-testid="plan-follow"
		>{m('nutrition.plan.follow')}</button>
	{/if}
</li>

<style>
	.plan-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) 0;
		border-top: 1px solid var(--color-border);
	}
	.plan-row:first-child {
		border-top: none;
	}
	.plan-main {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
		color: inherit;
		text-decoration: none;
	}
	.plan-main:hover .plan-title {
		text-decoration: underline;
	}
	.plan-title {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.plan-meta {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.following-badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		font-weight: 600;
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
	}
	.following-badge .material-symbols {
		font-size: 1rem;
	}
</style>
