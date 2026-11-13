<script lang="ts">
	import PageHeader from '#lib/components/PageHeader.svelte';
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
	<PageHeader
		kicker={m('plansNew.kicker')}
		title={m('seasonPlanner.heading')}
		subtitle={m('seasonPlanner.tagline')}
	/>
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
</style>
