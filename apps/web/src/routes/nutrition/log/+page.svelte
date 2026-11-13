<script lang="ts">
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { goto } from '$app/navigation';
	import LogFoodPanel from '#lib/components/LogFoodPanel.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
</script>

<svelte:head><title>{m('nutrition.logHeading')} — Threkir</title></svelte:head>

<div class="page">
	<PageHeader back={{ href: '/nutrition', label: m('nutrition.heading') }} title={m('nutrition.logHeading')} />

	<LogFoodPanel oncreated={() => goto('/nutrition')} photoOpen />
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		max-width: 44rem;
	}
</style>
