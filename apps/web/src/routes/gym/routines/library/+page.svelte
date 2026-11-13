<script lang="ts">
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { onMount } from 'svelte';
	import ListCard from '#lib/components/ListCard.svelte';
	import OfficialBadge from '#lib/components/OfficialBadge.svelte';
	import { fetchPublicGymRoutineLibrary, type PublicGymRoutineEntry } from '#lib/core/data.ts';
	import { m as t } from '#lib/i18n/store.svelte.ts';

	let routines = $state<PublicGymRoutineEntry[]>([]);
	let loading = $state(true);
	let loadError = $state<Error | null>(null);
	let query = $state('');

	let searchTimer: ReturnType<typeof setTimeout> | undefined;
	function onSearchInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(load, 250);
	}

	async function load() {
		loading = true;
		loadError = null;
		const res = await fetchPublicGymRoutineLibrary(query);
		routines = res.routines;
		loadError = res.error;
		loading = false;
	}

	onMount(load);
</script>

<svelte:head>
	<title>{t('gymLibrary.headTitle')}</title>
</svelte:head>

<div class="library">
	<PageHeader
		back={{ href: '/gym/routines', label: t('gymLibrary.backToRoutines') }}
		title={t('gymLibrary.heading')}
		subtitle={t('gymLibrary.subheading')}
	/>

	<div class="search">
		<AppSearchField
			bind:value={query}
			oninput={onSearchInput}
			label={t('gymLibrary.searchAria')}
			placeholder={t('gymLibrary.searchPlaceholder')}
		/>
	</div>

	{#if loading}
		<p class="state" role="status">{t('gymLibrary.loading')}</p>
	{:else if loadError}
		<div class="state error" role="alert">
			<p>{t('gymLibrary.loadError')}</p>
			<button class="btn btn-outline" type="button" onclick={load}>{t('gymLibrary.retry')}</button>
		</div>
	{:else if routines.length === 0}
		<p class="state" data-testid="gym-library-empty">
			{query.trim() ? t('gymLibrary.emptySearch', { query }) : t('gymLibrary.empty')}
		</p>
	{:else}
		<ul class="routine-grid" data-testid="gym-library-list">
			{#each routines as r (r.id)}
				<li>
					<ListCard class="routine-card" href="/gym/routines/library/{r.id}" title={r.title} subtitle={t('gymLibrary.byAuthor', { author: r.author_handle ?? t('gymLibrary.anonymousAuthor') })}>
						{#snippet badge()}{#if r.is_official}<OfficialBadge />{/if}{/snippet}
						{#snippet meta()}
							<span class="routine-meta">
							<span class="chip">{t('gymLibrary.exercisesLabel', { count: r.exercise_count })}</span>
							</span>
						{/snippet}
						{#snippet trailing()}<span class="routine-cta">{t('gymLibrary.preview')}</span>{/snippet}
					</ListCard>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.library {
		max-width: 880px;
		margin: 0 auto;
		padding: 1rem;
	}
	.search {
		display: flex;
		margin-bottom: 1rem;
	}
	.state {
		text-align: center;
		color: var(--color-text-secondary);
		padding: 2rem 0;
	}
	.state.error {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
		align-items: center;
	}
	.routine-grid {
		list-style: none;
		padding: 0;
		margin: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(240px, 100%), 1fr));
		gap: 0.75rem;
	}
	.routine-meta {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		margin-top: 0.2rem;
	}
	.chip {
		font-size: 0.75rem;
		padding: 0.15rem 0.5rem;
		border-radius: 1rem;
		background: var(--chip-bg);
		color: var(--chip-fg);
	}
	.routine-cta {
		margin-top: 0.4rem;
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-primary);
	}
</style>
