<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';

	// Routes' views, under the run-surface strip: Mine · Explore, and in Explore
	// Routes · Segments (issue #1374, owner decision 1). The segment catalogue
	// was a run-surface tab of its own; it is Explore's Segments view now, as on
	// mobile, where the same two rows are the Routes tab's view row and
	// Explore's chips. Explore leads with the map: the routes heatmap is its
	// first entry. Each view is its own URL (`/routes`, `/routes?tab=explore`,
	// `/segments`), so these are links, like RunSurfaceTabs, not an ARIA
	// tablist.
	let { view }: { view: 'mine' | 'routes' | 'segments' } = $props();

	const explore = $derived(view !== 'mine');
</script>

<nav class="view-tabs" aria-label={m('routesPage.sectionLabel')} data-testid="routes-view-nav">
	<a
		class="view-tab"
		class:active={!explore}
		href="/routes"
		aria-current={view === 'mine' ? 'page' : undefined}
	>
		{m('routesPage.tabMine')}
	</a>
	<a
		class="view-tab"
		class:active={explore}
		href="/routes?tab=explore"
		aria-current={explore ? 'true' : undefined}
	>
		{m('routesPage.tabExplore')}
	</a>
</nav>

{#if explore}
	<div class="explore-row">
		<nav class="seg-group" aria-label={m('routesPage.tabExplore')} data-testid="routes-explore-kind">
			<a
				class="seg-btn"
				class:active={view === 'routes'}
				href="/routes?tab=explore"
				aria-current={view === 'routes' ? 'page' : undefined}
			>
				{m('runSurface.tabRoutes')}
			</a>
			<a
				class="seg-btn"
				class:active={view === 'segments'}
				href="/segments"
				aria-current={view === 'segments' ? 'page' : undefined}
				data-testid="routes-explore-segments"
			>
				{m('runSurface.tabSegments')}
			</a>
		</nav>
		{#if view === 'routes'}
			<a class="btn btn-outline map-link" href="/routes/heatmap" data-testid="routes-explore-map">
				<span class="material-symbols" aria-hidden="true">local_fire_department</span>
				{m('routesPage.tabHeatmap')}
			</a>
		{/if}
	</div>
{/if}

<style>
	.view-tabs {
		display: flex;
		gap: 0.5rem;
		border-bottom: 1px solid var(--color-border);
		/* One underlined baseline, so the row scrolls rather than wraps. */
		max-width: 100%;
		overflow-x: auto;
		margin-bottom: var(--space-md);
	}

	.view-tab {
		flex: 0 0 auto;
		padding: 0.6rem 0.2rem;
		margin-inline-end: 1rem;
		font-size: 0.95rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		text-decoration: none;
	}

	.view-tab:hover {
		color: var(--color-text);
	}

	.view-tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}

	.explore-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin-bottom: var(--space-lg);
	}

	.seg-group {
		display: inline-flex;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		padding: var(--space-2xs);
		gap: var(--space-2xs);
		max-width: 100%;
		overflow-x: auto;
	}

	.seg-btn {
		flex: 0 0 auto;
		display: inline-flex;
		align-items: center;
		min-height: var(--tap-target-min);
		padding: var(--space-xs) var(--space-md);
		border-radius: var(--radius-sm);
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-decoration: none;
		transition: background var(--transition-fast), color var(--transition-fast),
			box-shadow var(--transition-fast);
	}

	.seg-btn:hover {
		color: var(--color-text);
	}

	.seg-btn.active {
		background: var(--color-surface);
		color: var(--color-primary);
		box-shadow: var(--shadow-sm);
	}

	.seg-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}

	.map-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		min-height: var(--tap-target-min);
	}

	.map-link .material-symbols {
		font-size: 1.1rem;
	}
</style>
