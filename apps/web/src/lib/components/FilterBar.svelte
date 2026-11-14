<script lang="ts" module>
	/// A quick chip: one value of the screen's most-used filter. Data, not
	/// markup, so a chip can only toggle a filter and never link anywhere
	/// (issue #1374: a chip that navigates looks like a filter and leaves).
	export interface FilterChip {
		key: string;
		label: string;
		pressed: boolean;
		onclick: () => void;
		testid?: string;
		/// A Material Symbols ligature. A chip with one, alone on the bar,
		/// is drawn as a toggle icon button in the top row instead of on a
		/// line of its own (issue #1374).
		icon?: string;
	}

	/// A filter that is on, shown as a removable chip on the same line so
	/// clearing it is one tap.
	export interface ActiveFilter {
		key: string;
		label: string;
		onRemove: () => void;
		testid?: string;
	}
</script>

<script lang="ts">
	import type { Snippet } from 'svelte';
	import Modal from './Modal.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { filtersButtonLabel, lineFades, lineMask, loneChipInTopRow, trailingOnLine } from './filter_bar.ts';

	// The control row of a list, the web twin of ui_kit's `FilterBar`
	// (conventions.md § Web lists — FilterBar and PageHeader): at most one
	// search field, at most one line of quick chips that scrolls sideways and
	// never wraps, a Filters button carrying the active count that opens the
	// sheet holding everything else, and the active filters as removable chips
	// on the chip line. Changes in the sheet apply at once, so the list behind
	// it is already right when Done closes it. The sheet is `Modal`, which traps
	// focus while open and hands it back to the Filters button on close.
	//
	// `idPrefix` names the parts for tests: `<prefix>-filters-toggle`,
	// `-filter-count`, `-active-filters`, `-filters-panel`, `-filters-done`.
	let {
		search,
		trailing,
		chips = [],
		chipsLabel,
		activeFilters = [],
		filters,
		filtersLabel,
		filtersTitle,
		activeFilterCount = 0,
		filtersOpen = $bindable(false),
		idPrefix,
	}: {
		/// Usually an `AppSearchField`.
		search?: Snippet;
		/// Actions at the end of the first row, after the search.
		trailing?: Snippet;
		chips?: FilterChip[];
		/// Names the chip line as a group for a screen reader.
		chipsLabel?: string;
		activeFilters?: ActiveFilter[];
		/// The sheet's controls. With none there is no Filters button.
		filters?: Snippet;
		filtersLabel?: string;
		filtersTitle?: string;
		activeFilterCount?: number;
		filtersOpen?: boolean;
		idPrefix?: string;
	} = $props();

	const tid = (part: string) => (idPrefix ? `${idPrefix}-${part}` : undefined);
	const label = $derived(filtersLabel ?? m('filterBar.filters'));
	const toggle = $derived(
		loneChipInTopRow(chips.length, !!chips[0]?.icon, !!search || !!trailing || !!filters)
			? chips[0]
			: undefined,
	);
	const lineChips = $derived(toggle ? [] : chips);
	const hasLine = $derived(lineChips.length > 0 || activeFilters.length > 0);
	// With nothing to share a top row, the actions stand at the line's end
	// rather than alone on a row above it (issue #1374).
	const actionsOnLine = $derived(
		trailingOnLine({
			hasSearch: !!search,
			hasFilters: !!filters,
			hasToggle: !!toggle,
			hasTrailing: !!trailing,
			hasLine,
		}),
	);
	const hasTop = $derived(!!search || !!filters || !!toggle || (!!trailing && !actionsOnLine));

	// The line fades at an edge with more beyond it, so a cut chip reads as
	// "more", never a hard cut (ui_kit's EdgeFadeScroll).
	let lineEl = $state<HTMLElement | undefined>();
	let mask = $state('none');
	$effect(() => {
		const el = lineEl;
		void lineChips.length;
		void activeFilters.length;
		if (!el) return;
		const update = () => {
			mask = lineMask(
				lineFades(el.scrollLeft, el.clientWidth, el.scrollWidth),
				getComputedStyle(el).direction === 'rtl',
			);
		};
		update();
		el.addEventListener('scroll', update, { passive: true });
		const ro = typeof ResizeObserver === 'undefined' ? undefined : new ResizeObserver(update);
		ro?.observe(el);
		for (const child of el.children) ro?.observe(child);
		return () => {
			el.removeEventListener('scroll', update);
			ro?.disconnect();
		};
	});
</script>

{#if hasTop || hasLine}
	<div class="filter-bar">
		{#if hasTop}
			<div class="fb-top">
				{#if search}{@render search()}{/if}
				{#if toggle}
					<button
						type="button"
						class="fb-toggle"
						class:active={toggle.pressed}
						aria-pressed={toggle.pressed}
						aria-label={toggle.label}
						title={toggle.label}
						onclick={toggle.onclick}
						data-testid={toggle.testid ?? tid('toggle')}
					>
						<span class="material-symbols" class:filled={toggle.pressed} aria-hidden="true">{toggle.icon}</span>
					</button>
				{/if}
				{#if filters}
					<button
						type="button"
						class="fb-filters"
						class:active={activeFilterCount > 0}
						aria-haspopup="dialog"
						aria-expanded={filtersOpen}
						aria-label={filtersButtonLabel(activeFilterCount, label, (count) =>
							m('filterBar.filtersCount', { count }),
						)}
						onclick={() => (filtersOpen = true)}
						data-testid={tid('filters-toggle')}
					>
						<span class="material-symbols" aria-hidden="true">tune</span>
						<span class="fb-filters-label">{label}</span>
						{#if activeFilterCount > 0}
							<span class="fb-count" aria-hidden="true" data-testid={tid('filter-count')}>{activeFilterCount}</span>
						{/if}
					</button>
				{/if}
				{#if trailing && !actionsOnLine}{@render trailing()}{/if}
			</div>
		{/if}
		{#if hasLine}
			<div class="fb-line-row">
				<div
					class="fb-line"
					bind:this={lineEl}
					style:mask-image={mask}
					style:-webkit-mask-image={mask}
					data-testid={tid('chip-line')}
				>
					{#if lineChips.length > 0}
						<div class="fb-chips" role="group" aria-label={chipsLabel} data-testid={tid('chips')}>
							{#each lineChips as chip (chip.key)}
								<button
									type="button"
									class="fb-chip"
									class:active={chip.pressed}
									aria-pressed={chip.pressed}
									onclick={chip.onclick}
									data-testid={chip.testid}
								>
									{chip.label}
								</button>
							{/each}
						</div>
					{/if}
					{#if activeFilters.length > 0}
						<div class="fb-active" data-testid={tid('active-filters')}>
							{#each activeFilters as f (f.key)}
								<button
									type="button"
									class="fb-chip active removable"
									onclick={f.onRemove}
									aria-label={m('filterBar.removeFilter', { filter: f.label })}
									data-testid={f.testid}
								>
									<span>{f.label}</span>
									<span class="material-symbols" aria-hidden="true">close</span>
								</button>
							{/each}
						</div>
					{/if}
				</div>
				{#if actionsOnLine && trailing}{@render trailing()}{/if}
			</div>
		{/if}
	</div>
{/if}

{#if filters}
	<Modal
		open={filtersOpen}
		title={filtersTitle ?? label}
		narrow
		onclose={() => (filtersOpen = false)}
		data-testid={tid('filters-panel')}
	>
		<div class="fb-sheet">
			{@render filters()}
		</div>
		<div class="fb-sheet-actions">
			<button
				type="button"
				class="btn btn-primary"
				onclick={() => (filtersOpen = false)}
				data-testid={tid('filters-done')}
			>
				{m('filterBar.done')}
			</button>
		</div>
	</Modal>
{/if}

<style>
	.filter-bar {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		min-width: 0;
	}
	.fb-top {
		display: flex;
		flex-wrap: wrap;
		align-items: stretch;
		gap: var(--space-sm);
	}
	.fb-line-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		min-width: 0;
	}
	/* One line, never two: extras scroll sideways inside the bar rather than
	   wrapping or widening the page (WCAG 1.4.10). */
	.fb-line {
		flex: 1 1 auto;
		min-width: 0;
		display: flex;
		flex-wrap: nowrap;
		align-items: center;
		gap: 0.4rem;
		overflow-x: auto;
		scrollbar-width: thin;
		padding-bottom: 2px;
	}
	.fb-chips,
	.fb-active {
		display: flex;
		flex-wrap: nowrap;
		gap: 0.4rem;
		flex: 0 0 auto;
	}
	.fb-filters {
		appearance: none;
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		min-height: var(--tap-target-min);
		min-width: var(--tap-target-min);
		padding: 0 0.85rem;
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font: inherit;
		font-size: 0.9rem;
		font-weight: 600;
		cursor: pointer;
		white-space: nowrap;
	}
	/* State is the filled glyph and aria-pressed, not the colour alone. */
	.fb-toggle {
		appearance: none;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-height: var(--tap-target-min);
		min-width: var(--tap-target-min);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.fb-toggle.active {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.fb-toggle .material-symbols.filled {
		font-variation-settings: 'FILL' 1;
	}
	.fb-toggle:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.fb-filters.active {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.fb-filters .material-symbols {
		font-size: 1.25rem;
	}
	.fb-filters:focus-visible,
	.fb-chip:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.fb-count {
		min-width: 1.4rem;
		padding: 0 0.35rem;
		border-radius: 999px;
		background: var(--color-primary);
		color: var(--color-on-primary);
		font-size: 0.8rem;
		line-height: 1.4rem;
		text-align: center;
	}
	.fb-chip {
		appearance: none;
		flex: 0 0 auto;
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		min-height: var(--tap-target-min);
		padding: 0.35rem 0.85rem;
		border: 1.5px solid var(--color-border);
		border-radius: 999px;
		background: var(--color-surface);
		color: var(--color-text);
		font: inherit;
		font-size: 0.85rem;
		white-space: nowrap;
		cursor: pointer;
	}
	.fb-chip.active {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-weight: 600;
	}
	.removable .material-symbols {
		font-size: 1rem;
	}
	.fb-sheet {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.fb-sheet-actions {
		display: flex;
		justify-content: flex-end;
		margin-top: var(--space-lg);
	}
</style>
