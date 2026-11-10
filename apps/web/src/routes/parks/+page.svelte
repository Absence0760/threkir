<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { fetchAllParkCourses, fetchParks, type Park, type ParkCourseWithPark } from '#lib/core/data.ts';
	import { groupParksByRegion, regionName, regionSlug } from '#lib/parks/park_courses.ts';
	import { AGENCY_LABEL, labelKey } from '#lib/parks/park_labels.ts';
	import { fmtCourseDistanceRange } from '#lib/parks/course_distance_format.ts';
	import ParkCourseLinesThumb from '#lib/components/parks/ParkCourseLinesThumb.svelte';
	import type { TrackPoint } from '#lib/types.ts';

	let parks = $state<Park[]>([]);
	let loading = $state(true);
	let loadFailed = $state(false);
	// The courses are an auxiliary read: when it fails the parks still list,
	// without their course count, distances and thumbnail.
	let courses = $state<ParkCourseWithPark[]>([]);

	const groups = $derived(groupParksByRegion(parks));

	const byPark = $derived.by(() => {
		const out = new Map<string, ParkCourseWithPark[]>();
		for (const c of courses) {
			const list = out.get(c.park_id);
			if (list) list.push(c);
			else out.set(c.park_id, [c]);
		}
		return out;
	});

	function linesOf(list: ParkCourseWithPark[]): TrackPoint[][] {
		return list.map((c) => c.segment.waypoints.map((w) => ({ lat: Number(w.lat), lng: Number(w.lng) })));
	}

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
	<header class="page-header">
		<h1>{m('parks.title')}</h1>
		<p class="subtitle">{m('parks.intro')}</p>
	</header>

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
		{#each groups as group (group.regionCode)}
			<section class="region" data-testid="parks-region" aria-labelledby="region-{group.regionCode}">
				<h2 id="region-{group.regionCode}">{regionName(group.regionCode)}</h2>
				<ul class="park-grid">
					{#each group.parks as park (park.id)}
						{@const agencyKey = labelKey(AGENCY_LABEL, park.agency)}
						{@const list = byPark.get(park.id) ?? []}
						{@const range = fmtCourseDistanceRange(list.map((c) => c.segment.distance_m))}
						{@const lines = linesOf(list)}
						<li>
							<a href="/parks/{regionSlug(park.region_code)}/{park.slug}" class="park-card" data-testid="park-card">
								<span class="thumb" aria-hidden="true">
									{#if lines.some((l) => l.length >= 2)}
										<ParkCourseLinesThumb {lines} />
									{:else}
										<span class="material-symbols thumb-icon">park</span>
									{/if}
								</span>
								<span class="park-text">
									<span class="park-name">{park.name}</span>
									{#if agencyKey}<span class="park-agency">{m(agencyKey)}</span>{/if}
									{#if list.length > 0}
										<span class="park-facts" data-testid="park-card-facts">
											{m('parks.courseCount', { n: list.length })}{#if range}&nbsp;·&nbsp;{range}{/if}
										</span>
									{/if}
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
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		text-decoration: none;
	}
	.page-header h1 {
		margin: 0 0 0.25rem;
	}
	.subtitle {
		margin: 0 0 var(--space-lg);
		max-width: var(--page-measure);
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.state-msg {
		color: var(--color-text-tertiary);
	}
	.region h2 {
		margin: var(--space-lg) 0 var(--space-sm);
		font-size: var(--font-size-section-label);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: var(--section-label-tracking);
		color: var(--color-text-secondary);
	}
	.park-grid {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(20rem, 100%), 1fr));
		gap: var(--space-md);
	}
	.park-card {
		display: flex;
		flex-direction: column;
		height: 100%;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		text-decoration: none;
		overflow: hidden;
	}
	.park-card:hover,
	.park-card:focus-visible {
		border-color: var(--color-primary);
	}
	.thumb {
		display: flex;
		align-items: center;
		justify-content: center;
		aspect-ratio: 2 / 1;
		background: var(--color-fill-subtle);
	}
	.thumb-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
	}
	.park-text {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		padding: var(--space-sm) var(--space-md) var(--space-md);
		min-width: 0;
	}
	.park-name {
		font-weight: 600;
		font-size: 1.05rem;
	}
	.park-agency {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}
	.park-facts {
		margin-top: var(--space-xs);
		font-size: 0.875rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
</style>
