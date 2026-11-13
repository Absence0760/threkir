<script lang="ts">
	import { onMount } from 'svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { afterNavigate } from '$app/navigation';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import PersonalHeatmap from '#lib/components/PersonalHeatmap.svelte';
	import SkeletonBlock from '#lib/components/SkeletonBlock.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';

	let ready = $state(false);
	onMount(async () => {
		await auth.ready();
		ready = true;
	});

	/// The only entry point to this page is the /runs toolbar, and the button
	/// pointed at /history — the cross-modal timeline, not the run list the
	/// runner came from. Going BACK rather than forward is what restores
	/// /runs's snapshot (filters + scroll); a soft-nav forward drops it. Stays
	/// a real link so a deep hit, a middle-click and the keyboard all work.
	/// Same shape as /clubs/[slug] → /clubs and /runs/[id] → /runs.
	let cameFromRuns = $state(false);
	afterNavigate(({ from }) => {
		if (from?.url.pathname === '/runs' && !cameFromRuns) {
			cameFromRuns = true;
		}
	});
	function handleBack(e: MouseEvent): void {
		if (cameFromRuns) {
			e.preventDefault();
			history.back();
		}
	}
</script>

<svelte:head>
	<title>{m('runsHeatmap.pageTitle')}</title>
</svelte:head>

<div class="page">
	<PageHeader flush title={m('runsHeatmap.heading')} subtitle={m('runsHeatmap.subtitle')}>
		{#snippet actions()}
			<a class="btn btn-outline" href="/runs" onclick={handleBack}
				>{m('runsHeatmap.backToRuns')}</a
			>
		{/snippet}
	</PageHeader>

	{#if !ready}
		<div class="map-host" data-testid="heatmap-skeleton">
			<SkeletonBlock height="100%" radius="var(--radius-md)" />
		</div>
		<p class="visually-hidden" role="status">{m('shell.loading')}</p>
	{:else if !auth.user}
		<p class="muted">{m('runsHeatmap.signInPrompt')}</p>
	{:else}
		<div class="map-host">
			<PersonalHeatmap />
		</div>
	{/if}
</div>

<style>
	.page {
		display: flex;
		flex-direction: column;
		padding: var(--page-padding-y) var(--page-padding-x);
		gap: var(--space-lg);
		height: 100vh;
		min-height: 32rem;
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.map-host {
		flex: 1 1 auto;
		min-height: 0;
	}
</style>
