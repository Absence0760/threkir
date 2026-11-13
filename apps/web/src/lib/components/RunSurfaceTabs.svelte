<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';

	// Run-surface sub-tab strip: Runs · Plans · Races & courses · Routes, in the
	// mobile strip's order (decisions § 2436). These are distinct surfaces at
	// distinct URLs, so the strip is a set of links (not an ARIA tablist — tabs
	// imply same-page panels). Routes, Plans, and the race calendar were relocated
	// out of their own sidebar slots to live under the run surface (decisions.md
	// § 677). The segment catalogue had a tab here until issue #1374 (owner
	// decision 1) made it Routes → Explore → Segments, so `/segments` marks
	// Routes and carries RoutesViewNav. Park courses have no tab: they are the
	// "Run any time" half of Races & courses, and `/parks` is reached from there
	// and from Segments.
	let { active }: { active: 'runs' | 'routes' | 'plans' | 'races' } = $props();
</script>

<nav class="surface-tabs" aria-label={m('runSurface.label')}>
	<a class="surface-tab" class:active={active === 'runs'} href="/runs" aria-current={active === 'runs' ? 'page' : undefined}>
		{m('runSurface.tabRuns')}
	</a>
	<a class="surface-tab" class:active={active === 'plans'} href="/plans" aria-current={active === 'plans' ? 'page' : undefined}>
		{m('runSurface.tabPlans')}
	</a>
	<a class="surface-tab" class:active={active === 'races'} href="/races" aria-current={active === 'races' ? 'page' : undefined}>
		{m('runSurface.tabRacesCourses')}
	</a>
	<a class="surface-tab" class:active={active === 'routes'} href="/routes" aria-current={active === 'routes' ? 'page' : undefined}>
		{m('runSurface.tabRoutes')}
	</a>
</nav>

<style>
	.surface-tabs {
		display: flex;
		gap: 0.5rem;
		border-bottom: 1px solid var(--color-border);
		margin-bottom: var(--space-lg);
		/* Tabs on one underlined baseline can't wrap without
		   breaking that baseline, so the strip scrolls itself rather
		   than widening the document (WCAG 1.4.10). */
		max-width: 100%;
		overflow-x: auto;
	}

	.surface-tab {
		flex: 0 0 auto;
		padding: 0.6rem 0.2rem;
		margin-inline-end: 1rem;
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		text-decoration: none;
		font-weight: 500;
	}

	.surface-tab:hover {
		color: var(--color-text);
	}

	.surface-tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}
</style>
