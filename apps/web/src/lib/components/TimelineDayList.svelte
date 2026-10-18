<script lang="ts" module>
	export interface TimelineItem {
		id: string;
		/// Picks the glyph's section accent: run, lift or meal.
		kind: 'run' | 'lift' | 'meal';
		glyph: string;
		/// Null renders the row read-only (meals have no detail route).
		href: string | null;
		primary: string;
		secondary: string;
	}
</script>

<script lang="ts">
	import { formatDate } from '#lib/format/time.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { DayGroup } from '#lib/timeline/day_groups.ts';

	// The compact day-grouped rows shared by the /history timeline and the
	// /runs list view (decisions § 2114). With `selecting`, every row becomes a
	// toggle for the caller's bulk selection instead of a link, the same swap
	// the /runs grid cards make.
	let {
		groups,
		headings = true,
		placeholder = false,
		selecting = false,
		selected = new Set<string>(),
		ontoggle,
	}: {
		groups: DayGroup<TimelineItem>[];
		/// False renders one undivided list: the caller's order is not by time.
		headings?: boolean;
		/// The loading shape, so the page commits to its height on first paint.
		placeholder?: boolean;
		selecting?: boolean;
		selected?: ReadonlySet<string>;
		ontoggle?: (id: string) => void;
	} = $props();

	function dayLabel(g: DayGroup<TimelineItem>): string {
		if (g.relative === 'today') return m('history.today');
		if (g.relative === 'yesterday') return m('history.yesterday');
		return formatDate(g.startedAt);
	}
</script>

{#if placeholder}
	<div class="timeline timeline-skel" aria-hidden="true">
		{#each Array(2) as _, g (g)}
			<div class="timeline-group">
				<span class="skel skel-line skel-day"></span>
				<ul class="timeline-list card-elevated">
					{#each Array(4) as _, i (i)}
						<li class="timeline-item skel-item">
							<span class="skel skel-glyph"></span>
							<span class="skel-rows">
								<span class="skel skel-line skel-w-50"></span>
								<span class="skel skel-line skel-w-30"></span>
							</span>
						</li>
					{/each}
				</ul>
			</div>
		{/each}
	</div>
{:else}
	<div class="timeline" class:single={!headings}>
		{#each groups as g (g.key)}
			<section class="timeline-group" data-testid="timeline-day-group">
				{#if headings}
					<h2 class="timeline-day">{dayLabel(g)}</h2>
				{/if}
				<ul class="timeline-list card-elevated">
					{#each g.rows as a (a.id)}
						{@const isSelected = selected.has(a.id)}
						<li class="timeline-item">
							{#if selecting}
								<button
									type="button"
									class="timeline-row timeline-row-link"
									class:selected={isSelected}
									aria-pressed={isSelected}
									data-kind={a.kind}
									onclick={() => ontoggle?.(a.id)}
								>
									<span class="select-box" class:checked={isSelected} aria-hidden="true">
										{#if isSelected}
											<span class="material-symbols">check</span>
										{/if}
									</span>
									<span class="timeline-main">
										<span class="timeline-primary">{a.primary}</span>
										{#if a.secondary}
											<span class="timeline-secondary">{a.secondary}</span>
										{/if}
									</span>
								</button>
							{:else}
								<svelte:element
									this={a.href ? 'a' : 'div'}
									href={a.href ?? undefined}
									class="timeline-row"
									class:timeline-row-link={a.href != null}
									data-kind={a.kind}
								>
									<span class="timeline-glyph" data-kind={a.kind} aria-hidden="true">
										<span class="material-symbols">{a.glyph}</span>
									</span>
									<span class="timeline-main">
										<span class="timeline-primary">{a.primary}</span>
										{#if a.secondary}
											<span class="timeline-secondary">{a.secondary}</span>
										{/if}
									</span>
									{#if a.href}
										<span class="material-symbols timeline-arrow" aria-hidden="true">chevron_right</span>
									{/if}
								</svelte:element>
							{/if}
						</li>
					{/each}
				</ul>
			</section>
		{/each}
	</div>
{/if}

<style>
	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}

	/* Day groups flow into a responsive multi-column grid on wide canvases
	   so the timeline fills the page instead of stranding the right ~40% as
	   dead space, while each day card keeps a readable row width. Collapses to
	   one column below ~64rem (and on mobile). Most-recent day is top-left;
	   cells read left-to-right, top-to-bottom. */
	.timeline {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(30rem, 100%), 1fr));
		gap: var(--space-xl);
		align-items: start;
	}
	/* One undivided list has no day cards to tile; keep it one readable column. */
	.timeline.single {
		grid-template-columns: minmax(0, 48rem);
	}
	.timeline-group {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.timeline-day {
		font-size: 0.75rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		margin: 0;
		padding-inline-start: var(--space-2xs);
	}
	/* One elevated panel per day; rows are separated by hairline
	   dividers rather than each being its own bordered box. card-elevated
	   gives the resting shadow + border; its padding is zeroed so rows fill
	   edge to edge. */
	.timeline-list {
		list-style: none;
		margin: 0;
		padding: 0;
		overflow: hidden;
	}
	.timeline-list.card-elevated {
		padding: 0;
	}
	.timeline-item + .timeline-item {
		border-top: 1px solid var(--color-border);
	}
	.timeline-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		width: 100%;
		padding: var(--space-sm) var(--space-md);
		text-decoration: none;
		color: inherit;
		background: transparent;
		border: none;
		font: inherit;
		text-align: start;
		transition: background var(--transition-fast);
	}
	button.timeline-row {
		cursor: pointer;
	}
	.timeline-row-link:hover { background: var(--color-bg-secondary); }
	.timeline-row-link:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: -2px;
		border-radius: var(--radius-sm);
	}
	.timeline-row.selected {
		background: color-mix(in srgb, var(--color-primary) 10%, transparent);
	}
	.timeline-glyph {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2.25rem;
		height: 2.25rem;
		border-radius: 50%;
		flex-shrink: 0;
		color: var(--color-text-secondary);
		background: var(--color-bg-tertiary);
	}
	/* Per-kind accent on the glyph chip — a secondary cue; the glyph
	   shape + the row text carry the type, never colour alone. Each kind
	   reads the shared --section-* pair, so a chip here is the same hue as
	   its sidebar entry; the fixed inks these replaced were 2.359 / 2.396:1
	   on the dark card (decisions § 529). */
	.timeline-glyph[data-kind='lift'] { color: var(--section-gym-ink); background: color-mix(in srgb, var(--section-gym) 18%, transparent); }
	.timeline-glyph[data-kind='meal'] { color: var(--section-nutrition-ink); background: color-mix(in srgb, var(--section-nutrition) 20%, transparent); }
	.timeline-glyph[data-kind='run'] { color: var(--color-primary); background: color-mix(in srgb, var(--color-primary) 12%, transparent); }
	.timeline-glyph .material-symbols { font-size: 1.25rem; }
	/* Same 2.25rem footprint as the glyph it replaces, so rows do not shift
	   sideways when selection mode toggles. */
	.select-box {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2.25rem;
		height: 2.25rem;
		flex-shrink: 0;
		border-radius: 50%;
		border: 2px solid var(--color-border);
		color: var(--color-surface);
	}
	.select-box.checked {
		background: var(--color-primary);
		border-color: var(--color-primary);
	}
	.select-box .material-symbols { font-size: 1.2rem; }
	.timeline-main {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
	}
	.timeline-primary {
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.timeline-secondary {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.timeline-arrow {
		color: var(--color-text-tertiary);
		font-size: 1.2rem;
		flex-shrink: 0;
	}

	/* Skeleton mirrors the timeline shape so the page renders to roughly its
	   true height immediately — no shift when the rows land. */
	.skel-item {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
	}
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-sm);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-line { height: 0.75rem; }
	.skel-day { width: 6rem; height: 0.7rem; }
	.skel-glyph {
		width: 2.25rem;
		height: 2.25rem;
		border-radius: 50%;
		flex-shrink: 0;
	}
	.skel-rows {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.skel-w-30 { width: 30%; }
	.skel-w-50 { width: 50%; }
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}
</style>
