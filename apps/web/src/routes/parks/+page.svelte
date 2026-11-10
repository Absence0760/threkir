<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import RunSurfaceTabs from '#lib/components/RunSurfaceTabs.svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { fetchParks, type Park } from '#lib/core/data.ts';
	import { groupParksByRegion, regionName, regionSlug } from '#lib/parks/park_courses.ts';
	import { AGENCY_LABEL, labelKey } from '#lib/parks/park_labels.ts';

	let parks = $state<Park[]>([]);
	let loading = $state(true);
	let loadFailed = $state(false);

	const groups = $derived(groupParksByRegion(parks));

	async function load() {
		loading = true;
		loadFailed = false;
		try {
			parks = await fetchParks();
		} catch (e) {
			console.error('fetchParks failed', e);
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	onMount(async () => {
		await auth.ready();
		await load();
	});
</script>

<svelte:head><title>{m('parks.title')}</title></svelte:head>

<div class="page">
	<RunSurfaceTabs active="parks" />
	<header class="page-header">
		<h1>{m('parks.title')}</h1>
		<p class="subtitle">{m('parks.intro')}</p>
	</header>

	{#if loading}
		<p class="state-msg">{m('parks.loading')}</p>
	{:else if loadFailed}
		<div class="error-banner" role="alert" data-testid="parks-load-error">
			<span class="material-symbols" aria-hidden="true">error</span>
			<strong>{m('parks.loadFailed')}</strong>
			<button type="button" class="btn btn-outline btn-sm" onclick={load}>{m('parks.retry')}</button>
		</div>
	{:else if parks.length === 0}
		<p class="state-msg" data-testid="parks-empty">{m('parks.empty')}</p>
	{:else}
		{#each groups as group (group.regionCode)}
			<section class="region" data-testid="parks-region">
				<h2>{regionName(group.regionCode)}</h2>
				<ul class="park-list">
					{#each group.parks as park (park.id)}
						{@const agencyKey = labelKey(AGENCY_LABEL, park.agency)}
						<li>
							<a href="/parks/{regionSlug(park.region_code)}/{park.slug}" class="park-card">
								<span class="material-symbols" aria-hidden="true">park</span>
								<span class="park-text">
									<span class="park-name">{park.name}</span>
									{#if agencyKey}<span class="park-agency">{m(agencyKey)}</span>{/if}
								</span>
							</a>
						</li>
					{/each}
				</ul>
			</section>
		{/each}
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.page-header h1 {
		margin: 0 0 0.25rem;
	}
	.subtitle {
		margin: 0 0 var(--space-lg);
		max-width: 48rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.state-msg {
		color: var(--color-text-tertiary);
	}
	.error-banner {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		max-width: 48rem;
	}
	.region h2 {
		margin: var(--space-lg) 0 var(--space-sm);
		font-size: 0.85rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-secondary);
	}
	.park-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(16rem, 100%), 1fr));
		gap: var(--space-sm);
	}
	.park-card {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		text-decoration: none;
	}
	.park-card:hover {
		border-color: var(--color-primary);
	}
	.park-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.park-name {
		font-weight: 600;
	}
	.park-agency {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}
</style>
