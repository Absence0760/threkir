<script lang="ts" module>
	import { isWorkoutCompleted } from '#lib/training/training.ts';
	import {
		structureRunDistanceM,
		walkRunGraduation,
		type WalkRunGraduation
	} from '#lib/training/walk_run_graduation.ts';
	import type { PlanWorkout } from '#lib/types.ts';

	/// The graduation for a loaded plan's rows, or null.
	export function graduationFromRows(workouts: PlanWorkout[]): WalkRunGraduation | null {
		return walkRunGraduation(
			workouts.map((w) => ({
				id: w.id,
				kind: w.kind,
				scheduled_date: w.scheduled_date,
				done: isWorkoutCompleted(w),
				runDistanceM: structureRunDistanceM(w.structure)
			}))
		);
	}
</script>

<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';

	/// The couch-to-5K completion moment on the plan page: shown to the owner
	/// once the plan's last walk-run session is done, with the next step. It
	/// is a header only; a general end-of-plan recap may sit directly under
	/// it and carries the numbers, so this card repeats none of them.
	interface Props {
		graduation: WalkRunGraduation;
	}
	let { graduation }: Props = $props();
</script>

<section class="graduation" aria-labelledby="walk-run-graduation-title" data-testid="walk-run-graduation">
	<span class="material-symbols graduation-icon" aria-hidden="true">emoji_events</span>
	<div class="graduation-body">
		<h2 id="walk-run-graduation-title">{m('walkRunGraduation.title')}</h2>
		<p data-testid="walk-run-graduation-body">
			{graduation.ranFiveK ? m('walkRunGraduation.bodyFiveK') : m('walkRunGraduation.bodyFinished')}
		</p>
		<h3>{m('walkRunGraduation.nextTitle')}</h3>
		<div class="graduation-next">
			<a
				class="btn btn-primary btn-sm"
				href="/plans/new?type=training&goal=10k"
				data-testid="walk-run-graduation-ten-k"
			>
				{m('walkRunGraduation.tenK')}
			</a>
			<p>{m('walkRunGraduation.keepRunning')}</p>
		</div>
	</div>
</section>

<style>
	.graduation {
		display: flex;
		align-items: flex-start;
		gap: var(--space-md);
		padding: var(--space-lg);
		background: color-mix(in srgb, var(--color-primary) 10%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-primary) 34%, var(--color-border));
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.graduation-icon {
		color: var(--color-primary);
		font-size: 2rem;
	}
	.graduation-body {
		flex: 1 1 auto;
		min-width: 0;
		overflow-wrap: anywhere;
	}
	.graduation-body h2 {
		margin: 0;
		font-size: 1.25rem;
	}
	.graduation-body h3 {
		margin: var(--space-md) 0 var(--space-xs);
		font-size: 0.95rem;
	}
	.graduation-body p {
		margin: var(--space-xs) 0 0;
		color: var(--color-text-secondary);
	}
	.graduation-next {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm) var(--space-md);
	}
	.graduation-next p {
		flex: 1 1 14rem;
		margin: 0;
	}
	.graduation-next .btn {
		white-space: normal;
		max-width: 100%;
	}
</style>
