<script lang="ts">
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import { onMount } from 'svelte';
	import ListCard from '#lib/components/ListCard.svelte';
	import OfficialBadge from '#lib/components/OfficialBadge.svelte';
	import { goto } from '$app/navigation';
	import {
		fetchPublicPlanLibrary,
		type PublicPlanLibraryEntry,
	} from '#lib/core/data.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { formatDistance } from '#lib/format/units.svelte.ts';
	import { goalEventLabel, planLengthLabel } from '#lib/training/goal_event_label.ts';

	let plans = $state<PublicPlanLibraryEntry[]>([]);
	let loading = $state(true);
	let loadError = $state<Error | null>(null);
	let query = $state('');

	function weeksOf(p: PublicPlanLibraryEntry): number {
		const start = new Date(p.start_date).getTime();
		const end = new Date(p.end_date).getTime();
		const days = Math.round((end - start) / 86_400_000) + 1;
		return Math.max(1, Math.ceil(days / 7));
	}

	let searchTimer: ReturnType<typeof setTimeout> | undefined;
	function onSearchInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(load, 250);
	}

	/// Bumped per request, so a slow earlier search can never overwrite the
	/// answer to a newer one.
	let requestSeq = 0;
	/// True only until the first answer lands. A search after that keeps the
	/// current results on screen (marked busy) instead of blanking them.
	let loaded = $state(false);

	async function load() {
		const seq = ++requestSeq;
		loading = true;
		loadError = null;
		const res = await fetchPublicPlanLibrary(query);
		if (seq !== requestSeq) return;
		plans = res.plans;
		loadError = res.error;
		loading = false;
		loaded = true;
	}

	onMount(load);
</script>

<svelte:head>
	<title>{m('planLibrary.headTitle')}</title>
</svelte:head>

<div class="library">
	<header class="library-head">
		<a class="back" href="/plans">{m('planLibrary.backToLibrary')}</a>
		<h1>{m('planLibrary.heading')}</h1>
		<p class="sub">{m('planLibrary.subheading')}</p>
	</header>

	<div class="search">
		<AppSearchField
			bind:value={query}
			oninput={onSearchInput}
			label={m('planLibrary.searchAria')}
			placeholder={m('planLibrary.searchPlaceholder')}
		/>
	</div>

	{#if loading && !loaded}
		<p class="state">{m('planLibrary.loading')}</p>
	{:else if loadError}
		<div class="state error">
			<p>{m('planLibrary.loadError')}</p>
			<button class="btn btn-outline" type="button" onclick={load}>
				{m('planLibrary.retry')}
			</button>
		</div>
	{:else if plans.length === 0}
		<p class="state">
			{query.trim() ? m('planLibrary.emptySearch', { query }) : m('planLibrary.empty')}
		</p>
	{:else}
		<ul class="plan-grid" aria-busy={loading}>
			{#each plans as p (p.id)}
				<li>
					<ListCard class="plan-card" href="/plans/library/{p.id}" title={p.name} subtitle={m('planLibrary.byAuthor', { author: p.author_handle ?? m('planLibrary.anonymousAuthor') })}>
						{#snippet badge()}{#if p.is_official}<OfficialBadge />{/if}{/snippet}
						{#snippet meta()}
							<span class="plan-meta">
							<span class="chip">{goalEventLabel(m, formatDistance, p.goal_event, p.goal_distance_m)}</span>
							<span class="chip">{planLengthLabel(m, weeksOf(p), p.days_per_week)}</span>
							</span>
						{/snippet}
						{#snippet trailing()}<span class="plan-cta">{m('planLibrary.preview')}</span>{/snippet}
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
	.library-head {
		margin-bottom: 1rem;
	}
	.back {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		text-decoration: none;
	}
	.library-head h1 {
		margin: 0.25rem 0 0.25rem;
		font-size: 1.4rem;
	}
	.sub {
		margin: 0;
		color: var(--color-text-secondary);
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
	.plan-grid {
		list-style: none;
		padding: 0;
		margin: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(240px, 100%), 1fr));
		gap: 0.75rem;
	}
	.plan-meta {
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
	.plan-cta {
		margin-top: 0.4rem;
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-primary);
	}
	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
</style>
