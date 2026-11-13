<script lang="ts">
	import SectionHeader from '#lib/components/SectionHeader.svelte';
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { formatElevation } from '#lib/format/units.svelte.ts';
	import { formatDuration } from '#lib/format/time.ts';
	import {
		fetchPark,
		fetchParkCourseMonthRunners,
		fetchParkCourseRecords,
		fetchParkCourses,
		type Park,
		type ParkCourse,
		type ParkCourseRecord,
	} from '#lib/core/data.ts';
	import { regionCodeFromSlug, regionName } from '#lib/parks/park_courses.ts';
	import {
		AGENCY_LABEL,
		DIFFICULTY_LABEL,
		SHAPE_LABEL,
		STATUS_LABEL,
		labelKey,
	} from '#lib/parks/park_labels.ts';
	import { courseLapsChip, courseShapeShown, sortParkCourses } from '#lib/parks/park_course_distance.ts';
	import { fmtCourseDistance } from '#lib/parks/course_distance_format.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import TrackPreview from '#lib/components/TrackPreview.svelte';
	import ParkCoursesMap from '#lib/components/parks/ParkCoursesMap.svelte';
	import ParkMapLegend from '#lib/components/parks/ParkMapLegend.svelte';
	import type { TrackPoint } from '#lib/types.ts';

	let { data } = $props();

	let park = $state<Park | null>(null);
	let courses = $state<ParkCourse[]>([]);
	let loading = $state(true);
	let loadFailed = $state(false);
	// The season's records are an auxiliary read on their own: when it fails
	// the courses still list, without records. Signed out, there is none.
	let records = $state<Map<string, ParkCourseRecord>>(new Map());
	let recordsFailed = $state(false);
	// How many ran each course this month where the park is, an auxiliary
	// read of its own like the records. A course nobody ran this month has
	// no entry and no line.
	let monthRunners = $state<Map<string, number>>(new Map());
	let monthRunnersFailed = $state(false);
	let highlightId = $state<string | null>(null);

	const sorted = $derived(
		sortParkCourses(courses, (c) => ({
			distanceM: Number(c.segment.distance_m),
			name: c.segment.name,
			slug: c.slug,
			status: c.status,
		})),
	);

	function pointsOf(course: ParkCourse): TrackPoint[] {
		return course.segment.waypoints.map((w) => ({ lat: Number(w.lat), lng: Number(w.lng), ele: w.ele }));
	}

	const mapCourses = $derived(sorted.map((c) => ({ id: c.id, points: pointsOf(c) })));
	const hasLines = $derived(mapCourses.some((c) => c.points.length >= 2));

	async function loadRecords() {
		recordsFailed = false;
		if (!auth.loggedIn) return;
		try {
			records = await fetchParkCourseRecords();
		} catch (e) {
			console.error('park course records read failed', e);
			recordsFailed = true;
		}
	}

	async function loadMonthRunners(parkId: string) {
		monthRunnersFailed = false;
		if (!auth.loggedIn) return;
		try {
			monthRunners = await fetchParkCourseMonthRunners(parkId);
		} catch (e) {
			console.error('park course month runners read failed', e);
			monthRunnersFailed = true;
		}
	}

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
		if (park && courses.length > 0) {
			void loadRecords();
			void loadMonthRunners(park.id);
		}
	}

	onMount(async () => {
		await auth.ready();
		await load();
	});
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
		<EmptyState icon="error" tone="danger" title={m('parks.loadFailed')} role="alert" data-testid="park-load-error">
			{#snippet actions()}
				<button type="button" class="btn btn-outline" onclick={load}>{m('parks.retry')}</button>
			{/snippet}
		</EmptyState>
	{:else if !park}
		<EmptyState
			icon="park"
			title={m('parks.parkNotFoundTitle')}
			text={m('parks.parkNotFoundBody')}
			data-testid="park-not-found"
		/>
	{:else}
		{@const agencyKey = labelKey(AGENCY_LABEL, park.agency)}
		<header class="detail-header">
			<h1>{park.name}</h1>
			<ul class="meta" data-testid="park-meta">
				<li>
					<span class="material-symbols" aria-hidden="true">place</span>
					{regionName(park.region_code)}
				</li>
				{#if agencyKey}<li>{m(agencyKey)}</li>{/if}
				{#if park.website_url}
					<li>
						<a class="website" href={park.website_url} target="_blank" rel="noopener noreferrer" data-testid="park-website">
							{m('parks.website')}
							<span class="material-symbols" aria-hidden="true">open_in_new</span>
						</a>
					</li>
				{/if}
			</ul>
			{#if park.description}<p class="description">{park.description}</p>{/if}
		</header>

		{#if courses.length === 0}
			<EmptyState icon="route" title={m('parks.noCourses')} data-testid="park-no-courses" />
		{:else}
			<div class="park-layout" class:with-map={hasLines}>
				<section class="courses" aria-labelledby="park-courses-title">
					<SectionHeader title label={m('parks.coursesTitle')} id="park-courses-title">
						{#snippet badge()}
							<span class="count">{m('parks.courseCount', { n: courses.length })}</span>
						{/snippet}
					</SectionHeader>
					{#if recordsFailed}
						<p class="records-failed" role="status" data-testid="park-records-failed">
							{m('races.anyTimeFastestFailed')}
						</p>
					{/if}
					{#if monthRunnersFailed}
						<p class="records-failed" role="status" data-testid="park-month-runners-failed">
							{m('parks.monthRunnersFailed')}
							<button type="button" class="btn btn-outline btn-sm" onclick={() => park && void loadMonthRunners(park.id)}>
								{m('parks.retry')}
							</button>
						</p>
					{/if}
					<ul class="course-list" data-testid="park-courses">
						{#each sorted as course (course.id)}
							{@const shapeKey = courseShapeShown(course.course_shape) ? labelKey(SHAPE_LABEL, course.course_shape) : null}
							{@const statusKey = labelKey(STATUS_LABEL, course.status)}
							{@const difficultyKey = labelKey(DIFFICULTY_LABEL, course.difficulty)}
							{@const laps = courseLapsChip(course.laps)}
							{@const gain = Number(course.segment.elevation_m)}
							{@const record = records.get(course.id)}
							{@const ranThisMonth = monthRunners.get(course.id) ?? 0}
							{@const points = pointsOf(course)}
							<li
								onmouseenter={() => (highlightId = course.id)}
								onmouseleave={() => (highlightId = null)}
								onfocusin={() => (highlightId = course.id)}
								onfocusout={() => (highlightId = null)}
							>
								<a
									href="/parks/{data.region}/{park.slug}/{course.slug}"
									class="course-card"
									class:closed={course.status === 'closed'}
									data-testid="park-course-card"
								>
									<span class="thumb" aria-hidden="true">
										{#if points.length >= 2}<TrackPreview {points} aspect={1.4} />{/if}
									</span>
									<span class="course-body">
										<span class="course-name">{course.segment.name}</span>
										<span class="facts">
											<span class="fact distance" data-testid="park-course-distance">{fmtCourseDistance(course.segment.distance_m)}</span>
											{#if laps}<span class="chip" data-testid="park-course-laps">{m('parks.lapsChip', { n: laps })}</span>{/if}
											{#if shapeKey}<span class="chip">{m(shapeKey)}</span>{/if}
											{#if Number.isFinite(gain) && gain > 0}
												<span class="fact">
													<span class="material-symbols" aria-hidden="true">trending_up</span>
													<span class="visually-hidden">{m('parks.statElevation')}</span>
													{formatElevation(gain)}
												</span>
											{/if}
											{#if difficultyKey}<span class="fact">{m(difficultyKey)}</span>{/if}
										</span>
										{#if auth.loggedIn && !recordsFailed}
											<span class="course-record" data-testid="park-course-record">
												<span class="material-symbols" aria-hidden="true">emoji_events</span>
												{#if record}
													{record.displayName
														? m('races.anyTimeFastestBy', { year: record.season, time: formatDuration(record.timeSeconds), name: record.displayName })
														: m('races.anyTimeFastest', { year: record.season, time: formatDuration(record.timeSeconds) })}
												{:else}
													{m('races.anyTimeNoTimeYet')}
												{/if}
											</span>
										{/if}
										{#if ranThisMonth > 0}
											<span class="course-record" data-testid="park-course-month-runners">
												<span class="material-symbols month-icon" aria-hidden="true">calendar_month</span>
												{m('parks.monthRunners', { n: ranThisMonth })}
											</span>
										{/if}
									</span>
									{#if course.status !== 'open' && statusKey}
										<span class="status-pill" class:closed={course.status === 'closed'}>{m(statusKey)}</span>
									{/if}
								</a>
							</li>
						{/each}
					</ul>
				</section>

				{#if hasLines}
					<section class="overview" aria-label={m('parks.overviewMapLabel', { park: park.name })}>
						<div class="map-frame">
							<ParkCoursesMap
								courses={mapCourses}
								{highlightId}
								label={m('parks.overviewMapLabel', { park: park.name })}
								testid="park-overview-map"
							/>
						</div>
						<ParkMapLegend
							testid="park-map-legend"
							items={[
								{ kind: 'line', label: m('parks.legendCourse') },
								{ kind: 'focusedLine', label: m('parks.legendHighlighted') },
								{ kind: 'trailhead', label: m('parks.legendStart') },
							]}
						/>
					</section>
				{/if}
			</div>
		{/if}
		<p class="not-affiliated" data-testid="park-not-affiliated">{m('parks.notAffiliated')}</p>
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
	.loading {
		min-height: 40vh;
	}
	.detail-header {
		margin-bottom: var(--space-lg);
	}
	.detail-header h1 {
		margin: 0 0 var(--space-xs);
	}
	.meta {
		list-style: none;
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-xs) var(--space-sm);
		margin: 0;
		padding: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.meta li {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
	}
	.meta li + li::before {
		content: '·';
		margin-inline-end: var(--space-sm);
		color: var(--color-text-tertiary);
	}
	.meta .material-symbols {
		font-size: 1rem;
	}
	.website {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
	}
	.description {
		max-width: var(--page-measure);
		margin: var(--space-sm) 0 0;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.park-layout {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-lg);
	}
	.overview {
		order: -1;
	}
	.map-frame {
		height: 16rem;
	}
	@media (min-width: 64rem) {
		.park-layout.with-map {
			grid-template-columns: minmax(0, 5fr) minmax(0, 6fr);
			align-items: start;
		}
		.overview {
			order: 0;
			position: sticky;
			top: var(--space-md);
		}
		.map-frame {
			height: min(32rem, 70vh);
		}
	}
	.count {
		font-size: 0.85rem;
		font-weight: 400;
		color: var(--color-text-tertiary);
	}
	.records-failed {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin: 0 0 var(--space-sm);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.course-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.course-card {
		display: grid;
		grid-template-columns: 4.5rem minmax(0, 1fr) auto;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md) var(--space-sm) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		text-decoration: none;
	}
	.course-card:hover,
	.course-card:focus-visible {
		border-color: var(--color-primary);
	}
	.course-card.closed .thumb,
	.course-card.closed .course-name {
		opacity: 0.6;
	}
	.thumb {
		width: 4.5rem;
		height: 3.2rem;
		border-radius: var(--radius-sm);
		background: var(--color-fill-subtle);
		overflow: hidden;
	}
	.course-body {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		min-width: 0;
	}
	.course-name {
		font-weight: 600;
	}
	.facts {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.25rem var(--space-sm);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.fact {
		display: inline-flex;
		align-items: center;
		gap: 0.15rem;
	}
	.fact .material-symbols {
		font-size: 1rem;
	}
	.distance {
		font-weight: 600;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.chip {
		padding: 0.05rem 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--chip-bg);
		color: var(--chip-fg);
		font-size: 0.75rem;
		font-weight: 600;
	}
	.course-record {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.course-record .material-symbols {
		font-size: 1rem;
		color: var(--color-crown);
	}
	.course-record .month-icon {
		color: var(--color-text-tertiary);
	}
	.status-pill {
		padding: 0.1rem 0.5rem;
		border-radius: var(--radius-pill);
		font-size: 0.75rem;
		background: var(--color-bg-secondary);
	}
	.status-pill.closed {
		color: var(--color-danger-text);
	}
	.not-affiliated {
		max-width: var(--page-measure);
		margin: var(--space-xl) 0 0;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
	}
	@media (max-width: 30rem) {
		.course-card {
			grid-template-columns: 3.5rem minmax(0, 1fr);
		}
		.thumb {
			width: 3.5rem;
			height: 2.6rem;
		}
		.status-pill {
			grid-column: 2;
			justify-self: start;
		}
	}
</style>
