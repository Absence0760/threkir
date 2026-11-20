<script lang="ts">
	import SectionHeader from '#lib/components/SectionHeader.svelte';
	import HelpLink from '#lib/components/help/HelpLink.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import { onMount, tick } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import {
		fetchAllParkCourses,
		fetchParkCourseRecords,
		fetchRaceCourseReviewQueue,
		searchRaceListings,
		type ParkCourseRecord,
		type ParkCourseWithPark,
		type RaceListingResult,
		type RaceListingFilters,
		type RaceDistanceBand
	} from '#lib/core/data.ts';
	import { raceImportLegFor } from '#lib/integrations/race_import_providers.ts';
	import { addDays, formatISO } from '#lib/training/training.ts';
	import { probeRaceLeg } from '#lib/integrations/race_import_probe.svelte.ts';
	import RunSurfaceTabs from '#lib/components/RunSurfaceTabs.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import RaceCalendarCard from '#lib/components/RaceCalendarCard.svelte';
	import RaceImportDialog from '#lib/components/RaceImportDialog.svelte';
	import RaceListingEditor from '#lib/components/RaceListingEditor.svelte';
	import Modal from '#lib/components/Modal.svelte';
	import FilterBar, { type ActiveFilter, type FilterChip } from '#lib/components/FilterBar.svelte';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import ListCard from '#lib/components/ListCard.svelte';
	import { formatDuration } from '#lib/format/time.ts';
	import { fmtCompactDistance } from '#lib/format/units.svelte.ts';
	import { anyTimeSearchHits, orderAnyTimeCourses, orderAnyTimeParks, parkSearchTerms } from '#lib/parks/any_time_courses.ts';
	import { anyTimeCourseLimit, parseRacesShow, racesShowSearch, type RacesShow } from '#lib/races/races_show.ts';
	import { regionName, regionSlug } from '#lib/parks/park_courses.ts';
	import ParkCard from '#lib/components/parks/ParkCard.svelte';
	import { SHAPE_LABEL, STATUS_LABEL, labelKey } from '#lib/parks/park_labels.ts';
	import { courseLapsChip, courseShapeShown } from '#lib/parks/park_course_distance.ts';
	import { fmtCourseDistance } from '#lib/parks/course_distance_format.ts';
	import {
		PLACE_LOOKUP_MIN_CHARS,
		coursePlaceBias,
		placeLabel,
		placesNearCourses,
	} from '#lib/parks/course_place_search.ts';
	import type { PlaceSearchResult } from '#lib/routes/geocoding_math.ts';

	const SHOWS: { v: RacesShow; k: MessageKey }[] = [
		{ v: 'all', k: 'races.showAll' },
		{ v: 'races', k: 'races.showRaces' },
		{ v: 'courses', k: 'races.showCourses' }
	];
	let show = $state<RacesShow>('all');

	// The choice is a shallow navigation, so the address it wrote is
	// `page.shallow.url`, which back from a course page restores too; a
	// `?show=` link followed while /races is open lands in `page.url`.
	const shownUrl = () => page.shallow?.url ?? page.url;
	$effect(() => {
		show = parseRacesShow(shownUrl().searchParams.get('show'));
	});

	function setShow(next: RacesShow) {
		show = next;
		// Shallow: the lists, the filters and the scroll stay as they are.
		const url = shownUrl();
		void goto(`${url.pathname}${racesShowSearch(url.search, next)}`, {
			replace: true,
			shallow: true
		});
	}

	let query = $state('');
	// `query` once typing pauses, which is what filters the park courses. Every
	// course is already loaded, so they are matched on the list rather than
	// asked of the server.
	let courseQuery = $state('');
	let courseQueryTimer: ReturnType<typeof setTimeout> | undefined;
	$effect(() => {
		const next = query;
		clearTimeout(courseQueryTimer);
		courseQueryTimer = setTimeout(() => (courseQuery = next), 250);
		return () => clearTimeout(courseQueryTimer);
	});
	const courseTerms = $derived(parkSearchTerms(courseQuery));

	function clearSearch() {
		clearTimeout(courseQueryTimer);
		query = '';
		courseQuery = '';
	}

	let distance = $state<'' | RaceDistanceBand>('');
	let when = $state<'upcoming' | 'recent'>('upcoming');
	const RECENT_WINDOW_DAYS = 30;

	let nearPlace = $state('');
	let center = $state<{ lng: number; lat: number } | null>(null);
	let radiusM = $state<number | undefined>(undefined);
	let nearLabel = $state('');
	let geoError = $state('');

	let results = $state<RaceListingResult[]>([]);
	let loading = $state(true);
	let error = $state(false);

	let showEditor = $state(false);

	let importing = $state<RaceListingResult | null>(null);

	let filtersOpen = $state(false);

	const DISTANCES: { v: '' | RaceDistanceBand; k: MessageKey }[] = [
		{ v: '', k: 'races.distanceAny' },
		{ v: '5k', k: 'races.distance5k' },
		{ v: '10k', k: 'races.distance10k' },
		{ v: 'half', k: 'races.distanceHalf' },
		{ v: 'marathon', k: 'races.distanceMarathon' },
		{ v: 'ultra', k: 'races.distanceUltra' }
	];

	// The search stays on the toolbar, so only what is tucked behind Filters
	// counts towards its badge.
	let activeCount = $derived((distance ? 1 : 0) + (when === 'recent' ? 1 : 0) + (nearLabel ? 1 : 0));
	let distanceLabel = $derived.by(() => {
		const band = DISTANCES.find((d) => d.v === distance && d.v !== '');
		return band ? m(band.k) : '';
	});

	const showChips = $derived<FilterChip[]>(
		SHOWS.map((s) => ({
			key: s.v,
			label: m(s.k),
			pressed: show === s.v,
			onclick: () => setShow(s.v),
			testid: `races-show-${s.v}`,
		})),
	);

	// The race filters that are on, as removable chips on the bar's line. The
	// Courses view hides the race calendar, so it hides them with it.
	const activeFilters = $derived.by<ActiveFilter[]>(() => {
		if (show === 'courses') return [];
		const out: ActiveFilter[] = [];
		if (when === 'recent') {
			out.push({ key: 'when', label: m('races.whenRecent'), onRemove: () => (when = 'upcoming'), testid: 'races-chip-when' });
		}
		if (distanceLabel) {
			out.push({ key: 'distance', label: distanceLabel, onRemove: () => (distance = ''), testid: 'races-chip-distance' });
		}
		if (nearLabel) {
			out.push({ key: 'near', label: `${m('discover.nearLabel')}: ${nearLabel}`, onRemove: clearNear, testid: 'races-near-clear' });
		}
		return out;
	});

	async function run() {
		loading = true;
		error = false;
		const f: RaceListingFilters = {};
		if (query.trim()) f.query = query.trim();
		if (distance) f.distance = distance;
		if (when === 'recent') {
			const today = new Date();
			f.from = formatISO(addDays(today, -RECENT_WINDOW_DAYS));
			f.to = formatISO(addDays(today, -1));
			f.newestFirst = true;
		}
		if (center) {
			f.center = center;
			if (radiusM != null) f.radiusM = radiusM;
		}
		try {
			results = await searchRaceListings(f);
			probeLegsIn(results);
		} catch {
			error = true;
		} finally {
			loading = false;
		}
	}

	/// Probe only the legs the listings on screen can actually reach, once each,
	/// so the import dialog opens already knowing what it can offer.
	function probeLegsIn(rows: RaceListingResult[]) {
		for (const r of rows) {
			const leg = raceImportLegFor(r.provider);
			if (leg) void probeRaceLeg(leg);
		}
	}

	let timer: ReturnType<typeof setTimeout> | undefined;
	$effect(() => {
		query;
		distance;
		when;
		center;
		radiusM;
		clearTimeout(timer);
		if (show === 'courses') return;
		timer = setTimeout(run, 250);
		return () => clearTimeout(timer);
	});

	// "Run any time": park courses, loaded on their own so a failed race
	// search never hides them and a failed course read never hides the races.
	// The season's records are a second, auxiliary read: when it fails the
	// courses still list, without records.
	let courses = $state<ParkCourseWithPark[]>([]);
	let coursesLoading = $state(true);
	let coursesFailed = $state(false);
	let records = $state<Map<string, ParkCourseRecord>>(new Map());
	let recordsFailed = $state(false);

	// The section lists parks, each opening its page of courses; a course is
	// listed on its own only when a search finds it by its own name
	// (decisions § 2550).
	const coursesByPark = $derived.by(() => {
		const byPark = new Map<string, ParkCourseWithPark[]>();
		for (const c of courses) {
			const list = byPark.get(c.park_id);
			if (list) list.push(c);
			else byPark.set(c.park_id, [c]);
		}
		return byPark;
	});

	const anyTimeHits = $derived(
		anyTimeSearchHits(
			courses,
			(c) => ({ parkId: c.park_id, courseName: c.segment.name, parkName: c.park.name, regionCode: c.park.region_code }),
			courseTerms,
		),
	);

	function courseStart(c: ParkCourseWithPark): { lat: number; lng: number } | null {
		const first = c.segment.waypoints[0];
		return first ? { lat: Number(first.lat), lng: Number(first.lng) } : null;
	}

	const allParks = $derived(
		orderAnyTimeParks(
			anyTimeHits.parkIds.map((id) => coursesByPark.get(id) ?? []).filter((list) => list.length > 0),
			(list) => {
				const park = list[0].park;
				return {
					regionCode: park.region_code,
					parkName: park.name,
					slug: park.slug,
					allClosed: list.every((c) => c.status === 'closed'),
					starts: list.map(courseStart).filter((p) => p !== null),
					location:
						park.centroid_lat !== null && park.centroid_lng !== null
							? { lat: park.centroid_lat, lng: park.centroid_lng }
							: null,
				};
			},
			center,
		),
	);

	const allHitCourses = $derived(
		orderAnyTimeCourses(
			anyTimeHits.courses,
			(c) => ({
				regionCode: c.park.region_code,
				parkName: c.park.name,
				courseName: c.segment.name,
				slug: c.slug,
				distanceM: Number(c.segment.distance_m),
				status: c.status,
				start: courseStart(c),
			}),
			center,
		),
	);

	const anyTimeLimit = $derived(anyTimeCourseLimit(show) ?? undefined);
	const anyTimeParks = $derived(allParks.slice(0, anyTimeLimit));
	const orderedCourses = $derived(allHitCourses.slice(0, anyTimeLimit));
	const anyTimeCount = $derived(anyTimeParks.length + orderedCourses.length);

	// The way to the full index, only when the list above is cut short; the
	// Courses view lists everything and has none (issue #1374). It counts the
	// courses the cut list stands for.
	const anyTimeTruncated = $derived(
		allParks.length > anyTimeParks.length || allHitCourses.length > orderedCourses.length,
	);
	const anyTimeCourseTotal = $derived(
		allParks.reduce((n, p) => n + p.park.length, 0) + allHitCourses.length,
	);
	const seeAllHref = $derived(courseQuery.trim() ? `/parks?q=${encodeURIComponent(courseQuery.trim())}` : '/parks');

	async function loadCourses() {
		coursesLoading = true;
		coursesFailed = false;
		try {
			courses = await fetchAllParkCourses();
		} catch (e) {
			console.error('park courses read failed', e);
			coursesFailed = true;
		} finally {
			coursesLoading = false;
		}
	}

	async function loadRecords() {
		recordsFailed = false;
		try {
			records = await fetchParkCourseRecords();
		} catch (e) {
			console.error('park course records read failed', e);
			recordsFailed = true;
		}
	}

	onMount(() => {
		void loadCourses();
		void loadRecords();
	});

	// The Courses view's one search matches parks and courses by name from the
	// list above, and looks places up beside it. A place is only ever offered,
	// as a "Courses near …" row the runner taps; typing never sorts by one on
	// its own (decisions § 2591).
	type PlaceLookup =
		| { status: 'idle' }
		| { status: 'loading' }
		| { status: 'ok'; places: PlaceSearchResult[] }
		| { status: 'unavailable' };
	let placeLookup = $state<PlaceLookup>({ status: 'idle' });

	// Where the catalogue is: every course start, and each park's own point.
	const coursePoints = $derived.by(() => {
		const out: { lat: number; lng: number }[] = [];
		for (const c of courses) {
			const start = courseStart(c);
			if (start && Number.isFinite(start.lat) && Number.isFinite(start.lng)) out.push(start);
		}
		for (const list of coursesByPark.values()) {
			const park = list[0].park;
			if (park.centroid_lat !== null && park.centroid_lng !== null) {
				out.push({ lat: park.centroid_lat, lng: park.centroid_lng });
			}
		}
		return out;
	});

	$effect(() => {
		const term = courseQuery.trim();
		if (show !== 'courses' || term.length < PLACE_LOOKUP_MIN_CHARS || coursesLoading || coursesFailed) {
			placeLookup = { status: 'idle' };
			return;
		}
		const points = coursePoints;
		const bias = coursePlaceBias(
			courses.map((c) => c.park.region_code),
			points,
			typeof navigator === 'undefined' ? null : navigator.language,
		);
		const controller = new AbortController();
		placeLookup = { status: 'loading' };
		void (async () => {
			try {
				const { searchPlaces } = await import('#lib/routes/geocoding.ts');
				const outcome = await searchPlaces(term, 8, controller.signal, bias);
				if (controller.signal.aborted || outcome.status === 'aborted') return;
				placeLookup =
					outcome.status === 'ok'
						? { status: 'ok', places: placesNearCourses(outcome.results, points) }
						: { status: 'unavailable' };
			} catch (e) {
				if (controller.signal.aborted) return;
				console.error('place lookup failed', e);
				placeLookup = { status: 'unavailable' };
			}
		})();
		return () => controller.abort();
	});

	const placeRows = $derived(placeLookup.status === 'ok' ? placeLookup.places : []);
	// A place may still be on its way, or is there to pick, so "no park or
	// course by that name" is not yet "nothing at all".
	const placesPending = $derived(
		show === 'courses' && (placeLookup.status === 'loading' || placeRows.length > 0),
	);

	// What a screen reader hears as the search settles.
	const courseSearchStatus = $derived.by(() => {
		if (courseTerms.length === 0 || coursesLoading || coursesFailed) return '';
		const found = m('races.courseSearchStatus', { n: anyTimeCount });
		return placeRows.length > 0 ? `${found} ${m('races.placeSuggestionsStatus', { n: placeRows.length })}` : found;
	});

	let nearControls = $state<HTMLElement | null>(null);

	async function pickPlace(place: PlaceSearchResult) {
		clearTimeout(placeTimer);
		center = { lng: place.lng, lat: place.lat };
		radiusM = undefined;
		nearPlace = '';
		nearLabel = placeLabel(place.name);
		geoError = '';
		clearSearch();
		// The row that was pressed goes with the search, so focus lands on what
		// it set: the near chip, which also undoes it.
		await tick();
		nearControls?.querySelector<HTMLElement>('[data-testid="races-near-clear"]')?.focus();
	}

	// A verified club's admin is pointed at the course suggestions waiting for
	// them (decisions § 2396). Auxiliary: a failed read shows no link.
	let suggestionsToReview = $state(0);
	onMount(() => {
		fetchRaceCourseReviewQueue()
			.then((queue) => {
				suggestionsToReview = queue.reduce((n, item) => n + item.pendingCount, 0);
			})
			.catch((e) => console.error('course suggestion queue read failed', e));
	});

	let placeTimer: ReturnType<typeof setTimeout> | undefined;
	function onNearPlaceInput(value: string) {
		clearTimeout(placeTimer);
		nearPlace = value;
		const term = value.trim();
		if (!term) {
			center = null;
			radiusM = undefined;
			nearLabel = '';
			geoError = '';
			return;
		}
		placeTimer = setTimeout(async () => {
			const { geocodePlace } = await import('#lib/routes/geocoding.ts');
			// Ranked nearer the courses, never held to their countries: the race
			// calendar is not limited to where the parks are.
			const proximity = coursePlaceBias([], coursePoints).proximity;
			const place = await geocodePlace(term, undefined, proximity ? { proximity } : undefined);
			if (place) {
				center = place.center;
				radiusM = place.radiusM;
				nearLabel = term;
				geoError = '';
			} else {
				center = null;
				radiusM = undefined;
				nearLabel = '';
				geoError = m('discover.nearNoMatch');
			}
		}, 350);
	}

	function useMyLocation() {
		geoError = '';
		if (typeof navigator === 'undefined' || !navigator.geolocation) {
			geoError = m('discover.geoNeedsHttps');
			return;
		}
		navigator.geolocation.getCurrentPosition(
			(pos) => {
				center = { lng: pos.coords.longitude, lat: pos.coords.latitude };
				radiusM = undefined;
				nearPlace = '';
				nearLabel = m('races.nearMe');
				geoError = '';
			},
			() => {
				geoError = m('discover.geoFailed');
			},
			{ enableHighAccuracy: false, timeout: 15000, maximumAge: 60000 }
		);
	}

	function clearNear() {
		clearTimeout(placeTimer);
		nearPlace = '';
		center = null;
		radiusM = undefined;
		nearLabel = '';
		geoError = '';
	}

	function clearFilters() {
		query = '';
		distance = '';
		when = 'upcoming';
		clearNear();
	}

	function openImport(race: RaceListingResult) {
		importing = race;
	}

	function onCreated() {
		showEditor = false;
		run();
	}
</script>

<svelte:head><title>{m('races.pageTitle')}</title></svelte:head>

{#snippet nearChip()}
	<button
		type="button"
		class="chip active removable"
		onclick={clearNear}
		aria-label={m('filterBar.removeFilter', { filter: `${m('discover.nearLabel')}: ${nearLabel}` })}
		data-testid="races-near-clear"
	>
		<span>{m('discover.nearLabel')}: {nearLabel}</span>
		<span class="material-symbols" aria-hidden="true">close</span>
	</button>
{/snippet}

<!-- The search's explanation is shown in the Filters sheet; a screen reader
     hears it on the field too, which is the one place it is always present.
     It finds races by name and park courses by name, park and place, so it
     stays in every view and says what it finds in the one showing. -->
{#snippet raceSearch()}
	<AppSearchField
		bind:value={query}
		label={m(show === 'races' ? 'races.searchPlaceholder' : show === 'courses' ? 'races.searchCoursesPlaceholder' : 'races.searchAllPlaceholder')}
		testid="races-search"
		describedby="races-search-desc"
	/>
	<span class="visually-hidden" id="races-search-desc">{m(show === 'courses' ? 'races.searchCoursesHint' : 'races.searchHint')}</span>
{/snippet}

<!-- The Filters sheet. Every control's explanation sits here, beside it and
     named by its aria-describedby, rather than under each control on the page
     (issue #1374 owner decision; control_hints_guard.test.ts). The search and
     the Show chips stay on the bar, so their explanations open here too. -->
{#snippet raceFilters()}
	<dl class="sheet-notes" data-testid="races-sheet-notes">
		<div>
			<dt>{m('filterBar.search')}</dt>
			<dd>{m('races.searchHint')}</dd>
		</div>
		<div>
			<dt>{m('races.showGroup')}</dt>
			<dd>{m('races.showHint')}</dd>
		</div>
	</dl>

	<section class="sheet-field" aria-labelledby="races-near-heading">
		<h3 id="races-near-heading">{m('discover.nearLabel')}</h3>
		<div class="near-row">
			<AppSearchField
				value={nearPlace}
				oninput={onNearPlaceInput}
				label={m('races.nearPlace')}
				testid="races-near"
				describedby="races-near-hint"
			/>
			<button type="button" class="chip near-locate" onclick={useMyLocation} data-testid="races-use-location">
				{m('discover.useMyLocation')}
			</button>
		</div>
		<p class="filter-hint" id="races-near-hint">{m('races.nearPlaceHint')}</p>
		{#if geoError}
			<p class="near-error" role="status">{geoError}</p>
		{/if}
	</section>

	<section class="sheet-field" aria-labelledby="races-when-heading">
		<h3 id="races-when-heading">{m('races.whenGroup')}</h3>
		<div class="chip-row" role="group" aria-labelledby="races-when-heading" aria-describedby="races-when-hint">
			<button
				type="button"
				class="chip"
				class:active={when === 'upcoming'}
				aria-pressed={when === 'upcoming'}
				onclick={() => (when = 'upcoming')}
				data-testid="races-when-upcoming"
			>
				{m('races.whenUpcoming')}
			</button>
			<button
				type="button"
				class="chip"
				class:active={when === 'recent'}
				aria-pressed={when === 'recent'}
				onclick={() => (when = 'recent')}
				data-testid="races-when-recent"
			>
				{m('races.whenRecent')}
			</button>
		</div>
		<p class="filter-hint" id="races-when-hint">{m('races.whenHint', { days: RECENT_WINDOW_DAYS })}</p>
	</section>

	<section class="sheet-field" aria-labelledby="races-distance-heading">
		<h3 id="races-distance-heading">{m('races.distanceGroup')}</h3>
		<div
			class="chip-row"
			role="group"
			aria-labelledby="races-distance-heading"
			aria-describedby="races-distance-hint"
		>
			{#each DISTANCES as d (d.v)}
				<button
					type="button"
					class="chip"
					class:active={distance === d.v}
					aria-pressed={distance === d.v}
					onclick={() => (distance = d.v)}
					data-testid="races-dist-{d.v || 'any'}"
				>
					{m(d.k)}
				</button>
			{/each}
		</div>
		<p class="filter-hint" id="races-distance-hint">{m('races.distanceFilterHint')}</p>
	</section>
{/snippet}

<div class="races-page">
	<RunSurfaceTabs active="races">
		{#snippet help()}<HelpLink route="/races" />{/snippet}
		{#snippet actions()}
			<button
				type="button"
				class="btn btn-primary"
				onclick={() => (showEditor = true)}
				data-testid="race-submit"
			>
				{m('races.submitRace')}
			</button>
		{/snippet}
	</RunSurfaceTabs>

	<!-- Filters belong to the race calendar, so the Courses view, which hides
	     it, keeps the search and the Show chips. -->
	<div class="races-filter-bar" data-testid="races-filter-bar">
		<FilterBar
			idPrefix="races"
			search={raceSearch}
			chips={showChips}
			chipsLabel={m('races.showGroup')}
			{activeFilters}
			filters={show === 'courses' ? undefined : raceFilters}
			activeFilterCount={activeCount}
			bind:filtersOpen
		/>
		{#if geoError && !filtersOpen && show !== 'courses'}
			<p class="near-error" role="status">{geoError}</p>
		{/if}
		{#if suggestionsToReview > 0}
			<a class="review-link" href="/races/course-suggestions" data-testid="race-course-queue-link">
				{m('raceCourse.queueLink', { n: suggestionsToReview })}
			</a>
		{/if}
	</div>

	{#if show !== 'courses'}
		<section class="races-section" aria-labelledby="races-upcoming-heading" data-testid="races-upcoming">
			<div class="section-head">
				<h2 id="races-upcoming-heading">{m('races.sectionUpcoming')}</h2>
				<p class="section-intro">{m('races.subtitle')}</p>
			</div>

			{#if loading}
				<p class="state-msg">{m('races.loading')}</p>
			{:else if error}
				<div class="races-error" role="alert" data-testid="races-error">
					<span>{m('races.searchFailed')}</span>
					<button type="button" class="btn btn-outline" onclick={run}>{m('races.retry')}</button>
				</div>
			{:else if results.length === 0}
				<EmptyState
					icon="event_busy"
					title={when === 'recent' ? m('races.emptyRecent', { days: RECENT_WINDOW_DAYS }) : m('races.empty')}
					data-testid="races-empty"
				>
					{#snippet actions()}
						{#if activeCount > 0 || query.trim() !== ''}
							<button type="button" class="btn btn-outline" onclick={clearFilters}>
								{m('races.clearFilters')}
							</button>
						{/if}
						<button type="button" class="btn btn-primary" onclick={() => (showEditor = true)}>
							{m('races.submitRace')}
						</button>
					{/snippet}
				</EmptyState>
			{:else}
				<ul class="results" data-testid="races-results">
					{#each results as r (r.id)}
						<RaceCalendarCard race={r} onimport={openImport} />
					{/each}
				</ul>
			{/if}
		</section>
	{/if}

	{#if show !== 'races'}
		<section class="races-section" aria-labelledby="races-any-time-heading" data-testid="races-any-time">
			<div class="section-head">
				<div class="section-title-row">
					<h2 id="races-any-time-heading">{m('races.sectionAnyTime')}</h2>
					{#if anyTimeTruncated && !coursesLoading && !coursesFailed}
						<a class="see-all" href={seeAllHref} data-testid="races-any-time-all">
							{m('races.anyTimeSeeAll', { n: anyTimeCourseTotal })}
							<span class="material-symbols" aria-hidden="true">arrow_forward</span>
						</a>
					{/if}
				</div>
				{#if show === 'courses'}
					<p class="section-intro">{m('races.anyTimeIntroCourses')}</p>
				{:else}
					<p class="section-intro">{m('races.anyTimeIntro')}</p>
				{/if}
			</div>

			<!-- The race filters are hidden here. The search above finds places
			     too, so all this view adds is the way to use the reader's own
			     location, and the chip saying what the courses are ordered by. -->
			{#if show === 'courses'}
				<div class="filters" data-testid="races-any-time-near" bind:this={nearControls}>
					<div class="active-filters">
						{#if nearLabel}{@render nearChip()}{/if}
						<button type="button" class="chip near-locate" onclick={useMyLocation} data-testid="races-use-location">
							{m('discover.useMyLocation')}
						</button>
					</div>
					{#if geoError}
						<p class="near-error" role="status">{geoError}</p>
					{/if}
				</div>
				<p class="visually-hidden" role="status" data-testid="races-course-search-status">{courseSearchStatus}</p>
			{/if}

			{#if coursesLoading}
				<p class="state-msg">{m('parks.loading')}</p>
			{:else if coursesFailed}
				<div class="races-error" role="alert" data-testid="races-any-time-error">
					<span>{m('parks.loadFailed')}</span>
					<button type="button" class="btn btn-outline" onclick={loadCourses}>{m('parks.retry')}</button>
				</div>
			{:else if anyTimeCount === 0 && courseTerms.length > 0 && placesPending}
				<p class="state-msg" data-testid="races-any-time-no-name-match">
					{m('races.anyTimeNoNameMatch', { query: courseQuery.trim() })}
				</p>
			{:else if anyTimeCount === 0 && courseTerms.length > 0}
				<EmptyState
					icon="search_off"
					title={show === 'courses' && placeLookup.status === 'ok'
						? m('races.anyTimeNoMatchAnywhere', { query: courseQuery.trim() })
						: m('races.anyTimeNoMatch', { query: courseQuery.trim() })}
					data-testid="races-any-time-no-match"
				>
					{#snippet actions()}
						<button type="button" class="btn btn-outline" onclick={clearSearch} data-testid="races-any-time-clear-search">
							{m('filterBar.clearSearch')}
						</button>
					{/snippet}
				</EmptyState>
			{:else if anyTimeCount === 0}
				<EmptyState icon="park" title={m('parks.empty')} data-testid="races-any-time-empty" />
			{:else}
				{#if anyTimeParks.length > 0}
					<div class="any-time-parks">
						{#if orderedCourses.length > 0}
							<SectionHeader label={m('races.anyTimeParks')} id="races-any-time-parks-heading" level={3} class="races-any-time-head" />
						{/if}
						<ul
							class="park-list"
							aria-labelledby={orderedCourses.length > 0 ? 'races-any-time-parks-heading' : 'races-any-time-heading'}
							data-testid="races-any-time-parks"
						>
							{#each anyTimeParks as { park: list, awayM } (list[0].park.id)}
								<li data-testid="races-any-time-park">
									<ParkCard park={list[0].park} courses={list} />
									{#if awayM !== null}
										<span class="park-away" data-testid="races-any-time-park-away">
											{m('races.anyTimeAway', { distance: fmtCompactDistance(awayM) })}
										</span>
									{/if}
								</li>
							{/each}
						</ul>
					</div>
				{/if}
				{#if orderedCourses.length > 0}
					<SectionHeader label={m('races.showCourses')} id="races-any-time-courses-heading" level={3} class="races-any-time-head" />
				{/if}
				{#if recordsFailed && orderedCourses.length > 0}
					<p class="records-failed" role="status" data-testid="races-any-time-records-failed">
						{m('races.anyTimeFastestFailed')}
						<button type="button" class="btn btn-outline btn-sm" onclick={loadRecords}>{m('parks.retry')}</button>
					</p>
				{/if}
				{#if orderedCourses.length > 0}
				<ul class="course-list" aria-labelledby="races-any-time-courses-heading" data-testid="races-any-time-list">
					{#each orderedCourses as { course, awayM } (course.id)}
						{@const shapeKey = courseShapeShown(course.course_shape) ? labelKey(SHAPE_LABEL, course.course_shape) : null}
						{@const laps = courseLapsChip(course.laps)}
						{@const statusKey = labelKey(STATUS_LABEL, course.status)}
						{@const record = records.get(course.id)}
						<!-- The course name's link covers the card; the park name is a
						     second link drawn above it, to the park's page. -->
						<li class="course-card" data-testid="races-any-time-course">
							<a
								class="course-name"
								href="/parks/{regionSlug(course.park.region_code)}/{course.park.slug}/{course.slug}"
								data-testid="races-any-time-course-link"
							>{course.segment.name}</a>
							<a
								class="course-park"
								href="/parks/{regionSlug(course.park.region_code)}/{course.park.slug}"
								aria-label={m('races.anyTimeParkLink', { park: `${course.park.name}, ${regionName(course.park.region_code)}` })}
								data-testid="races-any-time-park-link"
							>{course.park.name}, {regionName(course.park.region_code)}</a>
							<span class="course-meta" data-testid="races-any-time-meta">
								<span data-testid="races-any-time-distance">{fmtCourseDistance(course.segment.distance_m)}</span>{#if laps}&nbsp;·&nbsp;<span data-testid="races-any-time-laps">{m('parks.lapsChip', { n: laps })}</span>{/if}{#if shapeKey}&nbsp;·&nbsp;{m(shapeKey)}{/if}{#if awayM !== null}&nbsp;·&nbsp;{m('races.anyTimeAway', { distance: fmtCompactDistance(awayM) })}{/if}
							</span>
							{#if !recordsFailed}
								<span class="course-record" data-testid="races-any-time-record">
									{#if record}
										{record.displayName
											? m('races.anyTimeFastestBy', { year: record.season, time: formatDuration(record.timeSeconds), name: record.displayName })
											: m('races.anyTimeFastest', { year: record.season, time: formatDuration(record.timeSeconds) })}
									{:else}
										{m('races.anyTimeNoTimeYet')}
									{/if}
								</span>
							{/if}
							{#if course.status !== 'open' && statusKey}
								<span class="status-pill" class:closed={course.status === 'closed'}>{m(statusKey)}</span>
							{/if}
						</li>
					{/each}
				</ul>
				{/if}
			{/if}

			{#if show === 'courses' && courseTerms.length > 0 && !coursesLoading && !coursesFailed}
				{#if placeRows.length > 0}
					<div class="place-suggestions" data-testid="races-place-suggestions">
						<SectionHeader label={m('races.placeSuggestionsHeading')} id="races-places-heading" level={3} class="races-any-time-head" />
						<ul class="place-list" aria-labelledby="races-places-heading">
							{#each placeRows as place (place.name)}
								<li>
									<ListCard
										onclick={() => pickPlace(place)}
										title={m('races.placeSuggestion', { place: placeLabel(place.name) })}
										dense
										chevron
										testid="races-place-suggestion"
									>
										{#snippet leading()}<span class="material-symbols place-icon" aria-hidden="true">near_me</span>{/snippet}
									</ListCard>
								</li>
							{/each}
						</ul>
					</div>
				{:else if placeLookup.status === 'loading'}
					<p class="state-msg" data-testid="races-place-loading">{m('races.placeLookupLoading')}</p>
				{:else if placeLookup.status === 'unavailable'}
					<p class="near-error" data-testid="races-place-unavailable">{m('races.placeLookupFailed')}</p>
				{/if}
			{/if}
		</section>
	{/if}
</div>

<Modal
	open={showEditor}
	title={m('races.editorTitle')}
	narrow
	onclose={() => (showEditor = false)}
>
	<RaceListingEditor oncreated={onCreated} oncancel={() => (showEditor = false)} />
</Modal>

<RaceImportDialog race={importing} onclose={() => (importing = null)} />

<style>
	.races-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.races-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.section-head h2 {
		margin: 0;
		font-size: 1.15rem;
	}
	.section-intro {
		margin: 0.25rem 0 0;
		color: var(--color-text-secondary);
		line-height: 1.45;
	}
	.records-failed {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.course-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(18rem, 100%), 1fr));
		gap: var(--space-sm);
	}
	:global(.races-any-time-head) {
		margin-bottom: var(--space-xs);
	}
	.park-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(16rem, 100%), 1fr));
		gap: var(--space-sm);
	}
	.park-list > li {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.park-away {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.course-card {
		position: relative;
		display: grid;
		grid-template-columns: 1fr auto;
		align-items: start;
		gap: 0.15rem var(--space-sm);
		height: 100%;
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		text-decoration: none;
	}
	.course-card:hover,
	.course-card:focus-within {
		border-color: var(--color-primary);
	}
	.course-name {
		grid-column: 1;
		font-weight: 600;
		color: var(--color-text);
		text-decoration: none;
	}
	.course-name::after {
		content: '';
		position: absolute;
		inset: 0;
		border-radius: inherit;
	}
	.course-park {
		position: relative;
		z-index: 1;
		justify-self: start;
		display: inline-flex;
		align-items: center;
		min-height: 24px;
		text-decoration: underline;
		text-underline-offset: 2px;
	}
	.course-park,
	.course-meta,
	.course-record {
		grid-column: 1;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.course-record {
		color: var(--color-text);
	}
	.status-pill {
		grid-column: 2;
		grid-row: 1;
		padding: 0.1rem 0.5rem;
		border-radius: 999px;
		font-size: 0.75rem;
		background: var(--color-bg-secondary);
		white-space: nowrap;
	}
	.status-pill.closed {
		color: var(--color-danger-text);
	}
	.section-title-row {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-xs) var(--space-md);
	}
	.see-all {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		font-weight: 600;
	}
	.see-all .material-symbols {
		font-size: 1.1rem;
	}
	.review-link {
		align-self: flex-start;
		font-weight: 600;
	}
	.filters {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	/* One row that scrolls inside itself rather than wrapping: the state stays
	   a single line however many filters are on. */
	.active-filters {
		display: flex;
		gap: 0.4rem;
		overflow-x: auto;
		scrollbar-width: thin;
		padding-bottom: 2px;
	}
	.active-filters .chip {
		flex: 0 0 auto;
		white-space: nowrap;
	}
	.removable {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}
	.removable .material-symbols {
		font-size: 1rem;
	}
	.near-row {
		display: flex;
		gap: 0.4rem;
		align-items: stretch;
		flex-wrap: wrap;
	}
	.place-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.place-icon {
		color: var(--color-primary);
		font-size: 1.2rem;
	}
	.near-locate {
		flex-shrink: 0;
		white-space: nowrap;
	}
	.near-error {
		color: var(--color-danger-text);
		font-size: 0.85rem;
		margin: 0;
	}
	.chip-row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}
	.chip {
		appearance: none;
		border: 1.5px solid var(--color-border);
		background: var(--color-surface);
		color: var(--color-text);
		padding: 0.35rem 0.8rem;
		border-radius: 999px;
		font-size: 0.85rem;
		cursor: pointer;
	}
	.chip.active {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-weight: 600;
	}
	@media (max-width: 40rem) {
		.races-page {
			gap: var(--space-md);
		}
		.chip {
			min-height: var(--tap-target-min);
		}
	}
	.results {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.state-msg {
		color: var(--color-text-secondary);
	}
	.races-error {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		color: var(--color-danger-text);
	}
	.races-filter-bar {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	/* The Filters sheet: each control under its heading with its explanation
	   right below it. */
	.sheet-notes {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin: 0;
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
	}
	.sheet-notes dt {
		font-weight: 600;
		font-size: 0.85rem;
	}
	.sheet-notes dd {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		line-height: 1.45;
	}
	.sheet-field {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.sheet-field h3 {
		margin: 0;
		font-size: var(--font-size-section-title);
		font-weight: 600;
	}
	.filter-hint {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		line-height: 1.45;
		margin: 0;
	}
</style>
