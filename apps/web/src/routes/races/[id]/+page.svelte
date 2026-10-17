<script lang="ts">
	import { formatDistance } from '#lib/format/units.svelte.ts';
	import { formatDate, formatDuration } from '#lib/format/time.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { racePlanPreset } from '#lib/training/race_plan_preset.ts';
	import { todayISO } from '#lib/training/training.ts';
	import {
		fetchRaceListing,
		fetchMyRunsAtRace,
		fetchRaceListingPhotos,
		type RaceListingDetail,
		type RaceListingRun,
		type RaceListingPhoto
	} from '#lib/core/data.ts';
	import { raceSourceLabel } from '#lib/integrations/race_source.ts';
	import { buildRaceShareCanonical } from '#lib/share/share_race_meta.ts';
	import RaceImportDialog from '#lib/components/RaceImportDialog.svelte';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { safeHref } from '#lib/util/html_escape.ts';
	import { safeImageSrc } from '#lib/util/safe_image_src.ts';

	let { data } = $props();

	let race = $state<RaceListingDetail | null>(null);
	let loading = $state(true);
	let loadFailed = $state(false);
	let runs = $state<RaceListingRun[]>([]);
	let runsFailed = $state(false);
	let photos = $state<RaceListingPhoto[]>([]);
	let importing = $state<RaceListingDetail | null>(null);

	async function load() {
		const id = data.id;
		loading = true;
		loadFailed = false;
		let next: RaceListingDetail | null = null;
		let failed = false;
		try {
			next = await fetchRaceListing(id);
		} catch (e) {
			console.error('fetchRaceListing failed', e);
			failed = true;
		}
		// Moving to another race (or a retry) while this read was in flight
		// started a newer load; only the newest may write the page.
		if (id !== data.id) return;
		race = next;
		loadFailed = failed;
		loading = false;
		if (race) {
			void loadRuns(id);
			// Auxiliary: an empty gallery is hidden, never shown as an error.
			void fetchRaceListingPhotos(id).then((p) => {
				if (race?.id === id) photos = p;
			});
		}
	}

	async function loadRuns(id: string) {
		runsFailed = false;
		try {
			const rows = await fetchMyRunsAtRace(id);
			if (race?.id === id) runs = rows;
		} catch (e) {
			console.error('fetchMyRunsAtRace failed', e);
			if (race?.id === id) runsFailed = true;
		}
	}

	$effect(() => {
		void data.id;
		race = null;
		runs = [];
		photos = [];
		void load();
	});

	// A result exists only from race day on; before that the page says when
	// the import opens instead of offering one that can only come back empty.
	let canImport = $derived(race != null && race.race_date <= todayISO());

	let planHref = $derived.by(() => {
		if (!race) return null;
		const preset = racePlanPreset({
			raceDateIso: race.race_date,
			distanceM: race.distance_m,
			todayIso: todayISO()
		});
		if (!preset.ok) return null;
		const q = new URLSearchParams({
			type: 'training',
			raceDate: race.race_date,
			raceName: race.name
		});
		if (race.distance_m != null) q.set('raceDistance', String(race.distance_m));
		return `/plans/new?${q}`;
	});

	let entryHref = $derived(race?.entry_url ? safeHref(race.entry_url) : null);
	let resultsHref = $derived(race?.results_url ? safeHref(race.results_url) : null);

	async function share() {
		if (!race) return;
		const url = buildRaceShareCanonical(location.origin, race.id);
		try {
			if (navigator.share) {
				await navigator.share({ title: race.name, url });
			} else {
				await navigator.clipboard.writeText(url);
				showToast(m('races.detailLinkCopied'), 'success');
			}
		} catch (e) {
			// Dismissing the share sheet rejects with AbortError; that is not a failure.
			if (e instanceof DOMException && e.name === 'AbortError') return;
			console.error('race share failed', e);
			showToast(m('races.detailShareFailed'), 'error');
		}
	}
</script>

<svelte:head>
	<title>{race?.name ?? m('races.title')}</title>
</svelte:head>

<main class="race-page" id="main-content">
	<a class="back" href="/races" data-testid="race-detail-back">{m('races.detailBack')}</a>

	{#if loading}
		<p class="state">{m('races.loading')}</p>
	{:else if loadFailed}
		<div class="state load-error" role="alert" data-testid="race-detail-error">
			<span>{m('races.detailLoadFailed')}</span>
			<button type="button" class="btn btn-outline" onclick={() => void load()}>
				{m('races.retry')}
			</button>
		</div>
	{:else if !race}
		<p class="state" data-testid="race-detail-not-found">{m('races.detailNotFound')}</p>
	{:else}
		<header class="race-header">
			<h1 data-testid="race-detail-name">{race.name}</h1>
			<p class="meta">
				{formatDate(race.race_date)}
				{#if race.distance_m}· {formatDistance(race.distance_m)}{/if}
				{#if race.location_label}· {race.location_label}{/if}
			</p>
			<p class="source" data-testid="race-detail-source">{raceSourceLabel(race.provider)}</p>
			{#if !race.is_verified}
				<span class="unverified">{m('races.unverified')}</span>
			{/if}
		</header>

		<div class="actions">
			{#if planHref}
				<a class="btn btn-outline" href={planHref} data-testid="race-detail-train">
					{m('races.trainForThis')}
				</a>
			{/if}
			{#if entryHref && entryHref !== '#'}
				<a
					class="btn btn-outline"
					href={entryHref}
					target="_blank"
					rel="noopener noreferrer"
					data-testid="race-detail-register"
				>
					{m('races.register')}
				</a>
			{/if}
			{#if resultsHref && resultsHref !== '#'}
				<a
					class="btn btn-outline"
					href={resultsHref}
					target="_blank"
					rel="noopener noreferrer"
					data-testid="race-detail-results"
				>
					{m('races.viewResults')}
				</a>
			{/if}
			<button type="button" class="btn btn-outline" onclick={share} data-testid="race-detail-share">
				{m('races.detailShare')}
			</button>
			{#if canImport}
				<button
					type="button"
					class="btn btn-primary"
					onclick={() => (importing = race)}
					data-testid="race-detail-import"
				>
					{m('races.importResult')}
				</button>
			{/if}
		</div>
		{#if !canImport}
			<p class="hint" data-testid="race-detail-import-later">
				{m('races.detailImportAfterRace', { date: formatDate(race.race_date) })}
			</p>
		{/if}

		<section class="section" aria-labelledby="race-runs-heading">
			<h2 id="race-runs-heading">{m('races.detailYourRuns')}</h2>
			{#if runsFailed}
				<div class="state load-error" role="alert" data-testid="race-detail-runs-error">
					<span>{m('races.detailRunsFailed')}</span>
					<button type="button" class="btn btn-outline" onclick={() => race && void loadRuns(race.id)}>
						{m('races.retry')}
					</button>
				</div>
			{:else if runs.length === 0}
				<p class="hint" data-testid="race-detail-no-runs">{m('races.detailNoRuns')}</p>
			{:else}
				<ul class="runs" data-testid="race-detail-runs">
					{#each runs as r (r.id)}
						<li>
							<a class="card-elevated run" href="/runs/{r.id}">
								<span>{formatDate(r.started_at.slice(0, 10))}</span>
								<span class="run-meta">
									{formatDistance(r.distance_m)} · {r.chip_time
										? `${m('races.chipTime')} ${r.chip_time}`
										: formatDuration(r.duration_s)}
								</span>
							</a>
						</li>
					{/each}
				</ul>
			{/if}
		</section>

		{#if photos.length > 0}
			<section class="section" aria-labelledby="race-photos-heading" data-testid="race-detail-photos">
				<h2 id="race-photos-heading">{m('shareRace.photosHeading')}</h2>
				<div class="photo-grid">
					{#each photos as p (p.id)}
						<figure class="photo">
							<img src={safeImageSrc(p.thumbUrl)} alt={p.caption ?? ''} loading="lazy" />
							{#if p.caption || p.displayName}
								<figcaption>
									{#if p.caption}<span>{p.caption}</span>{/if}
									{#if p.displayName}
										<span class="by">{m('shareRace.photoBy', { name: p.displayName })}</span>
									{/if}
								</figcaption>
							{/if}
						</figure>
					{/each}
				</div>
			</section>
		{/if}
	{/if}
</main>

<RaceImportDialog
	race={importing}
	onclose={() => (importing = null)}
	onimported={() => race && void loadRuns(race.id)}
/>

<style>
	.race-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 56rem;
	}
	.back {
		align-self: flex-start;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.race-header h1 {
		margin: 0;
	}
	.meta {
		margin: 0.35rem 0 0;
		color: var(--color-text-secondary);
	}
	.source {
		margin: 0.25rem 0 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.unverified {
		display: inline-block;
		margin-top: 0.4rem;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.hint,
	.state {
		color: var(--color-text-secondary);
		margin: 0;
	}
	.load-error {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		color: var(--color-danger-text);
	}
	.section {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.section h2 {
		font-size: 1.1rem;
		margin: 0;
	}
	.runs {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.run {
		display: flex;
		justify-content: space-between;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		color: var(--color-text);
		text-decoration: none;
	}
	.run-meta {
		color: var(--color-text-secondary);
	}
	.photo-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(10rem, 1fr));
		gap: var(--space-sm);
	}
	.photo {
		margin: 0;
	}
	.photo img {
		width: 100%;
		aspect-ratio: 1;
		object-fit: cover;
		border-radius: var(--radius-md);
	}
	.photo figcaption {
		display: flex;
		flex-direction: column;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
</style>
