<script lang="ts">
	import SeasonPlanner from '#lib/components/SeasonPlanner.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
</script>

<svelte:head>
	<title>{m('seasonPlanner.pageTitle')}</title>
</svelte:head>

<div class="page">
	<a href="/plans/new" class="back-link">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('seasonPlanner.back')}
	</a>
	<p class="kicker">{m('plansNew.kicker')}</p>
	<header class="page-header">
		<h1>{m('seasonPlanner.heading')}</h1>
		<p class="tagline">{m('seasonPlanner.tagline')}</p>
	</header>
	<SeasonPlanner />
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		padding: var(--space-xs) 0;
		margin-bottom: var(--space-md);
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link .material-symbols {
		font-size: 1.1rem;
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm);
	}
	.page-header {
		margin-bottom: var(--space-xl);
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 800;
		line-height: 1.2;
		margin: 0 0 var(--space-xs);
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 44rem;
	}
</style>
