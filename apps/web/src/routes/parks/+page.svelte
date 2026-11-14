<script lang="ts">
	import SectionHeader from '#lib/components/SectionHeader.svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { m } from '#lib/i18n/store.svelte.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { fetchAllParkCourses, fetchParks, type Park, type ParkCourseWithPark } from '#lib/core/data.ts';
	import { groupParksByRegion, regionName } from '#lib/parks/park_courses.ts';
	import ParkCard from '#lib/components/parks/ParkCard.svelte';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import { parkSearchMatches, parkSearchTerms } from '#lib/parks/any_time_courses.ts';

	let parks = $state<Park[]>([]);
	let loading = $state(true);
	let loadFailed = $state(false);
	// The courses are an auxiliary read: when it fails the parks still list,
	// without their course count, distances and thumbnail.
	let courses = $state<ParkCourseWithPark[]>([]);

	// The search once typing pauses. Every park and course is already loaded,
	// so it is matched on the list. A park is found by its own name and place,
	// or by any of its courses' names, so a course name leads to its park.
	// Opens on `?q=`, which Races & courses' "See all" carries.
	let query = $state(page.url.searchParams.get('q') ?? '');
	let settledQuery = $state(page.url.searchParams.get('q') ?? '');
	let queryTimer: ReturnType<typeof setTimeout> | undefined;
	$effect(() => {
		const next = query;
		clearTimeout(queryTimer);
		queryTimer = setTimeout(() => (settledQuery = next), 250);
		return () => clearTimeout(queryTimer);
	});
	const terms = $derived(parkSearchTerms(settledQuery));

	function clearSearch() {
		clearTimeout(queryTimer);
		query = '';
		settledQuery = '';
	}

	const shownParks = $derived(
		terms.length === 0
			? parks
			: parks.filter(
					(p) =>
						parkSearchMatches(terms, { parkName: p.name, regionCode: p.region_code }) ||
						(byPark.get(p.id) ?? []).some((c) =>
							parkSearchMatches(terms, {
								courseName: c.segment.name,
								parkName: p.name,
								regionCode: p.region_code,
							}),
						),
				),
	);

	const groups = $derived(groupParksByRegion(shownParks));

	const byPark = $derived.by(() => {
		const out = new Map<string, ParkCourseWithPark[]>();
		for (const c of courses) {
			const list = out.get(c.park_id);
			if (list) list.push(c);
			else out.set(c.park_id, [c]);
		}
		return out;
	});

	async function loadCourses() {
		try {
			courses = await fetchAllParkCourses();
		} catch (e) {
			console.error('park courses read failed', e);
		}
	}

	async function load() {
		loading = true;
		loadFailed = false;
		const coursesRead = loadCourses();
		try {
			parks = await fetchParks();
		} catch (e) {
			console.error('fetchParks failed', e);
			loadFailed = true;
		} finally {
			loading = false;
		}
		await coursesRead;
	}

	onMount(async () => {
		await auth.ready();
		await load();
	});
</script>

<svelte:head><title>{m('parks.title')}</title></svelte:head>

<div class="page">
	<a href="/races" class="back-link" data-testid="parks-back-to-races">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('races.pageTitle')}
	</a>
	<PageHeader title={m('parks.title')} subtitle={m('parks.intro')} />

	{#if loading}
		<p class="state-msg">{m('parks.loading')}</p>
	{:else if loadFailed}
		<EmptyState icon="error" tone="danger" title={m('parks.loadFailed')} role="alert" data-testid="parks-load-error">
			{#snippet actions()}
				<button type="button" class="btn btn-outline" onclick={load}>{m('parks.retry')}</button>
			{/snippet}
		</EmptyState>
	{:else if parks.length === 0}
		<EmptyState icon="park" title={m('parks.empty')} data-testid="parks-empty">
			{#snippet actions()}
				<a class="btn btn-outline" href="/segments">
					<span class="material-symbols" aria-hidden="true">terrain</span>
					{m('runSurface.tabSegments')}
				</a>
			{/snippet}
		</EmptyState>
	{:else}
		<div class="parks-search">
			<AppSearchField bind:value={query} label={m('parks.searchPlaceholder')} testid="parks-search" />
		</div>
		{#if groups.length === 0}
			<EmptyState icon="search_off" title={m('parks.noMatch', { query: settledQuery.trim() })} data-testid="parks-no-match">
				{#snippet actions()}
					<button type="button" class="btn btn-outline" onclick={clearSearch} data-testid="parks-clear-search">
						{m('filterBar.clearSearch')}
					</button>
				{/snippet}
			</EmptyState>
		{/if}
		{#each groups as group (group.regionCode)}
			<section class="region" data-testid="parks-region" aria-labelledby="region-{group.regionCode}">
				<SectionHeader label={regionName(group.regionCode)} id="region-{group.regionCode}" class="parks-region-head" />
				<ul class="park-grid">
					{#each group.parks as park (park.id)}
						<li><ParkCard {park} courses={byPark.get(park.id) ?? []} /></li>
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
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		text-decoration: none;
	}
	.parks-search {
		max-width: 32rem;
	}
	.state-msg {
		color: var(--color-text-tertiary);
	}
	:global(.parks-region-head) {
		margin-top: var(--space-lg);
	}
	.park-grid {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(20rem, 100%), 1fr));
		gap: var(--space-md);
	}
</style>
