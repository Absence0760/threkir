<script lang="ts">
	import { onMount } from 'svelte';
	import Avatar from '#lib/components/Avatar.svelte';
	import SkeletonBlock from '#lib/components/SkeletonBlock.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import { hashHue } from '#lib/format/avatar.ts';
	import {
		searchPeople,
		fetchSuggestedPeople,
		fetchNearbyRunners,
		followUser,
		unfollowUser,
		type PeopleSuggestion,
		type NearbyRunner,
	} from '#lib/core/data.ts';
	import { NEARBY_RUNNERS_ENABLED } from '#lib/social/nearby_flag.ts';
	import { NEARBY_BUCKET_BOUNDS_M, nearbyBucketUpperBoundM } from '#lib/social/nearby.ts';
	import { formatDistance } from '#lib/format/units.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';

	let query = $state('');
	let results = $state<PeopleSuggestion[]>([]);
	let suggestions = $state<PeopleSuggestion[]>([]);
	let nearby = $state<NearbyRunner[]>([]);
	let loadingNearby = $state(NEARBY_RUNNERS_ENABLED);
	let searching = $state(false);
	let loadingSuggestions = $state(true);
	let rowBusy = $state<Set<string>>(new Set());

	function bucketLabel(bucket: number): string {
		const bound = nearbyBucketUpperBoundM(bucket);
		return bound == null
			? m('socialNearby.beyond', {
					d: formatDistance(NEARBY_BUCKET_BOUNDS_M[NEARBY_BUCKET_BOUNDS_M.length - 1]),
				})
			: m('socialNearby.within', { d: formatDistance(bound) });
	}

	let searchTimer: ReturnType<typeof setTimeout> | null = null;
	let searchGen = 0;

	let hasQuery = $derived(query.trim().length > 0);
	let visible = $derived(hasQuery ? results : suggestions);

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		try {
			suggestions = await fetchSuggestedPeople(12);
		} finally {
			loadingSuggestions = false;
		}
		// Opt-in "runners nearby" — only when the surface flag is on (default
		// off pending owner + CISO/counsel sign-off). Inert otherwise.
		if (NEARBY_RUNNERS_ENABLED) {
			try {
				nearby = await fetchNearbyRunners();
			} finally {
				loadingNearby = false;
			}
		}
	});

	function onSearchInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(runSearch, 300);
	}

	async function runSearch() {
		const term = query.trim();
		const gen = ++searchGen;
		if (!term) {
			results = [];
			searching = false;
			return;
		}
		searching = true;
		try {
			const next = await searchPeople(term, 20);
			if (gen !== searchGen) return;
			results = next;
		} catch (e) {
			// Without this catch, a network error during search left
			// the user looking at an empty results list with no
			// feedback. Surface the failure so they know to retry.
			if (gen === searchGen) {
				showToast(m('socialPeople.searchFailed', { error: errorCopy(e, m, 'socialPeople.searchFailed') }), 'error');
			}
		} finally {
			if (gen === searchGen) searching = false;
		}
	}

	function clearSearch() {
		query = '';
		results = [];
		searchGen++;
	}

	async function toggleFollow(
		target: { id: string; viewer_follows: boolean; display_name: string | null },
		e: MouseEvent
	) {
		e.preventDefault();
		e.stopPropagation();
		if (!auth.loggedIn || rowBusy.has(target.id)) return;
		const wasFollowing = target.viewer_follows;
		rowBusy = new Set([...rowBusy, target.id]);
		// Optimistic flip across both result + suggestion lists.
		flipFollow(target.id, !wasFollowing);
		try {
			if (wasFollowing) await unfollowUser(target.id);
			else if ((await followUser(target.id)) === 'requested') {
				// A private profile: a request went out, nothing is followed yet.
				flipFollow(target.id, false);
				showToast(m('socialPeople.requestSent'), 'success');
			}
		} catch (err) {
			flipFollow(target.id, wasFollowing);
			showToast(m('socialPeople.followFailed', { error: errorCopy(err, m, 'socialPeople.followFailed') }), 'error');
		} finally {
			const next = new Set(rowBusy);
			next.delete(target.id);
			rowBusy = next;
		}
	}

	function flipFollow(id: string, viewer_follows: boolean) {
		results = results.map((r) => (r.id === id ? { ...r, viewer_follows } : r));
		suggestions = suggestions.map((r) => (r.id === id ? { ...r, viewer_follows } : r));
		nearby = nearby.map((r) => (r.id === id ? { ...r, viewer_follows } : r));
	}


</script>

<div class="people">
	<div class="search-wrap">
		<AppSearchField
			bind:value={query}
			label={m('socialPeople.searchAriaLabel')}
			placeholder={m('socialPeople.searchPlaceholder')}
			clearLabel={m('socialPeople.clearSearch')}
			testid="people-search"
			oninput={(v) => (v === '' ? clearSearch() : onSearchInput())}
		/>
	</div>

	{#if hasQuery}
		<h2 class="section-title">{m('socialPeople.searchResults')}</h2>
		{#if searching}
			<p class="muted" role="status">{m('socialPeople.searching')}</p>
		{:else if results.length === 0}
			<EmptyState
				icon="search_off"
				headingLevel={3}
				title={m('socialPeople.noMatch', { query: query.trim() })}
				text={m('socialPeople.noMatchHelp')}
			/>
		{/if}
	{:else}
		<h2 class="section-title">{m('socialPeople.suggestedForYou')}</h2>
		{#if loadingSuggestions}
			<div class="grid" aria-hidden="true">
				{#each Array(4) as _, i (i)}
					<div class="skel-row">
						<SkeletonBlock height="2.5rem" width="2.5rem" radius="50%" />
						<div class="skel-row-body">
							<SkeletonBlock height="0.75rem" width="60%" />
							<SkeletonBlock height="0.75rem" width="40%" />
						</div>
						<SkeletonBlock height="1.75rem" width="5.5rem" radius="999px" />
					</div>
				{/each}
			</div>
			<p class="visually-hidden" role="status">{m('socialPeople.loadingSuggestions')}</p>
		{:else if suggestions.length === 0}
			<EmptyState
				icon="groups"
				headingLevel={3}
				title={m('socialPeople.noSuggestions')}
				text={m('socialPeople.noSuggestionsHelp')}
			>
				{#snippet actions()}
					<a class="btn btn-primary" href="/social?tab=clubs">
						<span class="material-symbols" aria-hidden="true">groups</span>
						{m('socialPeople.browseClubs')}
					</a>
				{/snippet}
			</EmptyState>
		{/if}
	{/if}

	{#if visible.length > 0}
		<div class="grid">
			{#each visible as person (person.id)}
				<a class="person-row" href="/u/{person.id}">
					<Avatar
						url={person.avatar_url}
						name={person.display_name}
						size="2.5rem"
						font="1.05rem"
						bg="seed"
						seedHue={hashHue(person.id)}
					/>
					<div class="person-body">
						<span class="person-name">{person.display_name ?? m('socialPeople.runnerFallback')}</span>
						{#if person.handle}
							<span class="person-handle">@{person.handle}</span>
						{/if}
						<span class="person-meta">
							{m('socialPeople.publicRuns', { n: person.public_runs_count })}
							{#if person.shared_clubs > 0}
								<span class="dot">·</span>
								{m('socialPeople.sharedClubs', { n: person.shared_clubs })}
							{/if}
						</span>
					</div>
					{#if auth.loggedIn}
						<button
							type="button"
							class="follow-btn"
							class:following={person.viewer_follows}
							disabled={rowBusy.has(person.id)}
							onclick={(e) => toggleFollow(person, e)}
							aria-label={person.viewer_follows
								? m('socialPeople.unfollowName', { name: person.display_name ?? m('socialPeople.runnerFallbackLower') })
								: m('socialPeople.followName', { name: person.display_name ?? m('socialPeople.runnerFallbackLower') })}
						>
							<span class="material-symbols" aria-hidden="true">
								{person.viewer_follows ? 'check' : 'person_add'}
							</span>
							<span class="follow-label">
								{person.viewer_follows ? m('socialPeople.following') : m('socialPeople.follow')}
							</span>
						</button>
					{/if}
				</a>
			{/each}
		</div>
	{/if}

	{#if NEARBY_RUNNERS_ENABLED && !hasQuery}
		<section class="nearby" aria-labelledby="nearby-heading">
			<h2 class="section-title" id="nearby-heading">{m('socialNearby.heading')}</h2>
			<p class="muted nearby-subtitle">{m('socialNearby.subtitle')}</p>
			{#if loadingNearby}
				<p class="muted" role="status">{m('socialNearby.loading')}</p>
			{:else if nearby.length === 0}
				<EmptyState
					icon="near_me"
					headingLevel={3}
					title={m('socialNearby.empty')}
					text={m('socialNearby.emptyHelp')}
				>
					{#snippet actions()}
						<a class="btn btn-outline" href="/settings/privacy">
							<span class="material-symbols" aria-hidden="true">settings</span>
							{m('shell.settings')}
						</a>
					{/snippet}
				</EmptyState>
			{:else}
				<div class="grid">
					{#each nearby as person (person.id)}
						<a class="person-row" href="/u/{person.id}">
							<Avatar
								url={person.avatar_url}
								name={person.display_name}
								size="2.5rem"
								font="1.05rem"
								bg="seed"
								seedHue={hashHue(person.id)}
							/>
							<div class="person-body">
								<span class="person-name">{person.display_name ?? m('socialPeople.runnerFallback')}</span>
								<span class="person-meta">{bucketLabel(person.bucket)}</span>
							</div>
							{#if auth.loggedIn}
								<button
									type="button"
									class="follow-btn"
									class:following={person.viewer_follows}
									disabled={rowBusy.has(person.id)}
									onclick={(e) => toggleFollow(person, e)}
									aria-label={person.viewer_follows
										? m('socialPeople.unfollowName', { name: person.display_name ?? m('socialPeople.runnerFallbackLower') })
										: m('socialPeople.followName', { name: person.display_name ?? m('socialPeople.runnerFallbackLower') })}
								>
									<span class="material-symbols" aria-hidden="true">
										{person.viewer_follows ? 'check' : 'person_add'}
									</span>
									<span class="follow-label">
										{person.viewer_follows ? m('socialPeople.following') : m('socialPeople.follow')}
									</span>
								</button>
							{/if}
						</a>
					{/each}
				</div>
			{/if}
		</section>
	{/if}
</div>

<style>
	.nearby {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-top: var(--space-md);
	}
	.nearby-subtitle {
		margin: 0;
		font-size: 0.85rem;
	}
	.people {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.search-wrap {
		display: flex;
		max-width: 32rem;
	}
	.section-title {
		font-size: 0.95rem;
		font-weight: 700;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		margin: var(--space-sm) 0 0;
	}
	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(22rem, 100%), 1fr));
		gap: var(--space-sm);
	}
	.person-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		text-decoration: none;
		color: inherit;
		transition: transform var(--transition-base), border-color var(--transition-base);
	}
	.person-row:hover {
		transform: translateY(-1px);
		border-color: color-mix(in srgb, var(--color-primary) 35%, var(--color-border));
	}
	.person-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.person-name {
		font-weight: 600;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.person-handle {
		font-size: 0.82rem;
		color: var(--color-text-secondary);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.person-meta {
		font-size: 0.82rem;
		color: var(--color-text-tertiary);
		display: inline-flex;
		gap: 0.3rem;
		align-items: center;
	}
	.dot {
		opacity: 0.6;
	}
	.follow-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		padding: 0.3rem 0.75rem;
		font-size: 0.82rem;
		font-weight: 600;
		border-radius: 999px;
		border: 1px solid var(--color-primary);
		background: var(--color-primary);
		color: white;
		cursor: pointer;
	}
	.follow-btn .material-symbols {
		font-size: 1rem;
	}
	.follow-btn.following {
		background: transparent;
		color: var(--color-primary);
	}
	.follow-btn:disabled {
		opacity: 0.6;
		cursor: progress;
	}
	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
	.skel-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.skel-row-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
</style>
