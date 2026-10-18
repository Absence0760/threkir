<script lang="ts">
	import type { PlanWorkout } from '#lib/types.ts';
	import { parseISO, todayISO, formatISO } from '#lib/training/training.ts';
	import { workoutKindLabel, workoutKindShortLabel } from '#lib/training/workout_labels.ts';
	import { planWorkoutAriaLabel, planWorkoutStatusOf } from '#lib/training/plan_workout_view.ts';
	import { planWorkoutStatusLook } from '#lib/training/plan_workout_status_style.ts';
	import { formatDateShort } from '#lib/format/time.ts';
	import { workoutKindMarkVar } from '#lib/training/workout_kind_color.ts';
	import { fmtKm } from '#lib/format/units.svelte.ts';
	import { currentLocale, m } from '#lib/i18n/store.svelte.ts';
	import { monthName, weekdayAbbrevs, leadingBlanks, type WeekStart } from '#lib/format/calendar.ts';

	type Props = {
		startDate: string;
		endDate: string;
		workouts: PlanWorkout[];
		planId: string;
		/// First day of the week — the host threads the user's
		/// `week_start_day` preference. Defaults to Monday so the component
		/// stays standalone-friendly.
		weekStart?: WeekStart;
		/// The runner's local day (yyyy-mm-dd): marks today's cell, decides
		/// which workouts are missed, and picks the month the calendar opens
		/// on. Defaults to the browser's day so the component stays standalone.
		today?: string;
		/// Called when the user clicks a workout cell. Hosts pass an
		/// inline-editor opener (sets `editing = wo` on the plan page).
		/// When omitted, falls back to navigating to the workout
		/// detail route — keeps the component standalone-friendly.
		onSelect?: (workout: PlanWorkout) => void;
	};
	let {
		startDate,
		endDate,
		workouts,
		planId,
		weekStart = 'monday',
		today = todayISO(),
		onSelect
	}: Props = $props();

	let workoutByDate = $derived.by(() => {
		const m = new Map<string, PlanWorkout>();
		for (const w of workouts) m.set(w.scheduled_date, w);
		return m;
	});

	let months = $derived.by(() => {
		const out: { year: number; month: number }[] = [];
		const start = parseISO(startDate);
		const end = parseISO(endDate);
		let y = start.getFullYear();
		let m = start.getMonth();
		while (y < end.getFullYear() || (y === end.getFullYear() && m <= end.getMonth())) {
			out.push({ year: y, month: m });
			m += 1;
			if (m > 11) { m = 0; y += 1; }
		}
		return out;
	});

	/// The month holding today; before the plan the first month, after it the
	/// last, so a finished plan opens on its race rather than on week 1.
	function initialIdx(): number {
		if (months.length === 0) return 0;
		if (today < startDate) return 0;
		if (today > endDate) return months.length - 1;
		const t = parseISO(today);
		const idx = months.findIndex(
			({ year, month }) => year === t.getFullYear() && month === t.getMonth()
		);
		return idx >= 0 ? idx : 0;
	}

	let currentIdx = $state(initialIdx());

	let current = $derived(months[currentIdx]);

	type Cell = {
		iso: string;
		day: number;
		inMonth: boolean;
		inPlan: boolean;
	};

	function isoFor(year: number, month: number, day: number): string {
		return formatISO(new Date(year, month, day));
	}

	let grid = $derived.by<Cell[]>(() => {
		if (!current) return [];
		const { year, month } = current;
		const first = new Date(year, month, 1);
		const last = new Date(year, month + 1, 0);
		// Honour the user's week_start_day (defaults to Monday).
		const leadDow = leadingBlanks(first.getDay(), weekStart);
		const cells: Cell[] = [];

		const prevLast = new Date(year, month, 0).getDate();
		for (let i = leadDow; i > 0; i--) {
			const d = prevLast - i + 1;
			const prevMonth = month === 0 ? 11 : month - 1;
			const prevYear = month === 0 ? year - 1 : year;
			const iso = isoFor(prevYear, prevMonth, d);
			cells.push({ iso, day: d, inMonth: false, inPlan: iso >= startDate && iso <= endDate });
		}
		for (let d = 1; d <= last.getDate(); d++) {
			const iso = isoFor(year, month, d);
			cells.push({ iso, day: d, inMonth: true, inPlan: iso >= startDate && iso <= endDate });
		}
		// Pad to a 7-column-wide rectangle
		const remainder = cells.length % 7;
		if (remainder !== 0) {
			const trail = 7 - remainder;
			for (let d = 1; d <= trail; d++) {
				const nextMonth = month === 11 ? 0 : month + 1;
				const nextYear = month === 11 ? year + 1 : year;
				const iso = isoFor(nextYear, nextMonth, d);
				cells.push({ iso, day: d, inMonth: false, inPlan: iso >= startDate && iso <= endDate });
			}
		}
		return cells;
	});

	// Locale-aware month label + weekday row, reordered for the chosen
	// week start. Reading currentLocale() here re-renders on a locale flip.
	let dow = $derived(weekdayAbbrevs(weekStart, currentLocale()));

	function prev() {
		if (currentIdx > 0) currentIdx -= 1;
	}
	function next() {
		if (currentIdx < months.length - 1) currentIdx += 1;
	}
</script>

<div class="cal">
	<header class="cal-head">
		<button
			type="button"
			class="nav"
			onclick={prev}
			disabled={currentIdx === 0}
			aria-label={m('planCalendar.prevMonth')}
		>
			<span class="material-symbols" aria-hidden="true">chevron_left</span>
		</button>
		<h3>{monthName(current.month, currentLocale())} {current.year}</h3>
		<button
			type="button"
			class="nav"
			onclick={next}
			disabled={currentIdx === months.length - 1}
			aria-label={m('planCalendar.nextMonth')}
		>
			<span class="material-symbols" aria-hidden="true">chevron_right</span>
		</button>
	</header>

	<div class="dow-row">
		{#each dow as d}
			<span>{d}</span>
		{/each}
	</div>

	<div class="grid">
		{#each grid as c (c.iso)}
			{@const wo = workoutByDate.get(c.iso)}
			{#if wo && c.inPlan}
				{@const status = planWorkoutStatusOf(wo, today)}
				{@const look = planWorkoutStatusLook(status)}
				<svelte:element
					this={onSelect ? 'button' : 'a'}
					role={onSelect ? 'button' : 'link'}
					type={onSelect ? 'button' : undefined}
					href={onSelect ? undefined : `/plans/${planId}/workouts/${wo.id}`}
					onclick={onSelect ? () => onSelect(wo) : undefined}
					class="cell has-workout"
					class:out-month={!c.inMonth}
					class:today={c.iso === today}
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
							day: formatDateShort(c.iso),
							kind: workoutKindLabel(wo.kind),
							distance:
								wo.target_distance_m != null && wo.kind !== 'rest'
									? fmtKm(wo.target_distance_m, 1)
									: null
						},
						m
					)}
				>
					<span class="day-num" aria-hidden="true">{c.day}</span>
					<span
						class="kind-pill"
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
				<div
					class="cell"
					class:out-month={!c.inMonth}
					class:out-plan={!c.inPlan}
					class:today={c.iso === today}
				>
					<span class="day-num">{c.day}</span>
				</div>
			{/if}
		{/each}
	</div>
</div>

<style>
	.cal {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
	}
	.cal-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-md);
	}
	.cal-head h3 {
		font-size: 1rem;
		font-weight: 600;
	}
	.nav {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2rem;
		height: 2rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}
	.nav:hover:not(:disabled) {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.nav:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
	.nav .material-symbols {
		font-size: 1.2rem;
	}
	.dow-row {
		display: grid;
		grid-template-columns: repeat(7, minmax(0, 1fr));
		gap: 0.35rem;
		margin-bottom: 0.4rem;
		text-align: center;
		font-size: var(--font-size-section-label);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-tertiary);
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(7, minmax(0, 1fr));
		gap: 0.35rem;
	}
	.cell {
		min-height: 4.5rem;
		padding: 0.35rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		font-size: var(--font-size-section-label);
		color: var(--color-text);
		text-decoration: none;
		position: relative;
	}
	/* The dim is a whole-cell opacity: at 0.35 it drops the kind label's
	   --color-text from 14.283:1 to 2.051:1 and --color-text-secondary from
	   5.722:1 to 1.627:1. A cell carrying a planned session — a leading or
	   trailing grid row still inside the plan — is content, so it keeps full
	   strength; only empty chrome cells are dimmed. */
	.cell.out-month:not(.has-workout) {
		opacity: 0.35;
	}
	.cell.out-plan {
		background: transparent;
		border-color: transparent;
	}
	.cell.today {
		border-color: var(--color-primary);
		box-shadow: 0 0 0 1px var(--color-primary);
	}
	.cell.has-workout:not(.today) {
		border-color: var(--wo-border, var(--color-border));
		border-style: var(--wo-border-style);
		border-inline-start: 3px solid var(--kind);
	}
	.cell.has-workout {
		background: var(--wo-bg, var(--color-bg));
		border-inline-start: 3px solid var(--kind);
		cursor: pointer;
		transition: transform var(--transition-fast), box-shadow var(--transition-fast);
	}
	.cell.has-workout:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-sm);
	}
	.day-num {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		color: var(--color-text-secondary);
		align-self: flex-end;
	}
	.kind-pill {
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

	/* The narrow-viewport cell tightens its box, not its type: the kind pill
	   and the distance used to drop to 0.55rem / 0.6rem (8.8 / 9.6 px), under
	   mobile's 11 px labelSmall floor (§ 482), on the one plan surface every
	   phone user opens. A 7-column grid at that width leaves ~29 px of content
	   per cell, so at the floor the distance reflows to two lines and the row
	   grows — which is what SC 1.4.4 and 1.4.10 ask for, and `min-height`
	   already permits. The pill keeps its ellipsis. */
	@media (max-width: 40rem) {
		.cell {
			min-height: 3.5rem;
			padding: 0.2rem;
		}
	}
	/* Below ~600 px a cell holds about 29 px of text, so "INTERVALS" or
	   "WALK-RUN" was cut to an ellipsis and the 3 px edge, six marks for nine
	   kinds, was left to name the kind. The abbreviation fits; the full word
	   stays in the cell's accessible name. */
	@media (max-width: 37.5rem) {
		.kind-full {
			display: none;
		}
		/* A pseudo-element, so the cell's text content stays the full word. */
		.kind-pill::after {
			content: attr(data-short);
			letter-spacing: 0;
		}
	}
</style>
