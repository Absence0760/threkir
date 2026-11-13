<script lang="ts">
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { goto, afterNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import RunEditor from '#lib/components/RunEditor.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { SAVED_ROUTE_PARAM } from '#lib/routes/route_return.ts';

	let cameFromRuns = $state(false);
	afterNavigate(({ from }) => {
		if (cameFromRuns || !from) return;
		const p = from.url.pathname;
		if (p === '/runs' || p.startsWith('/runs?')) {
			cameFromRuns = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromRuns) {
			e.preventDefault();
			history.back();
		}
	}

	function handleCancel(): void {
		if (cameFromRuns) history.back();
		else goto('/runs');
	}
</script>

<svelte:head>
	<title>{m('runsNewPage.title')} — Threkir</title>
</svelte:head>

<div class="page">
	<a href="/runs" class="back-link" onclick={handleBack}>
		<span class="material-symbols">arrow_back</span>
		{m('runsNewPage.backToRuns')}
	</a>

	<PageHeader
		kicker={m('runsNewPage.kicker')}
		title={m('runsNewPage.title')}
		subtitle={m('runsNewPage.tagline')}
	/>

	<RunEditor
		oncreated={(run) => goto(`/runs/${run.id}`)}
		oncancel={handleCancel}
		initialRouteId={page.url.searchParams.get(SAVED_ROUTE_PARAM)}
	/>
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 44rem;
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
	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
