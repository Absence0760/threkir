<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { distanceInPreferred } from '#lib/format/units.svelte.ts';
	import { fetchPark, fetchParkCourses, type Park, type ParkCourse } from '#lib/core/data.ts';
	import { regionCodeFromSlug, regionName } from '#lib/parks/park_courses.ts';
	import { AGENCY_LABEL, SHAPE_LABEL, STATUS_LABEL, labelKey } from '#lib/parks/park_labels.ts';

	let { data } = $props();

	let park = $state<Park | null>(null);
	let courses = $state<ParkCourse[]>([]);
	let loading = $state(true);
	let loadFailed = $state(false);

	async function load() {
		loading = true;
		loadFailed = false;
		try {
			const regionCode = regionCodeFromSlug(data.region);
			park = regionCode ? await fetchPark(regionCode, data.park) : null;
			courses = park ? await fetchParkCourses(park.id) : [];
		} catch (e) {
			console.error('park load failed', e);
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	onMount(async () => {
		await auth.ready();
		await load();
	});

	function fmtDist(metres: number): string {
		const { value, unit } = distanceInPreferred(metres);
		return `${value.toFixed(2)} ${unit}`;
	}
</script>

<svelte:head><title>{park?.name ?? m('parks.title')}</title></svelte:head>

<div class="page">
	<a href="/parks" class="back-link">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('parks.backToParks')}
	</a>

	{#if loading}
		<p class="loading">&nbsp;</p>
	{:else if loadFailed}
		<div class="not-found" role="alert" data-testid="park-load-error">
			<p>{m('parks.loadFailed')}</p>
			<button type="button" class="btn btn-outline" onclick={load}>{m('parks.retry')}</button>
		</div>
	{:else if !park}
		<div class="not-found" data-testid="park-not-found">
			<h1>{m('parks.parkNotFoundTitle')}</h1>
			<p>{m('parks.parkNotFoundBody')}</p>
		</div>
	{:else}
		{@const agencyKey = labelKey(AGENCY_LABEL, park.agency)}
		<header class="detail-header">
			<h1>{park.name}</h1>
			<p class="meta">
				<span class="material-symbols" aria-hidden="true">place</span>
				{regionName(park.region_code)}{#if agencyKey}&nbsp;·&nbsp;{m(agencyKey)}{/if}
			</p>
			{#if park.description}<p class="description">{park.description}</p>{/if}
			{#if park.website_url}
				<a class="website" href={park.website_url} target="_blank" rel="noopener noreferrer">
					{m('parks.website')}
					<span class="material-symbols" aria-hidden="true">open_in_new</span>
				</a>
			{/if}
		</header>

		{#if courses.length === 0}
			<p class="state-msg">{m('parks.noCourses')}</p>
		{:else}
			<ul class="course-list" data-testid="park-courses">
				{#each courses as course (course.id)}
					{@const shapeKey = labelKey(SHAPE_LABEL, course.course_shape)}
					{@const statusKey = labelKey(STATUS_LABEL, course.status)}
					<li>
						<a href="/parks/{data.region}/{park.slug}/{course.slug}" class="course-card">
							<span class="course-name">{course.segment.name}</span>
							<span class="course-meta">
								{fmtDist(Number(course.segment.distance_m))}
								{#if shapeKey}&nbsp;·&nbsp;{m(shapeKey)}{/if}
							</span>
							{#if course.status !== 'open' && statusKey}
								<span class="status-pill" class:closed={course.status === 'closed'}>{m(statusKey)}</span>
							{/if}
						</a>
					</li>
				{/each}
			</ul>
		{/if}
		<p class="not-affiliated" data-testid="park-not-affiliated">{m('parks.notAffiliated')}</p>
	{/if}
</div>

<style>
	.not-affiliated {
		max-width: 48rem;
		margin: var(--space-lg) 0 0;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
	}
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
	.loading {
		min-height: 40vh;
	}
	.not-found {
		text-align: center;
		padding: var(--space-xl) 0;
	}
	.detail-header h1 {
		margin: 0 0 0.25rem;
	}
	.meta {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		margin: 0 0 var(--space-sm);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.meta .material-symbols {
		font-size: 1rem;
	}
	.description {
		max-width: 48rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.website {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		font-size: 0.9rem;
	}
	.website .material-symbols {
		font-size: 1rem;
	}
	.state-msg {
		color: var(--color-text-tertiary);
	}
	.course-list {
		list-style: none;
		margin: var(--space-lg) 0 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		max-width: 48rem;
	}
	.course-card {
		display: grid;
		grid-template-columns: 1fr auto;
		align-items: center;
		gap: 0.15rem var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		text-decoration: none;
	}
	.course-card:hover {
		border-color: var(--color-primary);
	}
	.course-name {
		font-weight: 600;
	}
	.course-meta {
		grid-column: 1;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.status-pill {
		grid-column: 2;
		grid-row: 1 / span 2;
		padding: 0.1rem 0.5rem;
		border-radius: 999px;
		font-size: 0.75rem;
		background: var(--color-bg-secondary);
	}
	.status-pill.closed {
		color: var(--color-danger-text);
	}
</style>
