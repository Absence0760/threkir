<script lang="ts">
	import { localStore } from '#lib/core/browser_storage.ts';
	import { routeDisplayDistanceM } from '#lib/routes/official_distance.ts';
	import { onMount } from 'svelte';
	import { compareOrdinal } from '#lib/util/ordinal_compare.ts';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { formatDistance } from '#lib/core/mock-data.ts';
	import { formatElevation, getUnit } from '#lib/format/units.svelte.ts';
	import { fetchRoutesWithError, setRouteStar } from '#lib/core/data.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { routeSurfaceLabel } from '#lib/i18n/enum_labels.svelte.ts';
	import { fold, compareFoldedNames } from '#lib/segments/catalogue_browse.ts';
	import ImportRoute from '#lib/components/ImportRoute.svelte';
	import SkeletonBlock from '#lib/components/SkeletonBlock.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import FilterBar, { type ActiveFilter, type FilterChip } from '#lib/components/FilterBar.svelte';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import RunSurfaceTabs from '#lib/components/RunSurfaceTabs.svelte';
	import RoutesViewNav from '#lib/components/RoutesViewNav.svelte';
	import RouteExplorer from '#lib/components/RouteExplorer.svelte';
	import RouteTrackPreview from '#lib/components/RouteTrackPreview.svelte';
	import type { RouteListItem } from '#lib/routes/route_list_columns.ts';
	import type { Snapshot } from './$types';
	import { isListStale, listToken } from '#lib/core/list_freshness.ts';

	// Mine or Explore, read from the URL: the view row is links
	// (RoutesViewNav), so a link, a refresh and back all reopen the same view.
	const tab = $derived<'mine' | 'explore'>(
		page.url.searchParams.get('tab') === 'explore' ? 'explore' : 'mine',
	);
	let routes = $state<RouteListItem[]>([]);
	let loading = $state(true);
	let fetchError = $state<string | null>(null);
	let showImport = $state(false);

	// Filter state for the "My routes" tab: the search and the Starred
	// toggle on the FilterBar, surface, distance and sort in its sheet.
	// Filtering is client-side because the list is fully resident.
	type SurfaceFilter = 'any' | 'road' | 'trail' | 'mixed';
	type DistanceBucket = 'any' | 'lt5' | '5to10' | '10to20' | 'gt20';
	type SortKey = 'newest' | 'longest' | 'shortest' | 'most_run' | 'az';

	let search = $state('');
	let surfaceFilter = $state<SurfaceFilter>('any');
	let distanceFilter = $state<DistanceBucket>('any');
	let sortKey = $state<SortKey>('newest');
	let starredOnly = $state(false);

	const FILTERS_KEY = 'routes_filters_v1';
	let filtersHydrated = $state(false);

	$effect(() => {
		if (!filtersHydrated) return;
		try {
			localStore()?.setItem(
				FILTERS_KEY,
				JSON.stringify({ search, surfaceFilter, distanceFilter, sortKey, starredOnly }),
			);
		} catch (_) {
			/* silent — quota / private mode etc. */
		}
	});

	/// Monotonic generation counter. Matches the /runs page pattern —
	/// snapshot.restore bumps the gen so an in-flight load() kicked off
	/// on mount discards its result instead of clobbering the captured
	/// list on back-nav from a route-detail page.
	let fetchGen = $state(0);
	/// The list-freshness token `routes` was loaded under. Plain `let`: only
	/// the snapshot reads it. See lib/core/list_freshness.ts.
	let loadedToken = '';

	async function load() {
		loading = true;
		fetchError = null;
		const gen = ++fetchGen;
		const token = listToken('routes');
		const result = await fetchRoutesWithError();
		if (gen !== fetchGen) return;
		routes = result.routes;
		fetchError = result.error ? errorCopy(result.error, m, 'routes: fetchError') : null;
		if (!result.error) loadedToken = token;
		loading = false;
	}

	onMount(() => {
		if (page.url.searchParams.get('tab') === 'heatmap') {
			// Deep-link compat: `/routes?tab=heatmap` now bounces to
			// the standalone `/routes/heatmap` page. Use replaceState
			// so the back button skips the redirect hop.
			void goto('/routes/heatmap', { replace: true });
			return;
		}
		// Snapshot restore (SvelteKit back-nav) runs BEFORE onMount and
		// will have already flipped filtersHydrated. Skip the localStorage
		// read in that case — the snapshot is authoritative for this paint.
		if (!filtersHydrated) {
			try {
				const raw = localStore()?.getItem(FILTERS_KEY) ?? null;
				if (raw) {
					const saved = JSON.parse(raw);
					if (typeof saved.search === 'string') search = saved.search;
					if (saved.surfaceFilter) surfaceFilter = saved.surfaceFilter;
					if (saved.distanceFilter) distanceFilter = saved.distanceFilter;
					if (saved.sortKey) sortKey = saved.sortKey;
					if (typeof saved.starredOnly === 'boolean') starredOnly = saved.starredOnly;
				}
			} catch (_) {
				/* leave defaults */
			}
			filtersHydrated = true;
		}
		// Snapshot restore populates `routes` synchronously and flips
		// loading=false — only fetch when neither happened.
		if (routes.length === 0 && loading) load();
	});

	// Bucket boundaries are evaluated in the user's preferred unit so
	// "< 5" means "< 5 km" for metric users and "< 5 mi" for imperial
	// users. The bucket KEYS (lt5, 5to10, ...) are unit-agnostic
	// logical labels — switching the user's pref re-buckets every
	// route through the new threshold ladder. Without this an
	// mi-mode user would still see the metric thresholds even though
	// the labels read in miles.
	const METRES_PER_MILE = 1609.344;
	function shown(r: RouteListItem): number {
		return routeDisplayDistanceM(r.distance_m, r.official_distance_m);
	}

	function inDistanceBucket(meters: number, b: DistanceBucket): boolean {
		const unitMetres = getUnit() === 'mi' ? METRES_PER_MILE : 1000;
		const v = meters / unitMetres;
		switch (b) {
			case 'any':
				return true;
			case 'lt5':
				return v < 5;
			case '5to10':
				return v >= 5 && v < 10;
			case '10to20':
				return v >= 10 && v < 20;
			case 'gt20':
				return v >= 20;
		}
	}

	let distanceUnitLabel = $derived(getUnit() === 'mi' ? 'mi' : 'km');

	let filteredRoutes = $derived.by(() => {
		// Folded on BOTH sides of the comparison, never `toLowerCase`. The two
		// runtimes' own lower-case answers differ at 466 code points, and the one
		// reachable in Latin text is U+0130: `'İstanbul Loop'.toLowerCase()` is
		// `i̇stanbul loop` in a browser — an `i` plus a combining dot — which does
		// NOT contain `istanbul`, while Dart's simple mapping drops the dot and
		// does. So the same route was findable by typing `istanbul` on the phone
		// and not here (decisions § 1337). Folding also strips the accent, which
		// is what lets `zurich` reach `Zürich Loop` from a keyboard without one.
		const q = fold(search.trim());
		const out = routes.filter((r) => {
			if (starredOnly && !r.is_starred) return false;
			if (surfaceFilter !== 'any' && r.surface !== surfaceFilter) return false;
			if (!inDistanceBucket(shown(r), distanceFilter)) return false;
			if (q) {
				if (!fold(r.name ?? '').includes(q)) return false;
			}
			return true;
		});
		switch (sortKey) {
			case 'newest':
				out.sort((a, b) =>
					compareOrdinal(b.created_at ?? '', a.created_at ?? ''),
				);
				break;
			case 'longest':
				out.sort((a, b) => shown(b) - shown(a));
				break;
			case 'shortest':
				out.sort((a, b) => shown(a) - shown(b));
				break;
			case 'most_run':
				out.sort((a, b) => (b.run_count ?? 0) - (a.run_count ?? 0));
				break;
			case 'az':
				out.sort((a, b) =>
					compareFoldedNames(a.name ?? '', a.id, b.name ?? '', b.id),
				);
				break;
		}
		return out;
	});

	let filtersActive = $derived(
		search.trim().length > 0 ||
			surfaceFilter !== 'any' ||
			distanceFilter !== 'any' ||
			starredOnly,
	);

	const DISTANCE_BUCKETS: Exclude<DistanceBucket, 'any'>[] = ['lt5', '5to10', '10to20', 'gt20'];
	function distanceBucketLabel(b: Exclude<DistanceBucket, 'any'>): string {
		switch (b) {
			case 'lt5':
				return `< 5 ${distanceUnitLabel}`;
			case '5to10':
				return `5–10 ${distanceUnitLabel}`;
			case '10to20':
				return `10–20 ${distanceUnitLabel}`;
			case 'gt20':
				return `20+ ${distanceUnitLabel}`;
		}
	}

	let filtersOpen = $state(false);

	// Starred is the one quick chip; FilterBar draws a lone chip with an icon
	// as a toggle in the search row (the mobile lone-chip rule).
	const starredChip = $derived<FilterChip[]>([
		{
			key: 'starred',
			label: m('routesPage.starred'),
			pressed: starredOnly,
			onclick: () => (starredOnly = !starredOnly),
			testid: 'routes-starred',
			icon: 'star',
		},
	]);

	// The sheet's filters that are on, as removable chips on the bar's line.
	const activeFilters = $derived.by<ActiveFilter[]>(() => {
		const out: ActiveFilter[] = [];
		if (surfaceFilter !== 'any') {
			out.push({
				key: 'surface',
				label: routeSurfaceLabel(surfaceFilter),
				onRemove: () => (surfaceFilter = 'any'),
				testid: 'routes-chip-surface',
			});
		}
		if (distanceFilter !== 'any') {
			out.push({
				key: 'distance',
				label: distanceBucketLabel(distanceFilter),
				onRemove: () => (distanceFilter = 'any'),
				testid: 'routes-chip-distance',
			});
		}
		return out;
	});
	const activeCount = $derived(activeFilters.length);

	function clearFilters() {
		search = '';
		surfaceFilter = 'any';
		distanceFilter = 'any';
		starredOnly = false;
	}

	async function toggleStar(event: MouseEvent, routeId: string) {
		// Stop the parent <a> from navigating to the detail page when
		// the star button is clicked. The star is a sub-action; the
		// rest of the card still goes to the detail.
		event.preventDefault();
		event.stopPropagation();
		const i = routes.findIndex((r) => r.id === routeId);
		if (i < 0) return;
		const next = !routes[i].is_starred;
		// Optimistic update — the toggle should feel instant. If the
		// network call fails we revert and surface the error.
		routes = routes.map((r) => (r.id === routeId ? { ...r, is_starred: next } : r));
		try {
			await setRouteStar(routeId, next);
			loadedToken = listToken('routes');
		} catch (e) {
			routes = routes.map((r) => (r.id === routeId ? { ...r, is_starred: !next } : r));
			showToast(
				next
					? m('routesPage.starError', { error: errorCopy(e, m, 'routesPage.starError') })
					: m('routesPage.unstarError', { error: errorCopy(e, m, 'routesPage.unstarError') }),
				'error',
			);
		}
	}

	export const snapshot: Snapshot<{
		routes: RouteListItem[];
		search: string;
		surfaceFilter: SurfaceFilter;
		distanceFilter: DistanceBucket;
		sortKey: SortKey;
		starredOnly: boolean;
		scrollY: number;
		listToken: string;
	}> = {
		capture: () => ({
			routes,
			search,
			surfaceFilter,
			distanceFilter,
			sortKey,
			starredOnly,
			scrollY: typeof window === 'undefined' ? 0 : window.scrollY,
			listToken: loadedToken,
		}),
		restore: (s) => {
			search = s.search;
			surfaceFilter = s.surfaceFilter;
			distanceFilter = s.distanceFilter;
			sortKey = s.sortKey;
			starredOnly = s.starredOnly;
			filtersHydrated = true;
			// A route was written since the list was loaded (saved, edited,
			// starred or deleted on its detail page, or a run moved its
			// run_count): keep the tab and filters, leave `routes` empty and
			// `loading` set so onMount fetches.
			if (isListStale('routes', s.listToken)) return;
			// Invalidate any in-flight load() the mount-time path may have
			// already kicked off so it doesn't overwrite the captured list.
			fetchGen++;
			routes = s.routes;
			loadedToken = s.listToken;
			loading = false;
			// SvelteKit's auto scroll-restoration runs before the list has
			// rendered, so the page is too short and scroll falls back to
			// 0. Re-apply the captured scrollY after the DOM updates.
			if (typeof window !== 'undefined' && s.scrollY > 0) {
				queueMicrotask(() => {
					requestAnimationFrame(() => window.scrollTo(0, s.scrollY));
				});
			}
		},
	};
</script>

<svelte:head>
	<title>{m('routesPage.pageTitle')} — Threkir</title>
</svelte:head>

{#if showImport}
	<ImportRoute onclose={() => (showImport = false)} onimport={load} />
{/if}

{#snippet routeSearch()}
	<AppSearchField
		bind:value={search}
		label={m('routesPage.searchLabel')}
		placeholder={m('routesPage.searchPlaceholder')}
		clearLabel={m('routesPage.clearSearch')}
		testid="routes-search"
	/>
{/snippet}

{#snippet routeActions()}
	<div class="toolbar-actions">
		<button class="btn btn-outline btn-sm" type="button" onclick={() => (showImport = true)}>
			<span class="material-symbols" aria-hidden="true">upload_file</span>
			{m('routesPage.import')}
		</button>
		<a href="/routes/new" class="btn btn-primary btn-sm">
			<span class="material-symbols" aria-hidden="true">add</span>
			{m('routesPage.newRoute')}
		</a>
	</div>
{/snippet}

<!-- The Filters sheet: each choice applies at once, so the list behind it is
     already right when Done closes it. -->
{#snippet routeFilters()}
	<p class="filter-hint">{m('routesPage.starredSyncTitle')}</p>
	<div class="sheet-field">
		<label for="routes-surface">{m('routesPage.surfaceLabel')}</label>
		<select id="routes-surface" bind:value={surfaceFilter} class="sheet-select" data-testid="routes-surface">
			<option value="any">{m('routesPage.surfaceAny')}</option>
			<option value="road">{routeSurfaceLabel('road')}</option>
			<option value="trail">{routeSurfaceLabel('trail')}</option>
			<option value="mixed">{routeSurfaceLabel('mixed')}</option>
		</select>
	</div>
	<div class="sheet-field">
		<label for="routes-distance">{m('routesPage.distanceLabel')}</label>
		<select id="routes-distance" bind:value={distanceFilter} class="sheet-select" data-testid="routes-distance">
			<option value="any">{m('routesPage.distanceAny')}</option>
			{#each DISTANCE_BUCKETS as b (b)}
				<option value={b}>{distanceBucketLabel(b)}</option>
			{/each}
		</select>
	</div>
	<div class="sheet-field">
		<label for="routes-sort">{m('routesPage.sortLabel')}</label>
		<select id="routes-sort" bind:value={sortKey} class="sheet-select" data-testid="routes-sort">
			<option value="newest">{m('routesPage.sortNewest')}</option>
			<option value="longest">{m('routesPage.sortLongest')}</option>
			<option value="shortest">{m('routesPage.sortShortest')}</option>
			<option value="most_run">{m('routesPage.sortMostRun')}</option>
			<option value="az">{m('routesPage.sortAz')}</option>
		</select>
	</div>
{/snippet}

<div class="page">
	<RunSurfaceTabs active="routes" />
	<RoutesViewNav view={tab === 'explore' ? 'routes' : 'mine'} />

	{#if tab === 'mine'}
		{#if loading}
			<div class="filter-row filter-row-skel" aria-hidden="true">
				<span class="skel-search"><SkeletonBlock height="2.25rem" radius="var(--radius-md)" /></span>
				<SkeletonBlock height="2rem" width="7rem" radius="var(--radius-md)" />
				<SkeletonBlock height="2rem" width="7rem" radius="var(--radius-md)" />
				<SkeletonBlock height="2rem" width="7rem" radius="var(--radius-md)" />
			</div>
			<div class="route-grid" aria-hidden="true">
				{#each Array(6) as _, i (i)}
					<div class="skel-card">
						<SkeletonBlock height="9rem" radius="0" />
						<div class="skel-card-body">
							<SkeletonBlock height="0.75rem" width="60%" />
							<SkeletonBlock height="0.75rem" width="40%" />
						</div>
					</div>
				{/each}
			</div>
			<p class="sr-only" role="status">{m('routesPage.loadingRoutes')}</p>
		{:else if fetchError}
			<div class="error-banner" role="alert">
				<span class="material-symbols" aria-hidden="true">error</span>
				<div>
					<strong>{m('routesPage.loadError')}</strong>
					<span class="error-detail">{fetchError}</span>
				</div>
				<button class="btn btn-outline" onclick={load}>{m('routesPage.retry')}</button>
			</div>
		{:else if routes.length === 0}
			<EmptyState icon="route" title={m('routesPage.emptyTitle')} text={m('routesPage.emptyText')} mascot data-testid="routes-empty">
				{#snippet actions()}
					<a href="/routes/new" class="btn btn-primary">
						<span class="material-symbols" aria-hidden="true">add</span>
						{m('routesPage.buildRoute')}
					</a>
					<button class="btn btn-outline" type="button" onclick={() => (showImport = true)}>
						<span class="material-symbols" aria-hidden="true">upload_file</span>
						{m('routesPage.importFile')}
					</button>
					<a class="btn btn-outline" href="/routes?tab=explore">
						<span class="material-symbols" aria-hidden="true">explore</span>
						{m('routesPage.browseCommunity')}
					</a>
				{/snippet}
			</EmptyState>
		{:else}
			<!-- The list's control row is FilterBar (conventions.md § Web lists):
			     the search, the Starred toggle (a lone chip, so it sits in the
			     search row as a toggle button rather than on a line of its own),
			     Import and New route, and a Filters sheet holding surface,
			     distance and sort. -->
			<FilterBar
				idPrefix="routes"
				search={routeSearch}
				trailing={routeActions}
				chips={starredChip}
				{activeFilters}
				filters={routeFilters}
				activeFilterCount={activeCount}
				bind:filtersOpen
			/>

			<div class="filter-meta">
				<span>
					{m('routesPage.routeCount', { shown: filteredRoutes.length, total: routes.length })}
					{#if filtersActive}<span class="meta-sep"> · </span>{m('routesPage.filtered')}{/if}
				</span>
				{#if filtersActive}
					<button type="button" class="link-btn" onclick={clearFilters}>{m('routesPage.clearFilters')}</button>
				{/if}
			</div>

			{#if filteredRoutes.length === 0}
				<EmptyState
					icon="filter_alt_off"
					title={m('routesPage.noMatchTitle')}
					text={m('routesPage.noMatchText')}
				>
					{#snippet actions()}
						<button type="button" class="btn btn-primary" onclick={clearFilters}>
							{m('routesPage.clearFilters')}
						</button>
					{/snippet}
				</EmptyState>
			{:else}
				<div class="route-grid">
					{#each filteredRoutes as route (route.id)}
						<a href="/routes/{route.id}" class="route-card">
							<div class="route-map-placeholder">
								<RouteTrackPreview
									routeId={route.id}
									waypoints={route.waypoints ?? []}
									ownerUserId={route.user_id}
								/>
								{#if auth.user?.id === route.user_id}
									<button
										type="button"
										class="star-btn"
										class:starred={route.is_starred}
										title={route.is_starred
											? m('routesPage.unstarTitle')
											: m('routesPage.starTitle')}
										aria-label={route.is_starred
											? m('routesPage.unstarRouteLabel', { name: route.name ?? m('routesPage.routeFallback') })
											: m('routesPage.starRouteLabel', { name: route.name ?? m('routesPage.routeFallback') })}
										aria-pressed={route.is_starred}
										onclick={(e) => toggleStar(e, route.id)}
									>
										<span class="material-symbols" aria-hidden="true">star</span>
									</button>
								{/if}
							</div>
							<div class="route-info">
								<h3>{route.name}</h3>
								<div class="route-meta">
									<span>{formatDistance(shown(route))}</span>
									{#if route.elevation_m}
										<span class="meta-sep">&middot;</span>
										<span>{m('routesPage.elevation', { elevation: formatElevation(route.elevation_m) })}</span>
									{/if}
									{#if route.surface}
										<span class="meta-sep">&middot;</span>
										<span class="surface-tag">{routeSurfaceLabel(route.surface)}</span>
									{/if}
								</div>
							</div>
						</a>
					{/each}
				</div>
			{/if}
		{/if}
	{:else if tab === 'explore'}
		<RouteExplorer />
	{/if}
	<!-- `tab === 'heatmap'` was a fall-through here pre-May-2026.
		 The heatmap moved to its own /routes/heatmap route to
		 escape this page's flex chain; onMount() now redirects
		 the legacy ?tab=heatmap URL via goto() before this
		 template paints. -->
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}

	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: var(--color-danger-text);
		font-size: 1.4rem;
	}

	.route-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(22rem, 100%), 1fr));
		gap: var(--space-md);
	}

	.route-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		transition: border-color var(--transition-fast),
			box-shadow var(--transition-fast);
		text-decoration: none;
		color: inherit;
	}

	.route-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.route-map-placeholder {
		position: relative;
		height: 9rem;
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 6%, var(--color-bg-tertiary)),
			var(--color-bg-tertiary) 60%,
			color-mix(in srgb, var(--color-accent-cyan, var(--color-primary)) 5%, var(--color-bg-tertiary))
		);
		border-bottom: 1px solid color-mix(in srgb, var(--color-primary) 30%, var(--color-border));
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.star-btn {
		position: absolute;
		top: 0.5rem;
		inset-inline-end: 0.5rem;
		width: 2.25rem;
		height: 2.25rem;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0;
		background: rgba(0, 0, 0, 0.45);
		border: none;
		border-radius: 50%;
		color: rgba(255, 255, 255, 0.7);
		cursor: pointer;
		transition: background var(--transition-fast),
			color var(--transition-fast),
			transform var(--transition-fast);
	}

	.star-btn:hover {
		background: rgba(0, 0, 0, 0.65);
		transform: scale(1.05);
	}

	.star-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.star-btn.starred {
		background: rgba(0, 0, 0, 0.65);
		color: #fbbf24;
	}

	.star-btn .material-symbols {
		font-size: 1.25rem;
		font-variation-settings: 'FILL' 0;
		transition: font-variation-settings var(--transition-fast);
	}

	.star-btn.starred .material-symbols {
		font-variation-settings: 'FILL' 1;
	}

	.route-info {
		padding: var(--space-md) var(--space-lg);
	}

	h3 {
		font-size: 1rem;
		font-weight: 600;
		margin-bottom: var(--space-xs);
	}

	/* Wraps between figures, never inside one: a number keeps its unit. */
	.route-meta {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.route-meta > span {
		white-space: nowrap;
	}

	.meta-sep {
		color: var(--color-text-tertiary);
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}

	/* The loading frame stands in for FilterBar's top row. */
	.filter-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm) var(--space-md);
		margin-bottom: var(--space-sm);
		flex-wrap: wrap;
	}
	.toolbar-actions {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		margin-inline-start: auto;
	}
	.toolbar-actions .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.toolbar-actions .material-symbols {
		font-size: 1.05rem;
	}
	.filter-meta {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		margin: var(--space-sm) 0 var(--space-lg);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.link-btn {
		background: transparent;
		border: none;
		color: var(--color-primary);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
		padding: 0.2rem 0.3rem;
	}
	.link-btn:hover {
		color: var(--color-primary-hover);
	}

	/* Skeleton (SkeletonBlock). Mirrors
	   the real card layout so the page lands at its true height
	   immediately and the data swap doesn't shift the grid. */
	.skel-search {
		display: block;
		flex: 1 1 18rem;
		min-width: 12rem;
	}
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		pointer-events: none;
	}
	.skel-card-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-md) var(--space-lg);
	}
	.filter-row-skel {
		gap: var(--space-sm);
	}

	.sr-only {
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

	/* The Filters sheet: each control under its label. */
	.sheet-field {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.sheet-field label {
		font-weight: 600;
		font-size: 0.9rem;
	}
	.sheet-select {
		min-height: var(--tap-target-min);
		padding: 0 0.75rem;
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font: inherit;
	}
	.sheet-select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.filter-hint {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		line-height: 1.45;
		margin: 0;
	}

	/* <=30rem (phone): Import and New route share the row under the search,
	   each taking half. */
	@media (max-width: 30rem) {
		.toolbar-actions {
			margin-inline-start: 0;
			width: 100%;
		}
		.toolbar-actions .btn {
			flex: 1 1 0;
			justify-content: center;
		}
	}
</style>
