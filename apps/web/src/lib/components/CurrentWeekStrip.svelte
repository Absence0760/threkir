<script lang="ts">
	import type { PlanWorkout, PlanWeek } from '#lib/types.ts';
	import { addDays, parseISO, formatISO } from '#lib/training/training.ts';
	import { planWorkoutProgress } from '#lib/training/plan_progress.ts';
	import { workoutKindLabel, workoutKindShortLabel } from '#lib/training/workout_labels.ts';
	import { planWorkoutAriaLabel, planWorkoutStatusOf } from '#lib/training/plan_workout_view.ts';
	import { planWorkoutStatusLook } from '#lib/training/plan_workout_status_style.ts';
	import { workoutKindMarkVar } from '#lib/training/workout_kind_color.ts';
	import { fmtKm } from '#lib/format/units.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { WeekStart } from '#lib/format/calendar.ts';

	type Props = {
		/// The plan's start date (yyyy-mm-dd). The strip's 7-day window is
		/// derived from `currentWeek.week_index * 7` off this — NOT from the
		/// real calendar week — so its completion count matches the week card.
		startDate: string;
		/// The current week row (or null when the plan hasn't started / has
		/// no weeks). Drives both the day window and the displayed workouts.
		currentWeek: PlanWeek | null;
		/// The workouts belonging to `currentWeek` (the same list the week
		/// card counts), keyed onto days by `scheduled_date`.
		weekWorkouts: PlanWorkout[];
		/// Today's local ISO date — highlights the matching cell.
		today: string;
		/// First day of the week for display ordering only.
		weekStart?: WeekStart;
		/// Called when a workout cell is clicked (opens the inline editor).
		onSelect?: (workout: PlanWorkout) => void;
		/// Heading override: before the plan starts the strip shows its first
		/// week, which is not "This week".
		title?: string;
	};
	let {
		startDate,
		currentWeek,
		weekWorkouts,
		today,
		weekStart = 'monday',
		onSelect,
		title
	}: Props = $props();

	const DOW_KEYS = [
		'planDetail.dowSun',
		'planDetail.dowMon',
		'planDetail.dowTue',
		'planDetail.dowWed',
		'planDetail.dowThu',
		'planDetail.dowFri',
		'planDetail.dowSat'
	] as const;

	let workoutByDate = $derived.by(() => {
		const map = new Map<string, PlanWorkout>();
		for (const w of weekWorkouts) map.set(w.scheduled_date, w);
		return map;
	});

	type Cell = { iso: string; dow: string; workout: PlanWorkout | null };

	/// The seven cells of `currentWeek`, anchored to `start_date +
	/// week_index*7` and re-ordered for display by `weekStart`. The window
	/// is the plan's week bucket, so the workouts shown are exactly the ones
	/// the week card counts — ordering is presentation only.
	let cells = $derived.by<Cell[]>(() => {
		if (!currentWeek) return [];
		const weekStartD = addDays(parseISO(startDate), currentWeek.week_index * 7);
		const out: Cell[] = [];
		for (let i = 0; i < 7; i++) {
			const d = addDays(weekStartD, i);
			const iso = formatISO(d);
			out.push({ iso, dow: m(DOW_KEYS[d.getDay()]), workout: workoutByDate.get(iso) ?? null });
		}
		// Re-order so the row begins on the chosen week start (display only).
		if (weekStart === 'sunday') {
			const idx = out.findIndex((c) => parseISO(c.iso).getDay() === 0);
			if (idx > 0) return [...out.slice(idx), ...out.slice(0, idx)];
		}
		return out;
	});

	let weekProgress = $derived(planWorkoutProgress(weekWorkouts));
	let doneCount = $derived(weekProgress.completed);
	let activeCount = $derived(weekProgress.total);
</script>

{#if currentWeek}
	<section class="strip" aria-label={title ?? m('planDetail.currentWeek')}>
		<div class="strip-head">
			<h2 class="strip-title">{title ?? m('planDetail.currentWeek')}</h2>
			<span class="strip-count">
				{doneCount}<em> / {activeCount}</em> {m('planDetail.done')}
			</span>
		</div>
		<div class="strip-row">
			{#each cells as c (c.iso)}
				{@const wo = c.workout}
				{#if wo}
					{@const status = planWorkoutStatusOf(wo, today)}
					{@const look = planWorkoutStatusLook(status)}
					<svelte:element
						this={onSelect ? 'button' : 'a'}
						role={onSelect ? 'button' : 'link'}
						type={onSelect ? 'button' : undefined}
						onclick={onSelect ? () => onSelect(wo) : undefined}
						class="day has-workout"
						class:today={c.iso === today}
						class:rest={wo.kind === 'rest'}
						data-status={status}
						style="--kind: {workoutKindMarkVar(wo.kind)}"
						style:--wo-bg={look.bg}
						style:--wo-border={look.border}
						style:--wo-border-style={look.borderStyle}
						style:--wo-glyph={look.glyphColor}
						aria-label={planWorkoutAriaLabel(
							wo,
							today,
							{
								day: c.dow,
								kind: workoutKindLabel(wo.kind),
								distance:
									wo.target_distance_m != null && wo.kind !== 'rest'
										? fmtKm(wo.target_distance_m, 1)
										: null
							},
							m
						)}
					>
						<span class="dow" aria-hidden="true">{c.dow}</span>
						<span
							class="kind"
							aria-hidden="true"
							data-short={workoutKindShortLabel(wo.kind)}
						><span class="kind-full">{workoutKindLabel(wo.kind)}</span></span>
						{#if wo.target_distance_m != null && wo.kind !== 'rest'}
							<span class="dist" aria-hidden="true">{fmtKm(wo.target_distance_m, 1)}</span>
						{/if}
						{#if look.glyph}
							<span class="material-symbols check" aria-hidden="true">{look.glyph}</span>
						{/if}
					</svelte:element>
				{:else}
					<div class="day empty" class:today={c.iso === today}>
						<span class="dow">{c.dow}</span>
					</div>
				{/if}
			{/each}
		</div>
	</section>
{/if}

<style>
	.strip {
		margin-bottom: var(--space-md);
	}
	.strip-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		margin-bottom: var(--space-xs);
	}
	.strip-title {
		font-size: 0.95rem;
		font-weight: 600;
		margin: 0;
	}
	.strip-count {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.strip-count em {
		font-style: normal;
		color: var(--color-text-tertiary);
	}
	.strip-row {
		display: grid;
		grid-template-columns: repeat(7, minmax(0, 1fr));
		gap: 0.35rem;
	}
	.day {
		min-height: 4rem;
		padding: 0.35rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		font-size: var(--font-size-section-label);
		color: var(--color-text);
		text-decoration: none;
		position: relative;
	}
	.day.empty {
		background: transparent;
		opacity: 0.55;
	}
	.day.today {
		border-color: var(--color-primary);
		box-shadow: 0 0 0 1px var(--color-primary);
	}
	.day.has-workout:not(.today) {
		border-color: var(--wo-border, var(--color-border));
		border-style: var(--wo-border-style);
		border-inline-start: 3px solid var(--kind);
	}
	.day.has-workout {
		background: var(--wo-bg, var(--color-bg));
		border-inline-start: 3px solid var(--kind);
		cursor: pointer;
		transition: transform var(--transition-fast), box-shadow var(--transition-fast);
	}
	.day.has-workout:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-sm);
	}
	.dow {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.kind {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-text);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		line-height: 1.1;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.dist {
		font-size: var(--font-size-section-label);
		color: var(--color-text);
		font-weight: 600;
	}
	.check {
		position: absolute;
		bottom: 0.3rem;
		inset-inline-end: 0.3rem;
		font-family: 'Material Symbols Outlined';
		font-size: 0.95rem;
		color: var(--wo-glyph);
	}

	/* The narrow-viewport cell tightens its box, not its type — the same shrink
	   § 525 removed from `PlanCalendar`, which this strip carried verbatim. */
	@media (max-width: 40rem) {
		.day {
			min-height: 3.25rem;
			padding: 0.25rem;
		}
	}
	/* The same abbreviation PlanCalendar switches to below ~600 px. */
	@media (max-width: 37.5rem) {
		.kind-full {
			display: none;
		}
		/* A pseudo-element, so the cell's text content stays the full word. */
		.kind::after {
			content: attr(data-short);
			letter-spacing: 0;
		}
	}
</style>
