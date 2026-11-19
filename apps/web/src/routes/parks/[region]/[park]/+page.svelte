<script lang="ts">
	import SectionHeader from '#lib/components/SectionHeader.svelte';
	import ListCard from '#lib/components/ListCard.svelte';
	import { onMount, tick } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { formatDistance, formatElevation } from '#lib/format/units.svelte.ts';
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
	import { courseEnds, regionCodeFromSlug, regionName } from '#lib/parks/park_courses.ts';
	import { courseSearch, selectedCourseSlug, startSentence } from '#lib/parks/course_preview.ts';
	import { mapsStartUrl } from '#lib/routes/course_drive.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';
	import { parseRouteGuide } from '#lib/parks/route_guide.ts';
	import { referrerBack } from '#lib/util/referrer_back.svelte.ts';
	import { BACK_PLACE_KEY } from '#lib/util/back_target.ts';
	import {
		AGENCY_LABEL,
		DIFFICULTY_LABEL,
		SHAPE_LABEL,
		STATUS_LABEL,
		labelKey,
	} from '#lib/parks/park_labels.ts';
	import {
		courseDisplayNames,
		courseLapsChip,
		courseShapeShown,
		sortParkCourses,
	} from '#lib/parks/park_course_distance.ts';
	import { fmtCourseDistance } from '#lib/parks/course_distance_format.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import TrackPreview from '#lib/components/TrackPreview.svelte';
	import ParkCoursesMap from '#lib/components/parks/ParkCoursesMap.svelte';
	import ParkMapLegend, { type ParkMapLegendItem } from '#lib/components/parks/ParkMapLegend.svelte';
	import type { TrackPoint } from '#lib/types.ts';

	let { data } = $props();

	// With no in-app history a park sits under Races & courses, the place the
	// sidebar names; the parks index is one step further from the nav.
	const back = referrerBack({ href: '/races?show=courses', place: 'races' });

	let park = $state<Park | null>(null);
	let courses = $state<ParkCourse[]>([]);
	let loading = $state(true);
	let loadFailed = $state(false);
	// The season's records are an auxiliary read on their own: when it fails
	// the courses still list, without records. Signed out, there is none.
	let records = $state<Map<string, ParkCourseRecord>>(new Map());
	let recordsLoaded = $state(false);
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
	// Each card's name, without the distance and laps it states where the
	// shorter name stays unique in the park.
	const names = $derived.by(() => {
		const shown = courseDisplayNames(
			sorted.map((c) => c.segment.name),
			park?.name ?? '',
		);
		return new Map(sorted.map((c, i) => [c.id, shown[i]]));
	});
	const hasLines = $derived(mapCourses.some((c) => c.points.length >= 2));
	// One quiet line for the park rather than "no time yet" on every card.
	const noTimesYet = $derived(
		auth.loggedIn && recordsLoaded && !recordsFailed && courses.length > 0 && !courses.some((c) => records.has(c.id)),
	);

	// The previewed course lives in `?course=`, written shallow so the list,
	// its scroll and the back target stay put; back from the course page,
	// a reload or a shared link brings the preview back.
	const shownUrl = () => page.shallow?.url ?? page.url;
	const selectedSlug = $derived(selectedCourseSlug(shownUrl().search, courses.map((c) => c.slug)));
	const selected = $derived(sorted.find((c) => c.slug === selectedSlug) ?? null);
	const selectedEnds = $derived.by(() => {
		if (!selected) return null;
		return courseEnds({
			line: pointsOf(selected),
			startGate: { lat: selected.segment.start_gate_lat, lng: selected.segment.start_gate_lng },
			endGate: { lat: selected.segment.end_gate_lat, lng: selected.segment.end_gate_lng },
			shape: selected.course_shape,
		});
	});
	const selectedStart = $derived(
		selected
			? startSentence(parseRouteGuide(selected.route_guide), {
					message: (key, params) => m(`parks.guide.${key}`, params),
					distance: formatDistance,
					short: formatElevation,
				})
			: null,
	);
	const legendItems = $derived.by<ParkMapLegendItem[]>(() => {
		const line: ParkMapLegendItem = { kind: 'line', label: m('parks.legendCourse') };
		if (!selected) return [line, { kind: 'trailhead', label: m('parks.legendStart') }];
		const items: ParkMapLegendItem[] = [line, { kind: 'focusedLine', label: m('parks.legendHighlighted') }];
		if (selectedEnds && !selectedEnds.finish) return [...items, { kind: 'startFinish', label: m('parks.legendStartFinish') }];
		return [
			...items,
			{ kind: 'start', label: m('parks.legendStart') },
			{ kind: 'finish', label: m('parks.legendFinish') },
		];
	});

	let previewHeading = $state<HTMLElement | null>(null);
	// The overview's height while no course is previewed: the slot keeps it
	// when the preview lifts the overview into a sheet on a narrow screen.
	let overviewHeight = $state(0);
	// Whether the map is drawn; its key shows only under a drawn map.
	let mapShown = $state(hasAcceptedConsent());
	let restingHeight = $state(0);
	$effect(() => {
		if (!selected) restingHeight = overviewHeight;
	});

	function courseHref(slug: string): string {
		return `/parks/${data.region}/${data.park}/${slug}`;
	}

	function focusCard(slug: string) {
		document.querySelector<HTMLElement>(`[data-course-slug="${CSS.escape(slug)}"] .lc-tap`)?.focus();
	}

	// Opening a preview from none adds one history entry, so the browser's or
	// the phone's back closes it; picking another course replaces that entry.
	// `stacked` tells the back link to step over it.
	async function select(slug: string) {
		const opening = !selectedSlug;
		const url = shownUrl();
		await goto(`${url.pathname}${courseSearch(url.search, slug)}`, {
			shallow: true,
			replace: !opening,
			persistState: true,
			state: { ...page.state, stacked: opening ? 1 : (page.state.stacked ?? 0) },
		});
		await tick();
		previewHeading?.focus({ preventScroll: true });
	}

	async function closePreview() {
		const from = selectedSlug;
		if (!from) return;
		if (page.state.stacked) {
			await new Promise<void>((done) => {
				addEventListener('popstate', () => done(), { once: true });
				history.back();
			});
		} else {
			const url = shownUrl();
			await goto(`${url.pathname}${courseSearch(url.search, null)}`, {
				shallow: true,
				replace: true,
				persistState: true,
				state: page.state,
			});
		}
		await tick();
		focusCard(from);
	}

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape' && selected && !e.defaultPrevented) {
			e.preventDefault();
			void closePreview();
		}
	}

	async function loadRecords() {
		recordsFailed = false;
		if (!auth.loggedIn) return;
		try {
			records = await fetchParkCourseRecords();
			recordsLoaded = true;
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
<svelte:window onkeydown={onKeydown} />

<div class="page">
	<a href={back.href} onclick={back.handle} class="back-link" data-testid="park-back">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m(BACK_PLACE_KEY[back.place])}
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
			<!-- The heading and the hint span both columns, so the first card and
			     the map start on one line. -->
			<div class="courses-head">
				<SectionHeader title label={m('parks.coursesTitle')} id="park-courses-title">
					{#snippet badge()}
						<span class="count">{m('parks.courseCount', { n: courses.length })}</span>
					{/snippet}
				</SectionHeader>
				<p class="list-note" id="park-preview-hint">{m('parks.previewHint')}</p>
			</div>
			<div class="park-layout" class:with-map={hasLines || selected} class:with-preview={selected}>
				<section class="courses" aria-labelledby="park-courses-title">
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
							{@const name = names.get(course.id) ?? course.segment.name}
							<li
								data-course-slug={course.slug}
								onmouseenter={() => (highlightId = course.id)}
								onmouseleave={() => (highlightId = null)}
								onfocusin={() => (highlightId = course.id)}
								onfocusout={() => (highlightId = null)}
							>
								<ListCard
									onclick={() => void select(course.slug)}
									selected={selected?.id === course.id}
									title={name}
									dense
									class="course-card{course.status === 'closed' ? ' closed' : ''}"
									testid="park-course-card"
								>
									{#snippet leading()}
										<span class="thumb" aria-hidden="true">
											{#if points.length >= 2}<TrackPreview {points} aspect={1.4} />{/if}
										</span>
									{/snippet}
									{#snippet meta()}
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
											{#if course.status !== 'open' && statusKey}
												<span class="status-pill" class:closed={course.status === 'closed'}>{m(statusKey)}</span>
											{/if}
										</span>
										{#if record && auth.loggedIn && !recordsFailed}
											<span class="course-record" data-testid="park-course-record">
												<span class="material-symbols" aria-hidden="true">emoji_events</span>
												{record.displayName
													? m('races.anyTimeFastestBy', { year: record.season, time: formatDuration(record.timeSeconds), name: record.displayName })
													: m('races.anyTimeFastest', { year: record.season, time: formatDuration(record.timeSeconds) })}
											</span>
										{/if}
										{#if ranThisMonth > 0}
											<span class="course-record" data-testid="park-course-month-runners">
												<span class="material-symbols month-icon" aria-hidden="true">calendar_month</span>
												{m('parks.monthRunners', { n: ranThisMonth })}
											</span>
										{/if}
									{/snippet}
									{#snippet trailing()}
										<a
											class="course-open"
											href={courseHref(course.slug)}
											aria-label={m('parks.openCourseNamed', { course: name })}
											data-testid="park-course-open"
										>
											<span class="course-open-text">{m('parks.cardOpen')}</span>
											<span class="material-symbols" aria-hidden="true">arrow_forward</span>
										</a>
									{/snippet}
								</ListCard>
							</li>
						{/each}
					</ul>
					<!-- Below the cards, so a line that arrives late never moves a card
					     under a finger about to tap it. -->
					{#if noTimesYet}
						<p class="list-note">
							<span class="material-symbols" aria-hidden="true">emoji_events</span>
							<span data-testid="park-no-times-yet">{m('parks.noTimesYet')}</span>
						</p>
					{/if}
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
				</section>

				{#if hasLines || selected}
					<!-- Below 64rem the preview is a sheet fixed to the bottom of the
					     screen; the slot keeps the map's place in the page so the list
					     does not jump when it lifts out. -->
					<div class="overview-slot" style:--resting-height="{restingHeight}px">
					<section class="overview" aria-label={m('parks.overviewMapLabel', { park: park.name })} bind:offsetHeight={overviewHeight}>
						{#if hasLines}
							<div class="map-frame">
								<ParkCoursesMap
									courses={mapCourses}
									{highlightId}
									selectedId={selected?.id ?? null}
									{selectedEnds}
									label={m('parks.overviewMapLabel', { park: park.name })}
									twoFingerHint={m('parks.mapTwoFingers')}
									bind:consented={mapShown}
									testid="park-overview-map"
								/>
							</div>
							{#if mapShown}
								<ParkMapLegend testid="park-map-legend" items={legendItems} />
							{/if}
						{/if}
						{#if selected}
							{@const shapeKey = labelKey(SHAPE_LABEL, selected.course_shape)}
							{@const laps = courseLapsChip(selected.laps)}
							{@const gain = Number(selected.segment.elevation_m)}
							{@const name = names.get(selected.id) ?? selected.segment.name}
							{@const difficultyKey = labelKey(DIFFICULTY_LABEL, selected.difficulty)}
							{@const statusKey = selected.status === 'open' ? null : labelKey(STATUS_LABEL, selected.status)}
							{@const closed = selected.status === 'closed'}
							{@const directionsTo = closed ? null : selectedEnds}
							<section class="preview card-elevated" aria-labelledby="park-preview-title" data-testid="park-course-preview">
								<div class="preview-head">
									<h2 id="park-preview-title" class="preview-title" tabindex="-1" bind:this={previewHeading}>{name}</h2>
									{#if statusKey}
										<span class="status-pill" class:closed data-testid="park-course-preview-status">{m(statusKey)}</span>
									{/if}
									<button
										type="button"
										class="preview-close"
										aria-label={m('parks.previewClose')}
										onclick={() => void closePreview()}
										data-testid="park-course-preview-close"
									>
										<span class="material-symbols" aria-hidden="true">close</span>
									</button>
								</div>
								{#if closed}
									<p class="preview-closed" data-testid="park-course-preview-closed">
										{selected.status_note?.trim() || m('parks.closedBanner')}
									</p>
								{/if}
								<dl class="preview-facts">
									<div>
										<dt>{m('parks.statDistance')}</dt>
										<dd data-testid="park-course-preview-distance">{fmtCourseDistance(selected.segment.distance_m)}</dd>
									</div>
									{#if Number.isFinite(gain) && gain > 0}
										<div>
											<dt>{m('parks.statElevation')}</dt>
											<dd>{formatElevation(gain)}</dd>
										</div>
									{/if}
									{#if laps}
										<div>
											<dt>{m('parks.statLaps')}</dt>
											<dd data-testid="park-course-preview-laps">
												{m('parks.lapsOf', { n: laps, distance: fmtCourseDistance(Number(selected.segment.distance_m) / laps) })}
											</dd>
										</div>
									{/if}
									{#if shapeKey}
										<div>
											<dt>{m('parks.statShape')}</dt>
											<dd data-testid="park-course-preview-shape">{m(shapeKey)}</dd>
										</div>
									{/if}
									{#if difficultyKey}
										<div>
											<dt>{m('parks.statDifficulty')}</dt>
											<dd>{m(difficultyKey)}</dd>
										</div>
									{/if}
								</dl>
								{#if selectedStart && !closed}
									<p class="preview-start">
										<span class="material-symbols" aria-hidden="true">place</span>
										<span lang={selectedStart.lang ?? undefined} data-testid="park-course-preview-start">{selectedStart.text}</span>
									</p>
								{/if}
								<div class="preview-actions">
									<a class="btn btn-primary preview-open" href={courseHref(selected.slug)} data-testid="park-course-preview-open">
										{m('parks.openCourse')}
										<span class="material-symbols" aria-hidden="true">arrow_forward</span>
									</a>
									{#if directionsTo}
										<a
											class="btn btn-outline preview-directions"
											href={mapsStartUrl('google', directionsTo.start)}
											target="_blank"
											rel="noopener noreferrer"
											data-testid="park-course-preview-directions"
										>
											<span class="material-symbols" aria-hidden="true">directions</span>
											{m(directionsTo.finish ? 'parks.endsDirectionsStart' : 'parks.endsDirectionsStartFinish')}
										</a>
									{/if}
								</div>
							</section>
						{/if}
					</section>
					</div>
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
	/* The dot ends an item rather than starting the next, so a wrapped line
	   never opens on one. */
	.meta li:not(:last-child)::after {
		content: '·';
		margin-inline-start: var(--space-sm);
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
	.overview-slot {
		order: -1;
	}
	/* Short on a phone, so the first course shows without a scroll. */
	.map-frame {
		height: 10rem;
	}
	@media (min-width: 40rem) {
		.map-frame {
			height: 16rem;
		}
	}
	@media (min-width: 64rem) {
		.park-layout.with-map {
			grid-template-columns: minmax(0, 5fr) minmax(0, 6fr);
			align-items: start;
		}
		.overview-slot {
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
	/* Every card the height of the tallest, so the list reads as one grid:
	   the name holds to two lines (the whole name stays in the button's
	   accessible name), and the card's row fills it so Open sits centred. */
	.course-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-auto-rows: 1fr;
		gap: var(--space-sm);
	}
	.course-list > li {
		min-width: 0;
	}
	.course-list :global(.course-card .lc-top) {
		box-sizing: border-box;
		height: 100%;
	}
	.course-list :global(.course-card .list-card-title) {
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		overflow: hidden;
	}
	.list-note {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		margin: 0 0 var(--space-sm);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.course-list ~ .list-note,
	.course-list ~ .records-failed {
		margin: var(--space-sm) 0 0;
	}
	.list-note .material-symbols {
		flex-shrink: 0;
		font-size: 1rem;
		color: var(--color-crown);
	}
	.course-list :global(.course-card.closed .thumb),
	.course-list :global(.course-card.closed .list-card-title) {
		opacity: 0.6;
	}
	.course-open {
		display: inline-flex;
		align-items: center;
		gap: 0.15rem;
		min-height: var(--tap-target-min);
		padding: 0 var(--space-sm);
		border-radius: var(--radius-pill);
		color: var(--color-primary);
		font-weight: 600;
		font-size: 0.875rem;
		text-decoration: none;
		white-space: nowrap;
	}
	.course-open:hover {
		background: var(--color-primary-light);
	}
	.course-open:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.course-open .material-symbols {
		font-size: 1.1rem;
	}
	.thumb {
		display: block;
		width: 4.5rem;
		height: 3.2rem;
		border-radius: var(--radius-sm);
		background: var(--color-fill-subtle);
		overflow: hidden;
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
		display: flex;
		margin-top: var(--space-2xs);
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
	/* On the narrowest phones the thumbnail gives way, so the name and the
	   Open link keep their room; the preview draws the line. */
	@media (max-width: 30rem) {
		.course-list :global(.course-card .lc-leading) {
			display: none;
		}
	}
	.park-layout.with-preview .map-frame {
		height: 14rem;
	}
	@media (min-width: 64rem) {
		.park-layout.with-preview .map-frame {
			height: min(24rem, 46vh);
		}
	}
	/* Below 64rem the preview is a sheet over the bottom of the screen: the
	   list stays where it was, a tap on another card swaps the course, and the
	   slot holds the map's place so nothing jumps. */
	@media (max-width: 63.99rem) {
		.park-layout.with-preview .overview-slot {
			min-height: var(--resting-height);
		}
		.park-layout.with-preview .overview {
			position: fixed;
			inset: auto 0 0 0;
			z-index: var(--z-modal);
			max-height: 85dvh;
			overflow-y: auto;
			padding: var(--space-md) var(--space-md) calc(var(--space-md) + env(safe-area-inset-bottom));
			background: var(--color-surface);
			border-top: 1px solid var(--color-border);
			border-radius: var(--radius-lg) var(--radius-lg) 0 0;
			box-shadow: var(--shadow-lg);
		}
		.park-layout.with-preview .preview {
			margin-top: var(--space-sm);
			padding: 0;
			border: 0;
			box-shadow: none;
			background: none;
		}
	}
	.preview-closed {
		margin: 0;
		color: var(--color-danger-text);
		line-height: 1.45;
	}
	.preview-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.preview-directions {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.preview {
		margin-top: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.preview-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.preview-title {
		margin: 0;
		font-size: var(--font-size-section-title);
		font-weight: 700;
		line-height: 1.3;
		align-self: center;
	}
	.preview-title:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.preview-close {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		width: var(--tap-target-min);
		height: var(--tap-target-min);
		margin: calc(var(--space-sm) * -1) calc(var(--space-sm) * -1) 0 0;
		border: 0;
		border-radius: var(--radius-pill);
		background: none;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.preview-close:hover {
		background: var(--color-fill-subtle);
	}
	.preview-close:focus-visible {
		outline: 2px solid var(--color-primary);
	}
	.preview-facts {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm) var(--space-lg);
		margin: 0;
	}
	.preview-facts dt {
		font-size: 0.75rem;
		color: var(--color-text-secondary);
	}
	.preview-facts dd {
		margin: 0;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.preview-start {
		display: flex;
		align-items: flex-start;
		gap: var(--space-xs);
		margin: 0;
		color: var(--color-text);
		line-height: 1.45;
	}
	.preview-start .material-symbols {
		flex-shrink: 0;
		font-size: 1.1rem;
		color: var(--color-text-secondary);
		margin-top: 0.1rem;
	}
	.preview-open {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	@media (max-width: 40rem) {
		.preview-open,
		.preview-directions {
			flex: 1 1 100%;
			justify-content: center;
		}
	}
</style>
