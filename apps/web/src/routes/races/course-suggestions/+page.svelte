<script lang="ts">
	// The course-suggestion review queue (issue #1297, decisions § 2396): every
	// race with a pending suggestion the runner may review, including races
	// nobody has claimed, which a verified club's admin claims here and then
	// reviews in place. The RPCs are the gate; RaceCourseTools does the work.
	import { onMount } from 'svelte';
	import RaceCourseTools from '#lib/components/RaceCourseTools.svelte';
	import RunSurfaceTabs from '#lib/components/RunSurfaceTabs.svelte';
	import {
		fetchMyClubsWithError,
		fetchRaceCourseReviewQueue,
		fetchRaceListings,
		type RaceCourseReviewQueueItem,
		type RaceListingDetail
	} from '#lib/core/data.ts';
	import { formatDate } from '#lib/format/time.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { organiserClubsOf, type OrganiserClubCandidate } from '#lib/integrations/race_course_access.ts';

	let loading = $state(true);
	let failed = $state(false);
	let clubs = $state<OrganiserClubCandidate[]>([]);
	let queue = $state<RaceCourseReviewQueueItem[]>([]);
	let races = $state<RaceListingDetail[]>([]);

	const rows = $derived(
		queue.flatMap((item) => {
			const race = races.find((r) => r.id === item.listingId);
			return race ? [{ item, race }] : [];
		})
	);

	async function load(showLoading: boolean) {
		if (showLoading) loading = true;
		failed = false;
		try {
			const [clubRead, items] = await Promise.all([
				fetchMyClubsWithError(),
				fetchRaceCourseReviewQueue()
			]);
			if (clubRead.error) {
				console.error('course suggestion queue: club read failed', clubRead.error);
				failed = true;
				return;
			}
			const details = await fetchRaceListings(items.map((i) => i.listingId));
			clubs = organiserClubsOf(clubRead.clubs);
			queue = items;
			races = details;
		} catch (e) {
			console.error('course suggestion queue load failed', e);
			failed = true;
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		void load(true);
	});
</script>

<svelte:head><title>{m('raceCourse.queueTitle')}</title></svelte:head>

<div class="queue-page">
	<RunSurfaceTabs active="races" />
	<header>
		<a class="back" href="/races">{m('raceCourse.queueBack')}</a>
		<h1>{m('raceCourse.queueTitle')}</h1>
		<p class="subtitle">{m('raceCourse.queueSubtitle')}</p>
	</header>

	{#if loading}
		<p class="state-msg">{m('raceCourse.queueLoading')}</p>
	{:else if failed}
		<div class="queue-error" role="alert" data-testid="race-course-queue-error">
			<span>{m('raceCourse.queueLoadFailed')}</span>
			<button type="button" class="btn btn-outline" onclick={() => void load(true)}>
				{m('races.retry')}
			</button>
		</div>
	{:else if clubs.length === 0}
		<p class="state-msg" data-testid="race-course-queue-not-publisher">
			{m('raceCourse.queueNotPublisher')}
		</p>
	{:else if rows.length === 0}
		<p class="state-msg" data-testid="race-course-queue-empty">{m('raceCourse.queueEmpty')}</p>
	{:else}
		<ul class="queue-list" data-testid="race-course-queue">
			{#each rows as { item, race } (item.listingId)}
				<li class="card queue-item" data-testid="race-course-queue-item">
					<div class="race-head">
						<a class="race-name" href="/races/{race.id}">{race.name}</a>
						<span class="race-meta">
							{formatDate(race.race_date)} ·
							{race.organiser ? race.organiser.name : m('raceCourse.queueUnclaimed')} ·
							{m('raceCourse.queuePending', { n: item.pendingCount })}
						</span>
					</div>
					<RaceCourseTools
						{race}
						signedIn={true}
						allowSuggest={false}
						organiserClubs={clubs}
						onchanged={() => void load(false)}
					/>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.queue-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	header h1 {
		margin: var(--space-xs) 0 0;
	}
	.back {
		font-size: 0.9rem;
	}
	.subtitle {
		color: var(--color-text-secondary);
		margin: 0.25rem 0 0;
	}
	.state-msg {
		color: var(--color-text-secondary);
	}
	.queue-error {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-md);
		color: var(--color-danger-text);
	}
	.queue-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.queue-item {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.race-head {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.race-name {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.race-meta {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
</style>
