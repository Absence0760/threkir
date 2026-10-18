<script lang="ts">
	import HelpLink from '#lib/components/help/HelpLink.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import {
		searchRaceListings,
		type RaceListingResult,
		type RaceListingFilters,
		type RaceDistanceBand
	} from '#lib/core/data.ts';
	import { raceImportLegFor } from '#lib/integrations/race_import_providers.ts';
	import { addDays, formatISO } from '#lib/training/training.ts';
	import { probeRaceLeg } from '#lib/integrations/race_import_probe.svelte.ts';
	import RunSurfaceTabs from '#lib/components/RunSurfaceTabs.svelte';
	import RaceCalendarCard from '#lib/components/RaceCalendarCard.svelte';
	import RaceImportDialog from '#lib/components/RaceImportDialog.svelte';
	import RaceListingEditor from '#lib/components/RaceListingEditor.svelte';
	import Modal from '#lib/components/Modal.svelte';

	let query = $state('');
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
		timer = setTimeout(run, 250);
		return () => clearTimeout(timer);
	});

	let placeTimer: ReturnType<typeof setTimeout> | undefined;
	function onNearPlaceInput() {
		clearTimeout(placeTimer);
		const term = nearPlace.trim();
		if (!term) {
			center = null;
			radiusM = undefined;
			nearLabel = '';
			geoError = '';
			return;
		}
		placeTimer = setTimeout(async () => {
			const { geocodePlace } = await import('#lib/routes/geocoding.ts');
			const place = await geocodePlace(term);
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

	function openImport(race: RaceListingResult) {
		importing = race;
	}

	function onCreated() {
		showEditor = false;
		run();
	}
</script>

<svelte:head><title>{m('races.title')}</title></svelte:head>

<div class="races-page">
	<RunSurfaceTabs active="races" />
	<header class="races-header">
		<div>
			<h1>{m('races.title')}</h1>
			<HelpLink route="/races" />
			<p class="subtitle">{m('races.subtitle')}</p>
		</div>
		<button
			type="button"
			class="btn btn-primary"
			onclick={() => (showEditor = true)}
			data-testid="race-submit"
		>
			{m('races.submitRace')}
		</button>
	</header>

	<div class="filters">
		<div class="toolbar">
			<input
				type="search"
				class="search"
				bind:value={query}
				placeholder={m('races.searchPlaceholder')}
				aria-label={m('races.searchPlaceholder')}
				data-testid="races-search"
				aria-describedby="races-search-hint"
			/>
			<button
				type="button"
				class="filters-toggle"
				class:active={activeCount > 0}
				aria-expanded={filtersOpen}
				aria-controls="races-filters-panel"
				aria-label={activeCount > 0 ? m('races.filtersCount', { count: activeCount }) : m('races.filters')}
				onclick={() => (filtersOpen = !filtersOpen)}
				data-testid="races-filters-toggle"
			>
				<span class="material-symbols" aria-hidden="true">tune</span>
				<span>{m('races.filters')}</span>
				{#if activeCount > 0}
					<span class="filter-count" aria-hidden="true" data-testid="races-filter-count">{activeCount}</span>
				{/if}
			</button>
		</div>

		{#if activeCount > 0}
			<div class="active-filters" data-testid="races-active-filters">
				{#if when === 'recent'}
					<button
						type="button"
						class="chip active removable"
						onclick={() => (when = 'upcoming')}
						aria-label={m('races.removeFilter', { filter: m('races.whenRecent') })}
						data-testid="races-chip-when"
					>
						<span>{m('races.whenRecent')}</span>
						<span class="material-symbols" aria-hidden="true">close</span>
					</button>
				{/if}
				{#if distanceLabel}
					<button
						type="button"
						class="chip active removable"
						onclick={() => (distance = '')}
						aria-label={m('races.removeFilter', { filter: distanceLabel })}
						data-testid="races-chip-distance"
					>
						<span>{distanceLabel}</span>
						<span class="material-symbols" aria-hidden="true">close</span>
					</button>
				{/if}
				{#if nearLabel}
					<button
						type="button"
						class="chip active removable"
						onclick={clearNear}
						aria-label={m('races.removeFilter', { filter: `${m('discover.nearLabel')}: ${nearLabel}` })}
						data-testid="races-near-clear"
					>
						<span>{m('discover.nearLabel')}: {nearLabel}</span>
						<span class="material-symbols" aria-hidden="true">close</span>
					</button>
				{/if}
			</div>
		{/if}
		{#if geoError}
			<p class="near-error" role="status">{geoError}</p>
		{/if}

		<!-- `hidden`, not {#if}: the search field's description lives in here,
		     and aria-describedby still resolves against a hidden element. -->
		<div class="filters-panel" id="races-filters-panel" hidden={!filtersOpen} data-testid="races-filters-panel">
			<p class="filter-hint" id="races-search-hint">{m('races.searchHint')}</p>

			<div class="near-row">
				<input
					type="search"
					class="search near-input"
					bind:value={nearPlace}
					oninput={onNearPlaceInput}
					placeholder={m('races.nearPlace')}
					aria-label={m('races.nearPlace')}
					data-testid="races-near"
					aria-describedby="races-near-hint"
				/>
				<button type="button" class="chip near-locate" onclick={useMyLocation} data-testid="races-use-location">
					{m('discover.useMyLocation')}
				</button>
			</div>
			<p class="filter-hint" id="races-near-hint">{m('races.nearPlaceHint')}</p>

			<div
				class="chip-row"
				role="group"
				aria-label={m('races.whenGroup')}
				aria-describedby="races-when-hint"
			>
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

			<div
				class="chip-row"
				role="group"
				aria-label={m('races.distanceAny')}
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
		</div>
	</div>

	{#if loading}
		<p class="state-msg">{m('races.loading')}</p>
	{:else if error}
		<div class="races-error" role="alert" data-testid="races-error">
			<span>{m('races.searchFailed')}</span>
			<button type="button" class="btn btn-outline" onclick={run}>{m('races.retry')}</button>
		</div>
	{:else if results.length === 0}
		<p class="state-msg" data-testid="races-empty">
			{when === 'recent' ? m('races.emptyRecent', { days: RECENT_WINDOW_DAYS }) : m('races.empty')}
		</p>
	{:else}
		<ul class="results" data-testid="races-results">
			{#each results as r (r.id)}
				<RaceCalendarCard race={r} onimport={openImport} />
			{/each}
		</ul>
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
	.races-header {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
	}
	.subtitle {
		color: var(--color-text-secondary);
		margin: 0.25rem 0 0;
	}
	.filters {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.toolbar {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		align-items: stretch;
	}
	.toolbar .search {
		flex: 1 1 10rem;
		min-width: 0;
		width: auto;
	}
	.search {
		width: 100%;
		min-height: var(--tap-target-min);
		padding: 0.6rem 0.85rem;
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.95rem;
	}
	.filters-toggle {
		appearance: none;
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		min-height: var(--tap-target-min);
		min-width: var(--tap-target-min);
		padding: 0 0.85rem;
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.9rem;
		font-weight: 600;
		cursor: pointer;
		white-space: nowrap;
	}
	.filters-toggle.active {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.filters-toggle .material-symbols {
		font-size: 1.25rem;
	}
	.filter-count {
		min-width: 1.4rem;
		padding: 0 0.35rem;
		border-radius: 999px;
		background: var(--color-primary);
		color: var(--color-on-primary);
		font-size: 0.8rem;
		line-height: 1.4rem;
		text-align: center;
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
	.filters-panel:not([hidden]) {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		padding: var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
	}
	.near-row {
		display: flex;
		gap: 0.4rem;
		align-items: stretch;
		flex-wrap: wrap;
	}
	.near-input {
		flex: 1 1 12rem;
		min-width: 0;
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
	.filter-hint {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		line-height: 1.45;
		margin: calc(var(--space-md) * -1 + 0.25rem) 0 0;
	}
	.filters-panel > .filter-hint:first-child {
		margin-top: 0;
	}
</style>
