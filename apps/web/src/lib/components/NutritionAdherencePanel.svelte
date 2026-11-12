<script lang="ts">
	import type { DayAdherence, MacroVerdict } from '#lib/nutrition/nutrition_adherence.ts';
	import type { MacroKind } from '#lib/nutrition/nutrition_budget.ts';
	import { m } from '#lib/i18n/store.svelte.ts';

	interface Props {
		adherence: DayAdherence;
		/// Today is still being logged, so a partial day reads as in progress.
		isToday: boolean;
	}

	let { adherence, isToday }: Props = $props();

	const ICON: Record<MacroVerdict, string> = {
		met: 'check',
		under: 'arrow_downward',
		over: 'arrow_upward',
	};
	const UNIT: Record<MacroKind, string> = { calories: 'kcal', protein: 'g', carbs: 'g', fat: 'g' };
	const LABEL: Record<MacroKind, 'nutrition.calories' | 'nutrition.protein' | 'nutrition.carbs' | 'nutrition.fat'> = {
		calories: 'nutrition.calories',
		protein: 'nutrition.protein',
		carbs: 'nutrition.carbs',
		fat: 'nutrition.fat',
	};
</script>

<section class="card-elevated adherence-card" data-testid="plan-adherence">
	<div class="card-head">
		<span class="section-label">{m('nutrition.adherence.heading')}</span>
		<span
			class="verdict-pill verdict-{adherence.verdict}"
			data-testid="plan-adherence-verdict"
			data-verdict={adherence.verdict}
		>
			<span class="material-symbols" aria-hidden="true">{adherence.verdict === 'on_target'
					? 'check'
					: adherence.verdict === 'partial'
						? 'hourglass_empty'
						: 'error'}</span>
			{m(`nutrition.adherence.verdict_${adherence.verdict}`)}
		</span>
	</div>
	{#if adherence.verdict === 'partial'}
		<p class="section-hint" data-testid="plan-adherence-partial">
			{m(isToday ? 'nutrition.adherence.partialToday' : 'nutrition.adherence.partialPast')}
		</p>
	{:else}
		<ul class="macro-verdicts">
			{#each adherence.perMacro as row (row.kind)}
				<li class="macro-verdict verdict-row-{row.verdict}" data-testid={`plan-adherence-${row.kind}`} data-verdict={row.verdict}>
					<span class="material-symbols verdict-icon" aria-hidden="true">{ICON[row.verdict]}</span>
					<span class="macro-name">{m(LABEL[row.kind])}</span>
					<span class="macro-amount">{m('nutrition.adherence.amount', { actual: Math.round(row.actual), target: row.target, unit: UNIT[row.kind] })}</span>
					<span class="macro-state">{m(`nutrition.adherence.state_${row.verdict}`)}</span>
				</li>
			{/each}
		</ul>
	{/if}
</section>

<style>
	.adherence-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.verdict-pill {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		padding: 0.15rem 0.6rem;
		border-radius: 999px;
		font-size: var(--font-size-section-label);
		font-weight: 600;
		background: var(--color-fill-subtle);
		color: var(--color-text);
	}
	.verdict-pill .material-symbols {
		font-size: 1rem;
	}
	.verdict-on_target {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
		background: color-mix(in srgb, var(--color-success) 16%, transparent);
	}
	.verdict-off_target {
		color: var(--color-warning-text);
		background: var(--color-warning-light);
	}
	.section-hint {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.macro-verdicts {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.macro-verdict {
		display: grid;
		grid-template-columns: auto 1fr auto auto;
		align-items: center;
		gap: var(--space-sm);
		font-size: 0.85rem;
	}
	.verdict-icon {
		font-size: 1.1rem;
	}
	.verdict-row-met .verdict-icon {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
	}
	.verdict-row-under .verdict-icon,
	.verdict-row-over .verdict-icon {
		color: var(--color-warning-text);
	}
	.macro-name {
		font-weight: 600;
	}
	.macro-amount {
		font-variant-numeric: tabular-nums;
	}
	.macro-state {
		color: var(--color-text-secondary);
	}
</style>
