<script lang="ts">
	// The suggested changes to coach-assigned plans between the signed-in user
	// and one other person (the DM thread) or on one plan (the plan page),
	// issue #1215 Phase 2, decisions § 2382. Pending requests first, then the
	// three most recent decided ones. Renders nothing when there are none.
	import PlanChangeRequestCard from '#lib/components/PlanChangeRequestCard.svelte';
	import {
		fetchPlanChangeRequests,
		fetchPlanChangeTargets,
		type PlanChangeRequest,
	} from '#lib/core/data.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { planChangeIds, planChangeLines, type PlanChangeLines } from '#lib/training/plan_change.ts';

	interface Props {
		scope: { planId: string } | { partnerId: string };
		onchanged?: () => void | Promise<void>;
	}
	let { scope, onchanged }: Props = $props();

	const DECIDED_SHOWN = 3;

	let items = $state<{ request: PlanChangeRequest; lines: PlanChangeLines }[]>([]);
	let failed = $state(false);
	const scopeKey = $derived('planId' in scope ? `plan:${scope.planId}` : `partner:${scope.partnerId}`);

	async function load(key: string): Promise<void> {
		try {
			const all = await fetchPlanChangeRequests(scope);
			const pending = all.filter((r) => r.status === 'pending');
			const decided = all.filter((r) => r.status !== 'pending').slice(0, DECIDED_SHOWN);
			const shown = [...pending, ...decided];
			const workoutIds = new Set<string>();
			const weekIds = new Set<string>();
			for (const r of shown) {
				const ids = planChangeIds(r.workouts, r.weeks);
				ids.workoutIds.forEach((id) => workoutIds.add(id));
				ids.weekIds.forEach((id) => weekIds.add(id));
			}
			const targets = await fetchPlanChangeTargets([...workoutIds], [...weekIds]);
			if (key !== scopeKey) return;
			items = shown.map((request) => ({
				request,
				lines: planChangeLines(request.workouts, request.weeks, targets.workouts, targets.weeks),
			}));
			failed = false;
		} catch (e) {
			if (key !== scopeKey) return;
			console.error('[plan change] load failed', e);
			failed = true;
		}
	}

	$effect(() => {
		const key = scopeKey;
		items = [];
		failed = false;
		if (auth.user) void load(key);
	});

	async function changed(): Promise<void> {
		await load(scopeKey);
		await onchanged?.();
	}
</script>

{#if failed}
	<p class="load-failed" role="alert" data-testid="plan-change-load-failed">
		{m('planChange.loadFailed')}
		<button type="button" class="btn btn-secondary btn-sm" onclick={() => void load(scopeKey)}>
			{m('planChange.retry')}
		</button>
	</p>
{:else if items.length > 0 && auth.user}
	<div class="plan-changes" data-testid="plan-change-requests">
		{#each items as item (item.request.id)}
			<PlanChangeRequestCard
				request={item.request}
				lines={item.lines}
				viewerId={auth.user.id}
				onchanged={changed}
			/>
		{/each}
	</div>
{/if}

<style>
	.plan-changes {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin: 0.5rem 0;
	}
	.load-failed {
		color: var(--color-danger-text);
		font-size: 0.9rem;
		display: flex;
		gap: 0.5rem;
		align-items: center;
		flex-wrap: wrap;
	}
</style>
