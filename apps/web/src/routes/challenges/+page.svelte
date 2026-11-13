<script lang="ts">
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { fetchChallenges, browsePublicChallenges } from '#lib/core/data.ts';
	import type { ChallengeWithMeta } from '#lib/types.ts';
	import ChallengeEditor from '#lib/components/ChallengeEditor.svelte';
	import OfficialBadge from '#lib/components/OfficialBadge.svelte';
	import ChallengeProgressBar from '#lib/components/ChallengeProgressBar.svelte';
	import { myProgressView } from '#lib/social/challenge_list.ts';
	import Modal from '#lib/components/Modal.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { goto } from '$app/navigation';
	import { smartBack } from '#lib/util/smart_back.ts';

	const back = smartBack();
	const BROWSE_PAGE = 24;

	// My challenges = the ones I've joined. Browse = the ranked, server-paginated
	// public feed of ones I haven't (popularity-ordered in browse_public_challenges).
	let mine = $state<ChallengeWithMeta[] | null>(null);
	let mineError = $state<string | null>(null);
	// Stamped when the list lands so every row grades its window against one
	// instant, instead of each render sampling a slightly different clock.
	let mineAt = $state(Date.now());
	let browse = $state<ChallengeWithMeta[] | null>(null);
	let creating = $state(false);
	let search = $state('');
	let browseOffset = $state(0);
	let browseDone = $state(false);
	let browseLoading = $state(false);
	let browseError = $state<string | null>(null);
	let activeSearch = $state('');
	// Latest-wins sequencing for Browse, matching SocialPeople/SocialClubs: a
	// newer search must invalidate an older response, never be refused by it.
	let browseGen = 0;

	// A load *failure* is kept distinct from the genuinely-empty state so a
	// broken fetch surfaces an error + retry instead of masquerading as
	// "you're in no challenges" (issue #357).
	async function loadMine() {
		mineError = null;
		try {
			mine = await fetchChallenges({ mine: true });
			mineAt = Date.now();
		} catch (e) {
			mineError = errorCopy(e, m, 'challenges: mineError');
		}
	}

	async function loadBrowse(reset: boolean, term: string) {
		// Only the append path (Load more) may be refused while one is in
		// flight; refusing a *new search* would leave the list showing an
		// older term's results — and `activeSearch` pointing at that older
		// term, so the next Load more would page a query the box no longer
		// shows. A new search supersedes instead.
		if (!reset && browseLoading) return;
		const gen = ++browseGen;
		browseLoading = true;
		browseError = null;
		const offset = reset ? 0 : browseOffset;
		try {
			const rows = await browsePublicChallenges({ search: term, limit: BROWSE_PAGE, offset });
			if (gen !== browseGen) return;
			browse = reset ? rows : [...(browse ?? []), ...rows];
			browseOffset = offset + rows.length;
			browseDone = rows.length < BROWSE_PAGE;
			activeSearch = term;
		} catch (e) {
			if (gen !== browseGen) return;
			// Same reasoning as `mine` above: a failed browse must not render
			// as "no public challenges to join", which is a different fact.
			browseError = errorCopy(e, m, 'challenges: browseError');
			if (reset) browse = [];
			browseDone = true;
		} finally {
			if (gen === browseGen) browseLoading = false;
		}
	}

	$effect(() => {
		loadMine();
	});

	// Debounced search → reset Browse. Tracks `search`, so it also runs once on
	// mount with the empty term to load the first page.
	$effect(() => {
		const term = search.trim();
		const t = setTimeout(() => loadBrowse(true, term), 200);
		return () => clearTimeout(t);
	});

	function metricLabel(metricKey: ChallengeWithMeta['metric']): string {
		switch (metricKey) {
			case 'distance':
				return m('challenges.metricDistance');
			case 'duration':
				return m('challenges.metricDuration');
			case 'vert':
				return m('challenges.metricVert');
			case 'activity_count':
				return m('challenges.metricActivityCount');
			case 'streak_days':
				return m('challenges.metricStreak');
			case 'park_courses':
				return m('challenges.metricParkCourses');
		}
	}

	const METRIC_ICON: Record<ChallengeWithMeta['metric'], string> = {
		distance: 'straighten',
		duration: 'timer',
		vert: 'terrain',
		activity_count: 'format_list_numbered',
		streak_days: 'local_fire_department',
		park_courses: 'park'
	};
</script>

<svelte:head>
	<title>{m('challenges.title')}</title>
</svelte:head>

<div class="page">
	<PageHeader
		flush
		back={{ href: '/social?tab=challenges', label: m('challenges.back'), onclick: back.handle }}
		title={m('challenges.title')}
		subtitle={m('challenges.tagline')}
	>
		{#snippet actions()}
			<button type="button" class="btn btn-primary" onclick={() => (creating = true)}>
				{m('challenges.create')}
			</button>
		{/snippet}
	</PageHeader>

	<section>
		<h2>{m('challenges.myChallenges')}</h2>
		{#if mineError !== null}
			<div class="error-banner" role="alert">
				<span class="material-symbols" aria-hidden="true">error</span>
				<div>
					<strong>{m('challenges.loadFailed')}</strong>
					{#if mineError}<span class="error-detail">{mineError}</span>{/if}
				</div>
				<button class="btn btn-outline btn-sm" onclick={loadMine}>{m('plansPage.retry')}</button>
			</div>
		{:else if mine === null}
			<p class="muted">…</p>
		{:else if mine.length === 0}
			<EmptyState icon="trophy" headingLevel={3} title={m('challenges.empty')} />
		{:else}
			<ul class="list">
				{#each mine as c (c.id)}
					{@const progress = myProgressView(c, mineAt)}
					<li class="card-elevated">
						<a href={`/challenges/${c.id}`}>
							<div class="row-top">
								<span class="title">{c.title}{#if c.is_official}<OfficialBadge />{/if}</span>
								<span class="badge">
									<span class="material-symbols" aria-hidden="true">{METRIC_ICON[c.metric]}</span>
									{metricLabel(c.metric)}
								</span>
							</div>
							{#if progress.state === 'unknown'}
								<span class="meta" data-testid="challenge-progress-unavailable">
									{m('challenges.progressUnavailable')}
								</span>
							{:else}
								<ChallengeProgressBar
									metric={c.metric}
									value={progress.value}
									goal={c.goal_value}
									startsAt={c.starts_at}
									endsAt={c.ends_at}
								/>
							{/if}
							<div class="meta-row">
								<span class="meta">
									<span class="material-symbols" aria-hidden="true">group</span>
									{m('challenges.participants', { n: c.participant_count })}
								</span>
								{#if c.my_rank !== null}
									<span class="rank" data-testid="challenge-my-rank">
										{m('challenges.leaderboardRank', { rank: c.my_rank })}
									</span>
								{/if}
								{#if c.completed_at}
									<span class="earned">
										<span class="material-symbols" aria-hidden="true">military_tech</span>
										{m('challenges.badgeEarned')}
									</span>
								{/if}
							</div>
						</a>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<section>
		<div class="browse-head">
			<h2>{m('challenges.browse')}</h2>
			<div class="search">
				<AppSearchField bind:value={search} label={m('challenges.searchPlaceholder')} />
			</div>
		</div>
		{#if browseError !== null}
			<div class="error-banner" role="alert">
				<span class="material-symbols" aria-hidden="true">error</span>
				<div>
					<strong>{m('challenges.loadFailed')}</strong>
					{#if browseError}<span class="error-detail">{browseError}</span>{/if}
				</div>
				<button class="btn btn-outline btn-sm" onclick={() => loadBrowse(true, search.trim())}>
					{m('plansPage.retry')}
				</button>
			</div>
		{:else if browse === null}
			<p class="muted">…</p>
		{:else if browse.length === 0}
			<EmptyState icon="search" headingLevel={3} title={m('challenges.browseEmpty')} />
		{:else}
			<ul class="list">
				{#each browse as c (c.id)}
					<li class="card-elevated">
						<a href={`/challenges/${c.id}`}>
							<div class="row-top">
								<span class="title">{c.title}{#if c.is_official}<OfficialBadge />{/if}</span>
								<span class="badge">
									<span class="material-symbols" aria-hidden="true">{METRIC_ICON[c.metric]}</span>
									{metricLabel(c.metric)}
								</span>
							</div>
							<span class="meta">
								<span class="material-symbols" aria-hidden="true">group</span>
								{m('challenges.participants', { n: c.participant_count })}
							</span>
						</a>
					</li>
				{/each}
			</ul>
			{#if !browseDone}
				<div class="load-more">
					<button
						type="button"
						class="btn btn-secondary"
						disabled={browseLoading}
						onclick={() => loadBrowse(false, activeSearch)}
					>
						{m('challenges.loadMore')}
					</button>
				</div>
			{/if}
		{/if}
	</section>
</div>

<Modal open={creating} onclose={() => (creating = false)} title={m('challenges.create')}>
	<ChallengeEditor
		oncreated={(ch) => {
			creating = false;
			goto(`/challenges/${ch.id}`);
		}}
		oncancel={() => (creating = false)}
	/>
</Modal>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	section {
		margin-top: var(--space-xl);
	}
	h2 {
		font-size: 1.1rem;
		margin: 0 0 var(--space-md);
	}
	.browse-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		flex-wrap: wrap;
		margin-bottom: var(--space-md);
	}
	.browse-head h2 {
		margin: 0;
	}
	.search {
		display: flex;
		min-width: min(16rem, 100%);
	}
	.load-more {
		display: flex;
		justify-content: center;
		margin-top: var(--space-lg);
	}
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(18rem, 100%), 1fr));
		gap: var(--space-md);
	}
	.list li {
		transition: transform var(--transition-fast),
			box-shadow var(--transition-fast);
	}
	.list li:hover {
		transform: translateY(-2px);
	}
	.list li a {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-lg);
		text-decoration: none;
		color: inherit;
	}
	.row-top {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-2xs) var(--space-sm);
	}
	.title {
		font-weight: 600;
		line-height: 1.3;
	}
	.badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		flex-shrink: 0;
		font-size: 0.75rem;
		font-weight: 600;
		padding: 0.15rem 0.55rem;
		border-radius: 999px;
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.badge .material-symbols {
		font-size: 0.95rem;
		width: 0.95rem;
		height: 0.95rem;
	}
	.meta-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-2xs) var(--space-sm);
	}
	.meta {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.rank {
		padding: 0.05rem 0.45rem;
		border-radius: 999px;
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-size: 0.78rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.earned {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		padding: 0.05rem 0.45rem;
		border-radius: 999px;
		background: var(--color-success-light);
		color: var(--color-success-text);
		font-size: 0.78rem;
		font-weight: 600;
	}
	.earned .material-symbols {
		font-size: 0.95rem;
		width: 0.95rem;
		height: 0.95rem;
	}
	.meta .material-symbols {
		font-size: 1rem;
		width: 1rem;
		height: 1rem;
		color: var(--color-text-tertiary);
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
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
</style>
