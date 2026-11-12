<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { activeFormatLocale, formatDuration } from '#lib/format/time.ts';
	import { formatDistance } from '#lib/format/units.svelte.ts';
	import { workoutKindLabel } from '#lib/training/workout_labels.ts';
	import {
		dismissPlanWorkoutLink,
		fetchPlanWorkoutLinkCandidates,
		markWorkoutCompleted,
		type PlanWorkoutLinkCandidate
	} from '#lib/core/data.ts';

	interface Props {
		runId: string;
		runOwnerId: string;
	}
	let { runId, runOwnerId }: Props = $props();

	const isOwner = $derived(auth.user?.id === runOwnerId);

	// The matcher links a run on its own local day only; a workout done a day
	// or two early or late is asked about here, never linked silently. "Not
	// this one" is remembered server-side and moves on to the next candidate.
	let candidates = $state<PlanWorkoutLinkCandidate[]>([]);
	let busy = $state(false);
	const candidate = $derived(candidates[0] ?? null);

	onMount(async () => {
		if (!isOwner) return;
		try {
			candidates = await fetchPlanWorkoutLinkCandidates(runId);
		} catch (e) {
			console.warn('plan workout link candidates failed', e);
			candidates = [];
		}
	});

	function dayName(iso: string): string {
		const [y, mo, d] = iso.split('-').map(Number);
		return new Date(Date.UTC(y, (mo ?? 1) - 1, d ?? 1)).toLocaleDateString(activeFormatLocale(), {
			weekday: 'long',
			timeZone: 'UTC'
		});
	}

	function target(c: PlanWorkoutLinkCandidate): string {
		if (c.target_distance_m != null && c.target_distance_m > 0) {
			return formatDistance(c.target_distance_m);
		}
		if (c.target_duration_seconds != null && c.target_duration_seconds > 0) {
			return formatDuration(c.target_duration_seconds);
		}
		return '';
	}

	async function confirm() {
		if (!candidate || busy) return;
		busy = true;
		try {
			await markWorkoutCompleted(candidate.workout_id, runId);
			showToast(m('planLink.linked'), 'success');
			candidates = [];
		} catch (e) {
			console.warn('plan workout link failed', e);
			showToast(m('planLink.failed'), 'error');
		} finally {
			busy = false;
		}
	}

	async function dismiss() {
		if (!candidate || busy) return;
		const dismissed = candidate;
		candidates = candidates.slice(1);
		try {
			await dismissPlanWorkoutLink(dismissed.workout_id, runId);
		} catch (e) {
			console.warn('plan workout dismiss failed', e);
			showToast(m('planLink.dismissFailed'), 'error');
		}
	}
</script>

{#if isOwner && candidate}
	{@const c = candidate}
	<section class="section plan-link" data-testid="plan-link-prompt">
		<p class="plan-link-text">
			{c.day_offset > 0
				? m('planLink.promptEarly', { day: dayName(c.scheduled_date) })
				: m('planLink.promptLate', { day: dayName(c.scheduled_date) })}
		</p>
		<p class="plan-link-detail" data-testid="plan-link-detail">
			{workoutKindLabel(c.kind)}{target(c) ? ` · ${target(c)}` : ''}
		</p>
		<div class="plan-link-actions">
			<button
				type="button"
				class="btn btn-outline btn-sm"
				onclick={dismiss}
				disabled={busy}
				data-testid="plan-link-dismiss"
			>
				{m('planLink.dismiss')}
			</button>
			<button
				type="button"
				class="btn btn-primary btn-sm"
				onclick={confirm}
				disabled={busy}
				data-testid="plan-link-confirm"
			>
				{m('planLink.confirm')}
			</button>
		</div>
	</section>
{/if}

<style>
	.plan-link-text {
		margin: 0 0 0.2rem;
		font-weight: 600;
	}
	.plan-link-detail {
		margin: 0 0 var(--space-sm);
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.plan-link-actions {
		display: flex;
		gap: 0.4rem;
		justify-content: flex-end;
		flex-wrap: wrap;
	}
</style>
