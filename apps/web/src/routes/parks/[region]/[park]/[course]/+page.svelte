<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { routeSurfaceLabel } from '#lib/i18n/enum_labels.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { activeFormatLocale, formatDuration } from '#lib/format/time.ts';
	import { distanceInPreferred, formatElevation } from '#lib/format/units.svelte.ts';
	import {
		fetchGlobalSegmentCompletions,
		fetchGlobalSegmentLeaderboard,
		fetchPark,
		fetchParkCourses,
		SEGMENT_AGE_BANDS,
		type CompletionsEntry,
		type GlobalSegmentLeaderboardEntry,
		type Park,
		type ParkCourse,
		type SegmentAgeBand,
		type SegmentGenderFilter,
	} from '#lib/core/data.ts';
	import {
		courseAttribution,
		isLongCourse,
		parkCourseGpx,
		regionCodeFromSlug,
		regionName,
	} from '#lib/parks/park_courses.ts';
	import { downloadFile } from '#lib/routes/gpx.ts';
	import { PUBLIC_SITE_URL } from '$app/env/public';
	import { siteOrigin } from '#lib/core/site_url.ts';
	import { buildCourseShareCanonical } from '#lib/share/share_course_meta.ts';
	import {
		ATTRIBUTION_LABEL,
		DIFFICULTY_LABEL,
		SHAPE_LABEL,
		STATUS_LABEL,
		labelKey,
	} from '#lib/parks/park_labels.ts';
	import Avatar from '#lib/components/Avatar.svelte';
	import OldMatchNote from '#lib/components/OldMatchNote.svelte';
	import HelpLink from '#lib/components/help/HelpLink.svelte';
	import RunMap from '#lib/components/RunMap.svelte';
	import HeadToHeadDialog from '#lib/components/HeadToHeadDialog.svelte';
	import type { TrackPoint } from '#lib/types.ts';

	let { data } = $props();

	// The indexable home of a course is its share page, keyed by the same
	// three slugs as this URL, so the canonical needs no data load.
	let canonicalUrl = $derived(
		buildCourseShareCanonical(
			siteOrigin(PUBLIC_SITE_URL),
			`${data.region}/${data.park}/${data.course}`,
		),
	);

	let park = $state<Park | null>(null);
	let course = $state<ParkCourse | null>(null);
	let loading = $state(true);
	let loadFailed = $state(false);

	type BoardKind = 'fastest' | 'completions';
	let boardKind = $state<BoardKind>('fastest');
	let allTime = $state(false);
	let genderFilter = $state<SegmentGenderFilter | null>(null);
	let ageFilter = $state<SegmentAgeBand | null>(null);
	let fastest = $state<GlobalSegmentLeaderboardEntry[] | null>(null);
	let completions = $state<CompletionsEntry[] | null>(null);
	let boardFailed = $state(false);
	let showHeadToHead = $state(false);

	const season = $derived(allTime ? null : (park?.park_season ?? null));

	// Curated catalogue geometry (a world-readable table), never a runner's
	// trace, so it renders directly.
	const mapTrack = $derived<TrackPoint[]>(
		(course?.segment.waypoints ?? []).map((w) => ({
			lat: Number(w.lat),
			lng: Number(w.lng),
			ele: w.ele,
		})),
	);

	async function load() {
		loading = true;
		loadFailed = false;
		try {
			const regionCode = regionCodeFromSlug(data.region);
			park = regionCode ? await fetchPark(regionCode, data.park) : null;
			const courses = park ? await fetchParkCourses(park.id) : [];
			course = courses.find((c) => c.slug === data.course) ?? null;
		} catch (e) {
			console.error('park course load failed', e);
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	async function refreshBoard(segmentId: string) {
		boardFailed = false;
		fastest = null;
		completions = null;
		try {
			if (boardKind === 'fastest') {
				fastest = await fetchGlobalSegmentLeaderboard(segmentId, {
					gender: genderFilter,
					ageBand: ageFilter,
					season,
				});
			} else {
				completions = await fetchGlobalSegmentCompletions(segmentId, season);
			}
		} catch (e) {
			console.error('park course board failed', e);
			boardFailed = true;
		}
	}

	$effect(() => {
		const deps = [boardKind, season, genderFilter, ageFilter];
		void deps;
		if (course && auth.loggedIn) void refreshBoard(course.segment.id);
	});

	onMount(async () => {
		await auth.ready();
		await load();
	});

	function fmtDist(metres: number): string {
		const { value, unit } = distanceInPreferred(metres);
		return `${value.toFixed(2)} ${unit}`;
	}

	function downloadGpx() {
		if (!park || !course) return;
		const gpx = parkCourseGpx({
			name: course.segment.name,
			waypoints: mapTrack,
			checkpoints: course.checkpoints,
			attribution: courseAttribution(course.geometry_source, {
				name: park.name,
				websiteUrl: park.website_url,
			}),
		});
		const base = course.segment.name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_');
		downloadFile(gpx, `${base || 'course'}.gpx`, 'application/gpx+xml');
	}

	const shapeKey = $derived(labelKey(SHAPE_LABEL, course?.course_shape));
	const difficultyKey = $derived(labelKey(DIFFICULTY_LABEL, course?.difficulty));
	const statusKey = $derived(labelKey(STATUS_LABEL, course?.status));
	const attributionKey = $derived(labelKey(ATTRIBUTION_LABEL, course?.geometry_source));
	const statusCheckedLabel = $derived(
		course?.status_checked_at
			? new Date(course.status_checked_at).toLocaleDateString(activeFormatLocale(), { dateStyle: 'medium' })
			: null,
	);
</script>

<svelte:head>
	<title>{course?.segment.name ?? m('parks.title')}</title>
	<link rel="canonical" href={canonicalUrl} />
</svelte:head>

<div class="page">
	{#if park}
		<a href="/parks/{data.region}/{park.slug}" class="back-link">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{park.name}
		</a>
	{:else}
		<a href="/parks" class="back-link">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{m('parks.backToParks')}
		</a>
	{/if}

	{#if loading}
		<p class="loading">&nbsp;</p>
	{:else if loadFailed}
		<div class="not-found" role="alert" data-testid="park-course-load-error">
			<p>{m('parks.loadFailed')}</p>
			<button type="button" class="btn btn-outline" onclick={load}>{m('parks.retry')}</button>
		</div>
	{:else if !park || !course}
		<div class="not-found" data-testid="park-course-not-found">
			<h1>{m('parks.courseNotFoundTitle')}</h1>
			<p>{m('parks.courseNotFoundBody')}</p>
		</div>
	{:else}
		<header class="detail-header">
			<h1>{course.segment.name}</h1>
			<HelpLink route="/parks/[region]/[park]/[course]" />
			<p class="meta">
				<span class="material-symbols" aria-hidden="true">park</span>
				{park.name}&nbsp;·&nbsp;{regionName(park.region_code)}
			</p>
			{#if course.status === 'closed'}
				<p class="closed-banner" role="status" data-testid="park-course-closed">
					<span class="material-symbols" aria-hidden="true">block</span>
					{m('parks.closedBanner')}
				</p>
			{/if}
			<div class="key-stats">
				<div class="key-stat">
					<span class="key-stat-value">{fmtDist(Number(course.segment.distance_m))}</span>
					<span class="key-stat-label">{m('parks.statDistance')}</span>
				</div>
				{#if course.segment.elevation_m != null && Number(course.segment.elevation_m) > 0}
					<div class="key-stat">
						<span class="key-stat-value">{formatElevation(Number(course.segment.elevation_m))}</span>
						<span class="key-stat-label">{m('parks.statElevation')}</span>
					</div>
				{/if}
				{#if shapeKey}
					<div class="key-stat">
						<span class="key-stat-value">{m(shapeKey)}</span>
						<span class="key-stat-label">{m('parks.statShape')}</span>
					</div>
				{/if}
				{#if course.segment.surface}
					<div class="key-stat">
						<span class="key-stat-value">{routeSurfaceLabel(course.segment.surface)}</span>
						<span class="key-stat-label">{m('parks.statSurface')}</span>
					</div>
				{/if}
				{#if difficultyKey}
					<div class="key-stat">
						<span class="key-stat-value">{m(difficultyKey)}</span>
						<span class="key-stat-label">{m('parks.statDifficulty')}</span>
					</div>
				{/if}
			</div>
			{#if course.status !== 'open' && statusKey}
				<p class="status-line">
					{m(statusKey)}{#if course.status_note}: {course.status_note}{/if}
					{#if statusCheckedLabel}
						<span class="muted">({m('parks.statusChecked', { date: statusCheckedLabel })})</span>
					{/if}
				</p>
			{/if}
			{#if course.segment.description}
				<p class="description">{course.segment.description}</p>
			{/if}
		</header>

		{#if mapTrack.length >= 2}
			<section class="section">
				<div class="map-wrap"><RunMap track={mapTrack} /></div>
				{#if attributionKey}
					<p class="attribution" data-testid="park-course-attribution">{m(attributionKey)}</p>
				{/if}
			</section>
		{/if}

		<p class="not-affiliated" data-testid="park-course-not-affiliated">{m('parks.notAffiliated')}</p>

		<p class="safety" data-testid="park-course-safety">
			<span class="material-symbols" aria-hidden="true">info</span>
			{m('parks.safetyNotice')}
		</p>
		{#if isLongCourse(Number(course.segment.distance_m))}
			<p class="safety" data-testid="park-course-long">
				<span class="material-symbols" aria-hidden="true">schedule</span>
				{m('parks.longCourseNotice')}
			</p>
		{/if}

		<div class="course-actions">
			{#if course.route_id && course.status !== 'closed'}
				<a class="btn btn-outline btn-sm navigate" href="/routes/{course.route_id}">
					<span class="material-symbols" aria-hidden="true">directions_run</span>
					{m('parks.navigate')}
				</a>
			{/if}
			{#if mapTrack.length >= 2 && course.status !== 'closed'}
				<button
					type="button"
					class="btn btn-outline btn-sm navigate"
					onclick={downloadGpx}
					data-testid="park-course-gpx"
				>
					<span class="material-symbols" aria-hidden="true">download</span>
					{m('parks.downloadGpx')}
				</button>
			{/if}
		</div>

		<section class="section">
			{#if !auth.loggedIn}
				<p class="muted" data-testid="park-course-sign-in">
					{m('parks.signInForBoards')}
					<a href="/login">{m('parks.signIn')}</a>
				</p>
			{:else}
				<div class="board-head">
					<div class="segmented" role="group">
						<button
							type="button"
							class:active={boardKind === 'fastest'}
							aria-pressed={boardKind === 'fastest'}
							onclick={() => (boardKind = 'fastest')}
							data-testid="park-board-fastest"
						>
							{m('parks.boardFastest')}
						</button>
						<button
							type="button"
							class:active={boardKind === 'completions'}
							aria-pressed={boardKind === 'completions'}
							onclick={() => (boardKind = 'completions')}
							data-testid="park-board-completions"
						>
							{m('parks.boardCompletions')}
						</button>
					</div>
					<div class="segmented" role="group">
						<button
							type="button"
							class:active={!allTime}
							aria-pressed={!allTime}
							onclick={() => (allTime = false)}
							data-testid="park-season-this-year"
						>
							{m('parks.seasonThisYear', { year: park.park_season })}
						</button>
						<button
							type="button"
							class:active={allTime}
							aria-pressed={allTime}
							onclick={() => (allTime = true)}
							data-testid="park-season-all-time"
						>
							{m('parks.seasonAllTime')}
						</button>
					</div>
					<button
						type="button"
						class="btn btn-outline btn-sm h2h-open"
						onclick={() => (showHeadToHead = true)}
					>
						<span class="material-symbols" aria-hidden="true">group</span>
						{m('headToHead.compare')}
					</button>
				</div>

				{#if boardKind === 'fastest'}
					<div class="tier-filters">
						<label>
							{m('segments.gender')}
							<select bind:value={genderFilter}>
								<option value={null}>{m('segments.all')}</option>
								<option value="male">{m('segments.men')}</option>
								<option value="female">{m('segments.women')}</option>
							</select>
						</label>
						<label>
							{m('segments.ageBand')}
							<select bind:value={ageFilter}>
								<option value={null}>{m('segments.allAges')}</option>
								{#each SEGMENT_AGE_BANDS as band}
									<option value={band}>{band}</option>
								{/each}
							</select>
						</label>
					</div>
				{/if}

				{#if boardFailed}
					<p class="muted board-error" role="alert" data-testid="park-board-error">
						{m('parks.boardFailed')}
						<button
							type="button"
							class="btn btn-outline btn-sm"
							onclick={() => course && void refreshBoard(course.segment.id)}
						>
							{m('parks.retry')}
						</button>
					</p>
				{:else if boardKind === 'fastest'}
					<OldMatchNote segment={course.segment} />
					{#if fastest == null}
						<p class="muted">{m('segments.loading')}</p>
					{:else if fastest.length === 0}
						<p class="muted" data-testid="park-board-empty">{m('parks.noEfforts')}</p>
					{:else}
						<ol data-testid="park-board">
							{#each fastest as entry (entry.effort.id)}
								<li class:viewer={entry.effort.user_id === auth.user?.id}>
									<span class="rank">#{entry.rank}</span>
									<a href="/u/{entry.athlete.id}" class="athlete">
										<Avatar url={entry.athlete.avatar_url} name={entry.athlete.display_name} size="1.6rem" font="0.72rem" />
										<span class="athlete-name">{entry.athlete.display_name ?? m('segments.runnerFallback')}</span>
									</a>
									<span class="value">{formatDuration(Math.round(entry.effort.time_seconds))}</span>
								</li>
							{/each}
						</ol>
					{/if}
				{:else if completions == null}
					<p class="muted">{m('segments.loading')}</p>
				{:else if completions.length === 0}
					<p class="muted" data-testid="park-board-empty">{m('parks.noEfforts')}</p>
				{:else}
					<ol data-testid="park-board">
						{#each completions as entry (entry.athlete.id)}
							<li class:viewer={entry.athlete.id === auth.user?.id}>
								<span class="rank">#{entry.rank}</span>
								<a href="/u/{entry.athlete.id}" class="athlete">
									<Avatar url={entry.athlete.avatar_url} name={entry.athlete.display_name} size="1.6rem" font="0.72rem" />
									<span class="athlete-name">{entry.athlete.display_name ?? m('segments.runnerFallback')}</span>
								</a>
								<span class="value">{m('parks.completionDays', { n: entry.completions })}</span>
							</li>
						{/each}
					</ol>
				{/if}
			{/if}
		</section>
		<HeadToHeadDialog
			open={showHeadToHead}
			onclose={() => (showHeadToHead = false)}
			kind="global_segment"
			targetId={course.segment.id}
		/>
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
		margin: 0 0 var(--space-md);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.meta .material-symbols {
		font-size: 1rem;
	}
	.closed-banner {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		max-width: 48rem;
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-warning-light);
		color: var(--color-warning-text);
	}
	.key-stats {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(120px, 100%), 1fr));
		gap: 1px;
		max-width: 48rem;
		background: var(--color-border);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		overflow: hidden;
	}
	.key-stat {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
	}
	.key-stat-value {
		font-size: 1.05rem;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.key-stat-label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-tertiary);
	}
	.status-line,
	.description {
		margin: var(--space-md) 0 0;
		max-width: 48rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.section {
		margin-top: var(--space-lg);
	}
	.map-wrap {
		height: 300px;
		border-radius: var(--radius-md);
		overflow: hidden;
	}
	.attribution {
		margin: 0.3rem 0 0;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}
	.not-affiliated {
		max-width: 48rem;
		margin: var(--space-sm) 0 0;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		line-height: 1.5;
	}
	.safety {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		max-width: 48rem;
		margin: var(--space-md) 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.course-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.navigate {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
	.board-head {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin-bottom: var(--space-sm);
	}
	.segmented {
		display: inline-flex;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		overflow: hidden;
	}
	.segmented button {
		padding: 0.35rem 0.7rem;
		border: none;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		cursor: pointer;
		font-size: 0.85rem;
	}
	.segmented button.active {
		background: var(--color-primary-light);
		color: var(--color-text);
		font-weight: 600;
	}
	.h2h-open {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
	.tier-filters {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.tier-filters label {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-tertiary);
	}
	.tier-filters select {
		padding: 0.3rem 0.5rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		color: var(--color-text);
	}
	.muted {
		margin: 0;
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
	}
	.board-error {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
	}
	ol {
		list-style: none;
		margin: 0;
		padding: 0;
		max-width: 48rem;
	}
	li {
		display: grid;
		grid-template-columns: 2.2rem 1fr auto;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-xs);
		border-bottom: 1px solid var(--color-border);
	}
	li.viewer {
		background: var(--color-primary-light);
		border-radius: var(--radius-sm);
	}
	.rank {
		text-align: center;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-variant-numeric: tabular-nums;
	}
	.athlete {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		min-width: 0;
		color: var(--color-text);
		text-decoration: none;
	}
	.athlete-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.value {
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
</style>
