<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import { finishPlan } from '#lib/core/data.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { formatDate } from '#lib/format/time.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';

	/// An active plan whose last day has passed (`isPlanFinished`). Nothing
	/// writes `completed` on its own, so the runner files the plan here; until
	/// then it keeps reading as their plan, which is what makes the prompt
	/// worth showing on Home and on the plan itself.
	interface Props {
		plan: { id: string; name: string; end_date: string };
		onfinished: () => void | Promise<void>;
	}
	let { plan, onfinished }: Props = $props();

	let busy = $state(false);

	async function finish(): Promise<void> {
		if (busy) return;
		busy = true;
		try {
			await finishPlan(plan.id);
			showToast(m('planFinish.done', { name: plan.name }));
			await onfinished();
		} catch (e) {
			showToast(m('planFinish.failed', { error: thrownMessage(e) }), 'error');
		} finally {
			busy = false;
		}
	}
</script>

<section class="finish-plan" aria-labelledby="finish-plan-title" data-testid="finish-plan-prompt">
	<span class="material-symbols finish-plan-icon" aria-hidden="true">check_circle</span>
	<div class="finish-plan-body">
		<h3 id="finish-plan-title">{m('planFinish.title', { name: plan.name })}</h3>
		<p>{m('planFinish.body', { date: formatDate(plan.end_date) })}</p>
	</div>
	<button type="button" class="btn btn-primary btn-sm" disabled={busy} onclick={finish}>
		{busy ? m('planFinish.finishing') : m('planFinish.action')}
	</button>
</section>

<style>
	.finish-plan {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
		padding: var(--space-md) var(--space-lg);
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-primary) 30%, var(--color-border));
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.finish-plan-icon {
		color: var(--color-primary);
	}
	.finish-plan-body {
		flex: 1;
		min-width: 12rem;
	}
	.finish-plan-body h3 {
		margin: 0;
		font-size: 1rem;
	}
	.finish-plan-body p {
		margin: var(--space-xs) 0 0;
		color: var(--color-text-secondary);
	}
</style>
