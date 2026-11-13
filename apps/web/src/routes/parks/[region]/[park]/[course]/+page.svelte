<script lang="ts">
	import SectionHeader from '#lib/components/SectionHeader.svelte';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { currentLocale, m } from '#lib/i18n/store.svelte.ts';
	import { routeSurfaceLabel } from '#lib/i18n/enum_labels.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { activeFormatLocale, formatDuration } from '#lib/format/time.ts';
	import { formatElevation, getUnit } from '#lib/format/units.svelte.ts';
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
		boardPeriodArgs,
		boardPeriodParam,
		courseAttribution,
		courseOffersWayfinding,
		parkCourseGpx,
		parseBoardPeriod,
		parseSharedUse,
		regionCodeFromSlug,
		regionName,
		stepBoardMonth,
		type BoardPeriod,
		type ParkNow,
	} from '#lib/parks/park_courses.ts';
	import { monthYearLabel } from '#lib/format/calendar.ts';
	import { downloadFile } from '#lib/routes/gpx.ts';
	import { PUBLIC_SITE_URL } from '$app/env/public';
	import { siteOrigin } from '#lib/core/site_url.ts';
	import { buildCourseShareCanonical } from '#lib/share/share_course_meta.ts';
	import {
		DIFFICULTY_LABEL,
		SHAPE_LABEL,
		STATUS_LABEL,
		courseCredit,
		labelKey,
	} from '#lib/parks/park_labels.ts';
	import { courseLapsChip, courseShapeShown } from '#lib/parks/park_course_distance.ts';
	import { fmtCourseDistance } from '#lib/parks/course_distance_format.ts';
	import { checkpointPinColour, finishesAtStart } from '#lib/parks/course_map.ts';
	import { PUBLIC_MAPTILER_KEY } from '$app/env/public';
	import { basemapIsDarkFromEnv } from '#lib/routes/map-style.svelte.ts';
	import Avatar from '#lib/components/Avatar.svelte';
	import OldMatchNote from '#lib/components/OldMatchNote.svelte';
	import HelpLink from '#lib/components/help/HelpLink.svelte';
	import RunMap from '#lib/components/RunMap.svelte';
	import type { MapMarkerPin } from '#lib/components/RunMap.svelte';
	import ElevationProfile from '#lib/components/ElevationProfile.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import ParkCourseNotices from '#lib/components/parks/ParkCourseNotices.svelte';
	import ParkCourseRouteGuide from '#lib/components/parks/ParkCourseRouteGuide.svelte';
	import { parseRouteGuide } from '#lib/parks/route_guide.ts';
	import ParkCourseReportDialog from '#lib/components/parks/ParkCourseReportDialog.svelte';
	import ParkMapLegend, { type ParkMapLegendItem } from '#lib/components/parks/ParkMapLegend.svelte';
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
	// Read from `?period=` once the park says what month it is there; null
	// until then. This year is the default and keeps the URL bare.
	let period = $state<BoardPeriod | null>(null);
	let genderFilter = $state<SegmentGenderFilter | null>(null);
	let ageFilter = $state<SegmentAgeBand | null>(null);
	let fastest = $state<GlobalSegmentLeaderboardEntry[] | null>(null);
	let completions = $state<CompletionsEntry[] | null>(null);
	let boardFailed = $state(false);
	let showHeadToHead = $state(false);
	let showReport = $state(false);
	// Whether the course has any time at all, on any board: until it has, the
	// board kinds, seasons and filters have nothing to switch between, so the
	// section is an invitation instead. Read from the all-time completions
	// board, which throws on a failed read rather than reading as empty.
	let anyTimes = $state<boolean | null>(null);
	let probeFailed = $state(false);
	let chartHoverIdx = $state<number | null>(null);

	const parkNow = $derived<ParkNow | null>(park ? { season: park.park_season, month: park.park_month } : null);
	const periodArgs = $derived(period ? boardPeriodArgs(period) : null);
	const prevMonth = $derived(period && parkNow ? stepBoardMonth(period, -1, parkNow) : null);
	const nextMonth = $derived(period && parkNow ? stepBoardMonth(period, 1, parkNow) : null);

	// The choice is a shallow navigation, as `?show=` on Races & courses is:
	// the board reloads, the map and the scroll stay. `page.shallow.url` is
	// what it wrote; a `?period=` link followed while the page is open lands
	// in `page.url`.
	const shownUrl = () => page.shallow?.url ?? page.url;
	$effect(() => {
		const raw = shownUrl().searchParams.get('period');
		if (parkNow) period = parseBoardPeriod(raw, parkNow) ?? { kind: 'year', season: parkNow.season };
	});

	function setPeriod(next: BoardPeriod) {
		period = next;
		const url = shownUrl();
		const params = new URLSearchParams(url.search);
		const value = boardPeriodParam(next);
		if (value) params.set('period', value);
		else params.delete('period');
		const rest = params.toString();
		void goto(`${url.pathname}${rest ? `?${rest}` : ''}`, { replace: true, shallow: true });
	}

	function thisMonth(): BoardPeriod | null {
		return parkNow ? { kind: 'month', season: parkNow.season, month: parkNow.month } : null;
	}

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
		const args = periodArgs ?? { season: null, month: null };
		try {
			if (boardKind === 'fastest') {
				fastest = await fetchGlobalSegmentLeaderboard(segmentId, {
					gender: genderFilter,
					ageBand: ageFilter,
					season: args.season,
					month: args.month,
				});
			} else {
				completions = await fetchGlobalSegmentCompletions(segmentId, args.season, 50, args.month);
			}
		} catch (e) {
			console.error('park course board failed', e);
			boardFailed = true;
		}
	}

	async function probeBoard(segmentId: string) {
		probeFailed = false;
		anyTimes = null;
		try {
			anyTimes = (await fetchGlobalSegmentCompletions(segmentId, null, 1)).length > 0;
		} catch (e) {
			console.error('park course board probe failed', e);
			probeFailed = true;
		}
	}

	$effect(() => {
		if (course && auth.loggedIn) void probeBoard(course.segment.id);
	});

	$effect(() => {
		const deps = [boardKind, periodArgs?.season, periodArgs?.month, genderFilter, ageFilter];
		void deps;
		if (course && auth.loggedIn && anyTimes && period) void refreshBoard(course.segment.id);
	});

	onMount(async () => {
		await auth.ready();
		await load();
	});

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
			guide: routeGuide ? { guide: routeGuide, checkedAt: course.route_guide_checked_at } : null,
		});
		const base = course.segment.name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_');
		downloadFile(gpx, `${base || 'course'}.gpx`, 'application/gpx+xml');
	}

	const shapeKey = $derived(courseShapeShown(course?.course_shape) ? labelKey(SHAPE_LABEL, course?.course_shape) : null);
	const laps = $derived(courseLapsChip(course?.laps));
	const routeGuide = $derived(parseRouteGuide(course?.route_guide));
	const difficultyKey = $derived(labelKey(DIFFICULTY_LABEL, course?.difficulty));
	const statusKey = $derived(labelKey(STATUS_LABEL, course?.status));
	const credit = $derived(courseCredit(course?.attribution, course?.geometry_source));

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const darkBasemap = $derived(basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY ?? '', prefersDark));
	const checkpointPins = $derived<MapMarkerPin[]>(
		(course?.checkpoints ?? []).map((c, i) => ({
			id: `checkpoint-${i}`,
			label: m('parks.checkpointShort', { n: i + 1 }),
			color: checkpointPinColour(darkBasemap),
			lat: c.lat,
			lng: c.lng,
		})),
	);
	const legendItems = $derived.by<ParkMapLegendItem[]>(() => {
		const items: ParkMapLegendItem[] = finishesAtStart(mapTrack)
			? [{ kind: 'startFinish', label: m('parks.legendStartFinish') }]
			: [
					{ kind: 'start', label: m('parks.legendStart') },
					{ kind: 'finish', label: m('parks.legendFinish') },
				];
		if (checkpointPins.length > 0) items.push({ kind: 'checkpoint', label: m('parks.legendCheckpoint') });
		const unitM = getUnit() === 'mi' ? 1609.344 : 1000;
		if (Number(course?.segment.distance_m) >= unitM) {
			items.push({
				kind: 'distance',
				label: getUnit() === 'mi' ? m('parks.legendMileMarker') : m('parks.legendKmMarker'),
			});
		}
		items.push({ kind: 'direction', label: m('parks.legendDirection') });
		return items;
	});
	// The profile and the map share an index, so the profile needs a height
	// on every point of the line or none at all.
	const elevations = $derived.by<number[] | null>(() => {
		if (mapTrack.length < 2) return null;
		const out: number[] = [];
		for (const p of mapTrack) {
			const e = Number(p.ele);
			if (p.ele == null || !Number.isFinite(e)) return null;
			out.push(e);
		}
		let lo = Infinity;
		let hi = -Infinity;
		for (const e of out) {
			if (e < lo) lo = e;
			if (e > hi) hi = e;
		}
		return hi > lo ? out : null;
	});
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
		<EmptyState icon="error" tone="danger" title={m('parks.loadFailed')} role="alert" data-testid="park-course-load-error">
			{#snippet actions()}
				<button type="button" class="btn btn-outline" onclick={load}>{m('parks.retry')}</button>
			{/snippet}
		</EmptyState>
	{:else if !park || !course}
		<EmptyState
			icon="route"
			title={m('parks.courseNotFoundTitle')}
			text={m('parks.courseNotFoundBody')}
			data-testid="park-course-not-found"
		/>
	{:else}
		{@const wayfinding = courseOffersWayfinding(course.status)}
		{@const canNavigate = !!course.route_id && wayfinding}
		{@const canDownload = mapTrack.length >= 2 && wayfinding}
		<header class="detail-header">
			<div class="title-row">
				<h1>{course.segment.name}</h1>
				<HelpLink route="/parks/[region]/[park]/[course]" />
			</div>
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
		</header>

		<div class="course-layout" class:with-map={mapTrack.length >= 2}>
			<div class="summary">
				<div class="key-stats" data-testid="park-course-stats">
					<div class="key-stat">
						<span class="key-stat-value">
							<span data-testid="park-course-distance">{fmtCourseDistance(course.segment.distance_m)}</span>
							{#if laps}<span class="chip" data-testid="park-course-laps">{m('parks.lapsChip', { n: laps })}</span>{/if}
						</span>
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
					<p class="description" data-testid="park-course-description">{course.segment.description}</p>
				{/if}
			</div>

			{#if canNavigate || canDownload}
				<div class="course-actions">
					{#if canNavigate}
						<a class="btn btn-primary action" href="/routes/{course.route_id}" data-testid="park-course-navigate">
							<span class="material-symbols" aria-hidden="true">directions_run</span>
							{m('parks.navigate')}
						</a>
					{/if}
					{#if canDownload}
						<button
							type="button"
							class="btn action"
							class:btn-primary={!canNavigate}
							class:btn-outline={canNavigate}
							onclick={downloadGpx}
							data-testid="park-course-gpx"
						>
							<span class="material-symbols" aria-hidden="true">download</span>
							{m('parks.downloadGpx')}
						</button>
					{/if}
				</div>
			{/if}

			{#if mapTrack.length >= 2}
				<section class="map-block" aria-label={m('parks.courseMapLabel')}>
					<div class="map-wrap">
						<RunMap track={mapTrack} markers={checkpointPins} hoverIdx={chartHoverIdx} />
					</div>
					<ParkMapLegend items={legendItems} testid="park-course-legend" />
					{#if credit}
						<p class="attribution" data-testid="park-course-attribution">
							{'text' in credit ? credit.text : m(credit.key)}
						</p>
					{/if}
					{#if elevations}
						<div class="elevation" data-testid="park-course-elevation">
							<SectionHeader title label={m('parks.elevationTitle')} />
							<ElevationProfile
								{elevations}
								totalGain={course.segment.elevation_m == null ? null : Number(course.segment.elevation_m)}
								totalDistance={Number(course.segment.distance_m)}
								onhover={(idx) => (chartHoverIdx = idx)}
							/>
						</div>
					{/if}
				</section>
			{/if}

			{#if routeGuide && wayfinding}
				<div class="guide-slot">
					<ParkCourseRouteGuide
						guide={routeGuide}
						checkedAt={course.route_guide_checked_at}
						testidPrefix="park-course"
					/>
				</div>
			{/if}

			<div class="notices-slot">
				<ParkCourseNotices
					distanceM={Number(course.segment.distance_m)}
					sharedUse={parseSharedUse(course.shared_use)}
					testidPrefix="park-course"
				/>
				{#if credit && mapTrack.length < 2}
					<p class="attribution" data-testid="park-course-attribution">
						{'text' in credit ? credit.text : m(credit.key)}
					</p>
				{/if}
				<!-- Kept with the notices, away from Navigate: it is for the rare
				     runner or land manager with a problem, not a next step. -->
				<p class="report-row">
					<button
						type="button"
						class="report-link"
						onclick={() => (showReport = true)}
						data-testid="park-course-report"
					>
						<span class="material-symbols" aria-hidden="true">flag</span>
						{m('parks.report.action')}
					</button>
				</p>
			</div>

			<section class="board" aria-labelledby="park-board-title">
				<SectionHeader title label={m('parks.boardTitle')} id="park-board-title" />
				{#if !auth.loggedIn}
					<p class="muted" data-testid="park-course-sign-in">
						{m('parks.signInForBoards')}
						<a href="/login">{m('parks.signIn')}</a>
					</p>
				{:else if probeFailed}
					<p class="muted board-error" role="alert" data-testid="park-board-error">
						{m('parks.boardFailed')}
						<button
							type="button"
							class="btn btn-outline btn-sm"
							onclick={() => course && void probeBoard(course.segment.id)}
						>
							{m('parks.retry')}
						</button>
					</p>
				{:else if anyTimes === null}
					<p class="muted">{m('segments.loading')}</p>
				{:else if !anyTimes}
					<EmptyState
						icon="emoji_events"
						headingLevel={3}
						title={m('parks.firstTimeTitle')}
						text={m('parks.firstTimeBody')}
						data-testid="park-board-invite"
					/>
				{:else}
					<div class="board-head">
						<div class="segmented" role="group" aria-label={m('parks.boardKindLabel')}>
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
						<div class="segmented" role="group" aria-label={m('parks.boardSeasonLabel')}>
							<button
								type="button"
								class:active={period?.kind === 'month'}
								aria-pressed={period?.kind === 'month'}
								onclick={() => {
									const next = thisMonth();
									if (next) setPeriod(next);
								}}
								data-testid="park-period-this-month"
							>
								{m('parks.periodThisMonth')}
							</button>
							<button
								type="button"
								class:active={period?.kind === 'year'}
								aria-pressed={period?.kind === 'year'}
								onclick={() => setPeriod({ kind: 'year', season: park!.park_season })}
								data-testid="park-season-this-year"
							>
								{m('parks.seasonThisYear', { year: park.park_season })}
							</button>
							<button
								type="button"
								class:active={period?.kind === 'all'}
								aria-pressed={period?.kind === 'all'}
								onclick={() => setPeriod({ kind: 'all' })}
								data-testid="park-season-all-time"
							>
								{m('parks.seasonAllTime')}
							</button>
						</div>
						<button
							type="button"
							class="btn btn-outline btn-sm h2h-open"
							onclick={() => (showHeadToHead = true)}
							data-testid="park-board-compare"
						>
							<span class="material-symbols" aria-hidden="true">group</span>
							{m('headToHead.compare')}
						</button>
					</div>

					{#if period?.kind === 'month'}
						<div class="month-nav" data-testid="park-period-month-nav">
							<button
								type="button"
								class="month-step"
								aria-label={m('parks.periodPrevMonth')}
								disabled={!prevMonth}
								onclick={() => prevMonth && setPeriod(prevMonth)}
								data-testid="park-period-prev"
							>
								<span class="material-symbols" aria-hidden="true">chevron_left</span>
							</button>
							<span class="month-label" aria-live="polite" data-testid="park-period-month">
								{monthYearLabel(period.season, period.month, currentLocale())}
							</span>
							<button
								type="button"
								class="month-step"
								aria-label={m('parks.periodNextMonth')}
								disabled={!nextMonth}
								onclick={() => nextMonth && setPeriod(nextMonth)}
								data-testid="park-period-next"
							>
								<span class="material-symbols" aria-hidden="true">chevron_right</span>
							</button>
						</div>
					{/if}

					{#if boardKind === 'fastest'}
						<div class="tier-filters" data-testid="park-board-filters">
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
									{#each SEGMENT_AGE_BANDS as band (band)}
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
		</div>
		<ParkCourseReportDialog
			open={showReport}
			courseId={course.id}
			courseName={course.segment.name}
			onclose={() => (showReport = false)}
		/>
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
	.detail-header {
		margin-bottom: var(--space-lg);
	}
	.title-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
	}
	.title-row h1 {
		margin: 0;
	}
	.meta {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		margin: var(--space-xs) 0 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.meta .material-symbols {
		font-size: 1rem;
	}
	.report-row {
		margin: var(--space-sm) 0 0;
	}
	.report-link {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		min-height: 1.5rem;
		padding: 0.2rem 0;
		border: none;
		background: none;
		color: var(--color-text-secondary);
		font: inherit;
		font-size: 0.85rem;
		text-decoration: underline;
		cursor: pointer;
	}
	.report-link:hover {
		color: var(--color-text);
	}
	.report-link:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.report-link .material-symbols {
		font-size: 1rem;
	}
	.closed-banner {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		max-width: var(--page-measure);
		margin: var(--space-md) 0 0;
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-warning-light);
		color: var(--color-warning-text);
	}
	/* One column on a phone, in reading order. From 72rem the map and the board
	   take the wide column and the summary, actions, route guide and notices the narrow
	   one, so every block in a column shares that column's width. */
	.course-layout {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-lg);
		align-items: start;
	}
	@media (min-width: 72rem) {
		.course-layout.with-map {
			grid-template-columns: minmax(0, 3fr) minmax(18rem, 2fr);
			grid-template-rows: auto auto auto auto 1fr;
			column-gap: var(--space-xl);
		}
		.with-map .map-block {
			grid-column: 1;
			grid-row: 1 / span 3;
		}
		.with-map .summary {
			grid-column: 2;
			grid-row: 1;
		}
		.with-map .course-actions {
			grid-column: 2;
			grid-row: 2;
		}
		.with-map .guide-slot {
			grid-column: 2;
			grid-row: 3;
		}
		.with-map .notices-slot {
			grid-column: 2;
			grid-row: 4 / span 2;
		}
		.with-map .board {
			grid-column: 1;
			grid-row: 4 / span 2;
		}
		.with-map .map-wrap {
			height: 26rem;
		}
	}
	.key-stats {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(8rem, 100%), 1fr));
		gap: 1px;
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
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-xs);
		font-size: 1.05rem;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.key-stat-label {
		font-size: var(--font-size-section-label);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-tertiary);
	}
	.chip {
		padding: 0.05rem 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--chip-bg);
		color: var(--chip-fg);
		font-size: 0.75rem;
		font-weight: 600;
	}
	.status-line,
	.description {
		margin: var(--space-md) 0 0;
		max-width: var(--page-measure);
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.course-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.action {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
	.map-wrap {
		height: 20rem;
		border-radius: var(--radius-md);
		overflow: hidden;
	}
	.elevation {
		margin-top: var(--space-lg);
	}
	.attribution {
		margin: var(--space-sm) 0 0;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
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
	.month-nav {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		margin-bottom: var(--space-sm);
	}
	.month-step {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 2.75rem;
		min-height: 2.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		color: var(--color-text);
		cursor: pointer;
	}
	.month-step:disabled {
		color: var(--color-text-tertiary);
		cursor: default;
	}
	.month-step:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.month-label {
		min-width: 0;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
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
		font-size: var(--font-size-section-label);
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
	}
	ol li {
		display: grid;
		grid-template-columns: 2.2rem minmax(0, 1fr) auto;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-xs);
		border-bottom: 1px solid var(--color-border);
	}
	ol li.viewer {
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
