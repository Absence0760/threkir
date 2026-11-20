<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import PageHeader from './PageHeader.svelte';

	// The run surface's header: one title row, then the sub-tab strip
	// (Runs · Plans · Races & courses · Routes, in the mobile strip's order,
	// decisions § 2436). Every sidebar root opens on a visible PageHeader with
	// its one primary action at the end of the title row, the web analogue of
	// the mobile root's FAB; a tab page passes that action as `actions` (and a
	// HelpLink as `help`) and renders no title of its own, so the title and the
	// strip sit at the same height on every tab. They share one block because
	// the host pages space their children with different flex gaps.
	//
	// These are distinct surfaces at distinct URLs, so the strip is a set of
	// links (not an ARIA tablist — tabs imply same-page panels). Routes, Plans,
	// and the race calendar were relocated out of their own sidebar slots to
	// live under the run surface (decisions.md § 677). `/segments` marks Routes
	// and carries RoutesViewNav (issue #1374, owner decision 1). Park courses
	// have no tab: they are the "Run any time" half of Races & courses.
	let {
		active,
		actions,
		help,
	}: { active: 'runs' | 'routes' | 'plans' | 'races'; actions?: Snippet; help?: Snippet } = $props();
</script>

<div class="run-surface-head" data-testid="run-surface-head">
	<PageHeader title={m('nav.runs')} {actions} {help} flush testid="run-surface-header" />
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
</div>

<style>
	.run-surface-head {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		margin-bottom: var(--space-lg);
		min-width: 0;
	}

	/* The title row is one height whether a tab has an action, a help link,
	   both or neither, so the strip under it never moves between tabs. */
	.run-surface-head :global(.page-head) {
		align-items: center;
		min-height: 2.5rem;
	}
	.run-surface-head :global(.page-head-actions > *) {
		min-height: 2.5rem;
	}

	.surface-tabs {
		display: flex;
		gap: 0.5rem;
		border-bottom: 1px solid var(--color-border);
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
