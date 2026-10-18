<script lang="ts" module>
	import { isWorkoutCompleted, isWorkoutSkipped } from '#lib/training/training.ts';
	import { missedWorkoutPrompt, type MissedPrompt } from '#lib/training/plan_missed_prompt.ts';
	import type { PlanWeek, PlanWorkout } from '#lib/types.ts';

	/// The prompt for a loaded plan's rows. The plan page reads it too, to open
	/// the make-up preview Home's "Make it up" links to.
	export function missedPromptFromRows(
		weeks: PlanWeek[],
		workouts: PlanWorkout[],
		today: string,
		answeredHere: ReadonlySet<string> = new Set()
	): MissedPrompt | null {
		const byWeek = new Map<string, PlanWorkout[]>();
		for (const wo of workouts) {
			const list = byWeek.get(wo.week_id) ?? [];
			list.push(wo);
			byWeek.set(wo.week_id, list);
		}
		return missedWorkoutPrompt({
			today,
			weeks: weeks.map((w) => {
				const list = byWeek.get(w.id) ?? [];
				const declared = w.target_volume_m ?? 0;
				return {
					weekIndex: w.week_index,
					phase: w.phase,
					plannedMetres:
						declared > 0
							? declared
							: list.reduce((s, x) => s + (x.kind !== 'rest' ? (x.target_distance_m ?? 0) : 0), 0),
					workouts: list.map((x) => ({
						id: x.id,
						scheduledDate: x.scheduled_date,
						kind: x.kind,
						targetDistanceM: x.target_distance_m,
						completed: isWorkoutCompleted(x),
						skipped: isWorkoutSkipped(x),
						answered: x.missed_ack_at != null || answeredHere.has(x.id)
					}))
				};
			})
		});
	}
</script>

<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import { answerMissedWorkouts } from '#lib/core/data.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { fmtKm } from '#lib/format/units.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { parseISO } from '#lib/training/training.ts';
	import { workoutKindLabel } from '#lib/training/workout_labels.ts';

	/// Asks once about the runner's most recent missed workout
	/// (`missedWorkoutPrompt`, decisions § 2122), on Home's plan hero and the
	/// plan page's Today slot. The host shows it only to the owner of an
	/// active, unfinished plan. "Let it go" records the answer here; "Make it
	/// up" goes to the host's make-up preview, which records it on apply.
	interface Props {
		planId: string;
		weeks: PlanWeek[];
		workouts: PlanWorkout[];
		/// The runner's local today (YYYY-MM-DD).
		today: string;
		/// The plan page opens its preview in place.
		onmakeup?: (prompt: MissedPrompt) => void;
		/// Home links to the plan page, which opens the preview there.
		makeUpHref?: string;
	}
	let { planId, weeks, workouts, today, onmakeup, makeUpHref }: Props = $props();

	let answered = $state<Set<string>>(new Set());
	let busy = $state(false);

	/// A failure here must not take the Today card with it, so it reads as
	/// nothing to ask.
	let prompt = $derived.by((): MissedPrompt | null => {
		try {
			return missedPromptFromRows(weeks, workouts, today, answered);
		} catch (e) {
			console.error('Reading the missed-workout prompt failed', { message: thrownMessage(e) });
			return null;
		}
	});

	let recommendMakeUp = $derived(prompt?.makeUp != null);

	function dayLabel(iso: string): string {
		return parseISO(iso).toLocaleDateString(activeFormatLocale(), {
			weekday: 'long',
			day: 'numeric',
			month: 'short'
		});
	}

	function body(p: MissedPrompt): string {
		if (p.makeUp) {
			return m('missedPrompt.makeUpBody', {
				from: fmtKm(p.makeUp.fromMetres),
				to: fmtKm(p.makeUp.toMetres)
			});
		}
		switch (p.advice.reason) {
			case 'key_session':
				return m('missedPrompt.coveredBody');
			case 'taper':
				return m('missedPrompt.taperBody');
			case 'recovery_soon':
				return m('missedPrompt.recoveryBody');
			case 'not_long_run':
				return m('missedPrompt.letGoBody');
		}
	}

	async function letGo(): Promise<void> {
		const p = prompt;
		if (!p || busy) return;
		busy = true;
		try {
			await answerMissedWorkouts(planId, [p.workoutId]);
			answered = new Set([...answered, p.workoutId]);
			showToast(m('missedPrompt.letGoDone'));
		} catch (e) {
			showToast(m('missedPrompt.saveFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			busy = false;
		}
	}
</script>

{#if prompt}
	<section class="missed-prompt" aria-labelledby="missed-prompt-title" data-testid="missed-prompt">
		<span class="material-symbols missed-prompt-icon" aria-hidden="true">event_busy</span>
		<div class="missed-prompt-body">
			<h3 id="missed-prompt-title">
				{m('missedPrompt.title', { kind: workoutKindLabel(prompt.kind), day: dayLabel(prompt.scheduledDate) })}
			</h3>
			<p data-testid="missed-prompt-body">{body(prompt)}</p>
		</div>
		<div class="missed-prompt-actions">
			{#if prompt.makeUp}
				{#if makeUpHref}
					<a class="btn btn-primary btn-sm" href={makeUpHref} data-testid="missed-prompt-make-up">
						{m('missedPrompt.makeUp')}
						<span class="missed-prompt-rec" data-testid="missed-prompt-recommended">{m('missedPrompt.recommended')}</span>
					</a>
				{:else}
					<button
						type="button"
						class="btn btn-primary btn-sm"
						disabled={busy}
						onclick={() => prompt && onmakeup?.(prompt)}
						data-testid="missed-prompt-make-up"
					>
						{m('missedPrompt.makeUp')}
						<span class="missed-prompt-rec" data-testid="missed-prompt-recommended">{m('missedPrompt.recommended')}</span>
					</button>
				{/if}
			{/if}
			<button
				type="button"
				class="btn btn-sm {recommendMakeUp ? 'btn-secondary' : 'btn-primary'}"
				disabled={busy}
				onclick={letGo}
				data-testid="missed-prompt-let-go"
			>
				{m('missedPrompt.letGo')}
				{#if !recommendMakeUp}
					<span class="missed-prompt-rec" data-testid="missed-prompt-recommended">{m('missedPrompt.recommended')}</span>
				{/if}
			</button>
		</div>
	</section>
{/if}

<style>
	.missed-prompt {
		display: flex;
		align-items: flex-start;
		gap: var(--space-md);
		flex-wrap: wrap;
		padding: var(--space-md) var(--space-lg);
		background: color-mix(in srgb, var(--color-primary) 6%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-primary) 26%, var(--color-border));
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.missed-prompt-icon {
		color: var(--color-primary);
	}
	.missed-prompt-body {
		flex: 1 1 10rem;
		min-width: 0;
		overflow-wrap: anywhere;
	}
	.missed-prompt-body h3 {
		margin: 0;
		font-size: 1rem;
	}
	.missed-prompt-body p {
		margin: var(--space-xs) 0 0;
		color: var(--color-text-secondary);
	}
	.missed-prompt-actions {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
		align-self: center;
		min-width: 0;
	}
	.missed-prompt-actions .btn {
		white-space: normal;
		text-align: start;
		flex-wrap: wrap;
		max-width: 100%;
	}
	.missed-prompt-rec {
		font-size: 0.75rem;
		font-weight: 600;
		opacity: 0.9;
		margin-inline-start: var(--space-xs);
	}
</style>
