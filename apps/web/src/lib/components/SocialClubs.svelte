<script lang="ts">
	import { onMount } from 'svelte';
	import ClubAvatar from '#lib/components/ClubAvatar.svelte';
	import SkeletonBlock from '#lib/components/SkeletonBlock.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { browseClubsWithError, fetchMyClubsWithError, searchClubsWithError } from '#lib/core/data.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import ClubEditor from '#lib/components/ClubEditor.svelte';
	import StravaClubsSection from '#lib/components/StravaClubsSection.svelte';
	import Modal from '#lib/components/Modal.svelte';
	import FilterBar from '#lib/components/FilterBar.svelte';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import VerifiedBadge from '#lib/components/VerifiedBadge.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { clubRoleLabel } from '#lib/i18n/enum_labels.svelte.ts';
	import { CREATE_CLUB_GUIDE_ID, clubSetupHref } from '#lib/social/club_setup.ts';
	import { fold } from '#lib/segments/catalogue_browse.ts';
	import type { ClubWithMeta } from '#lib/types.ts';

	let subtab = $state<'browse' | 'mine'>('mine');
	let loading = $state(true);
	let search = $state('');
	let browseResults = $state<ClubWithMeta[]>([]);
	let myClubs = $state<ClubWithMeta[]>([]);
	let browseError = $state<Error | null>(null);
	let mineError = $state<Error | null>(null);
	let browseGen = $state(0);
	let mineGen = $state(0);

	// My clubs' own search: a name filter over the clubs already loaded, so
	// the tab is never a row holding only Create club (issue #1374).
	let mineSearch = $state('');
	let mineShown = $derived.by(() => {
		const q = fold(mineSearch.trim());
		return q ? myClubs.filter((c) => fold(c.name).includes(q)) : myClubs;
	});
	let visible = $derived(subtab === 'browse' ? browseResults : mineShown);
	let adminClubs = $derived(
		myClubs.filter((c) => c.viewer_role === 'owner' || c.viewer_role === 'admin')
	);
	let loadError = $derived(subtab === 'browse' ? browseError : mineError);

	async function loadBrowse() {
		loading = true;
		const gen = ++browseGen;
		// `searchClubs` geocodes the query first (so "Virginia" pulls
		// clubs in Virginia even when their label is "Richmond, VA")
		// and falls back to plain ILIKE when the geocode doesn't
		// resolve. Empty / blank query → plain "most recent 60".
		const result = search.trim()
			? await searchClubsWithError(search)
			: await browseClubsWithError();
		if (gen !== browseGen) return;
		browseResults = result.clubs;
		browseError = result.error;
		loading = false;
	}

	async function loadMine() {
		loading = true;
		const gen = ++mineGen;
		const result = await fetchMyClubsWithError();
		if (gen !== mineGen) return;
		myClubs = result.clubs;
		mineError = result.error;
		loading = false;
	}

	function setSubtab(next: 'browse' | 'mine') {
		subtab = next;
		// /social hosts this tab, so the subtab URL key is `clubs-sub` to
		// avoid colliding with the top-level `?tab=clubs`.
		const url = new URL(page.url.href);
		if (next === 'mine') url.searchParams.delete('clubs-sub');
		else url.searchParams.set('clubs-sub', next);
		goto(url, { replace: true, reset: false });
	}

	onMount(async () => {
		const initial = page.url.searchParams.get('clubs-sub');
		if (initial === 'browse') subtab = 'browse';

		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (myClubs.length === 0) loadMine();
		if (browseResults.length === 0) loadBrowse();
	});

	let searchTimer: ReturnType<typeof setTimeout> | null = null;
	function onSearchInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(loadBrowse, 250);
	}

	let showClubModal = $state(false);

	function handleClubCreated(club: { slug: string }) {
		showClubModal = false;
		goto(`/clubs/${club.slug}`);
	}

</script>

{#snippet clubsSearch()}
	<AppSearchField
		bind:value={search}
		label={m('socialClubs.searchAriaLabel')}
		placeholder={m('socialClubs.searchPlaceholder')}
		clearLabel={m('socialClubs.clearSearchAriaLabel')}
		testid="clubs-search"
		oninput={(v) => (v === '' ? loadBrowse() : onSearchInput())}
	/>
{/snippet}

{#snippet mineSearchField()}
	<AppSearchField
		bind:value={mineSearch}
		label={m('socialClubs.mineSearchPlaceholder')}
		placeholder={m('socialClubs.mineSearchPlaceholder')}
		clearLabel={m('socialClubs.clearSearchAriaLabel')}
		testid="clubs-mine-search"
	/>
{/snippet}

{#snippet createClubAction()}
	<button class="btn btn-primary btn-sm create-club" type="button" onclick={() => (showClubModal = true)}>
		<span class="material-symbols" aria-hidden="true">add</span>
		{m('socialClubs.createClub')}
	</button>
{/snippet}

{#snippet missingClubActions(query: string)}
	<a class="btn btn-primary" href={clubSetupHref(query)}>
		<span class="material-symbols" aria-hidden="true">add</span>
		{m('socialClubs.setUpYourClub')}
	</a>
	<a class="btn btn-outline" href="/help/{CREATE_CLUB_GUIDE_ID}">
		<span class="material-symbols" aria-hidden="true">help</span>
		{m('socialClubs.howToCreateClub')}
	</a>
{/snippet}

{#snippet clubGrid()}
	<div class="grid">
		{#each visible as club (club.id)}
			<a href="/clubs/{club.slug}" class="card">
				<div class="card-header">
					<ClubAvatar {club} size="2.5rem" font="1.1rem" />
					<div class="card-title">
						<h3>
								{club.name}
								{#if club.is_verified}
									<VerifiedBadge />
								{/if}
							</h3>
						{#if club.location_label}
							<span class="location">
								<span class="material-symbols" aria-hidden="true">place</span>
								{club.location_label}
							</span>
						{/if}
					</div>
					{#if !club.is_public}
						<span class="badge" title={m('socialClubs.privateTitle')}>{m('socialClubs.private')}</span>
					{/if}
				</div>
				{#if club.description}
					<p class="desc">{club.description}</p>
				{/if}
				<div class="card-foot">
					<span class="members">
						<span class="material-symbols" aria-hidden="true">group</span>
						{m('socialClubs.memberCount', { n: club.member_count })}
					</span>
					{#if club.viewer_role}
						<span class="chip chip-mine">{clubRoleLabel(club.viewer_role)}</span>
					{:else if club.viewer_status === 'pending'}
						<span class="chip chip-pending" title={m('socialClubs.requestPendingTitle')}>
							{m('socialClubs.requestPending')}
						</span>
					{/if}
				</div>
			</a>
		{/each}
	</div>
{/snippet}

<div class="clubs-panel">
	<div class="tabs" role="tablist" aria-label={m('socialClubs.tablistLabel')}>
		<button
			role="tab"
			class="tab"
			class:active={subtab === 'mine'}
			aria-selected={subtab === 'mine'}
			onclick={() => setSubtab('mine')}
		>
			{m('socialClubs.myClubs')}
		</button>
		<button
			role="tab"
			class="tab"
			class:active={subtab === 'browse'}
			aria-selected={subtab === 'browse'}
			onclick={() => setSubtab('browse')}
		>
			{m('socialClubs.browse')}
		</button>
	</div>

	<FilterBar idPrefix="clubs" search={subtab === 'browse' ? clubsSearch : mineSearchField} trailing={createClubAction} />

	{#if loading}
		<div class="grid" aria-hidden="true">
			{#each Array(6) as _, i (i)}
				<div class="skel-card">
					<div class="skel-card-header">
						<SkeletonBlock height="2.5rem" width="2.5rem" radius="50%" />
						<div class="skel-card-title">
							<SkeletonBlock height="0.75rem" width="60%" />
							<SkeletonBlock height="0.75rem" width="40%" />
						</div>
					</div>
					<SkeletonBlock height="0.75rem" width="80%" />
					<SkeletonBlock height="0.75rem" width="60%" />
				</div>
			{/each}
		</div>
		<p class="visually-hidden" role="status">{m('socialClubs.loadingClubs')}</p>
	{:else if loadError && visible.length > 0}
		<!-- The clubs read succeeded and only the viewer's own membership did
		     not, so the list is real; say the roles and Join buttons are
		     unreliable rather than replacing the list with an error. -->
		<p class="membership-unknown" role="alert" data-testid="clubs-membership-unknown">
			{m('socialClubs.membershipUnknown')}
			<button
				class="btn btn-secondary btn-sm"
				type="button"
				onclick={() => (subtab === 'browse' ? loadBrowse() : loadMine())}
			>
				{m('socialClubs.retry')}
			</button>
		</p>
		{@render clubGrid()}
	{:else if loadError}
		<EmptyState
			icon="cloud_off"
			tone="danger"
			title={m('socialClubs.loadErrorTitle')}
			text={m('socialClubs.loadErrorText')}
			role="alert"
		>
			{#snippet actions()}
				<button
					class="btn btn-primary"
					type="button"
					onclick={() => (subtab === 'browse' ? loadBrowse() : loadMine())}
				>
					<span class="material-symbols" aria-hidden="true">refresh</span>
					{m('socialClubs.retry')}
				</button>
			{/snippet}
		</EmptyState>
	{:else if visible.length === 0}
		{#if subtab === 'mine' && myClubs.length > 0}
			<EmptyState icon="search_off" title={m('socialClubs.mineNoMatch')} data-testid="clubs-mine-no-match">
				{#snippet actions()}
					<button type="button" class="btn btn-secondary" onclick={() => (mineSearch = '')}>
						{m('socialClubs.clearSearch')}
					</button>
				{/snippet}
			</EmptyState>
		{:else if subtab === 'mine'}
			<EmptyState
				icon="groups"
				title={m('socialClubs.emptyMineTitle')}
				text={m('socialClubs.emptyMineText')}
			>
				{#snippet actions()}
					<button class="btn btn-primary" type="button" onclick={() => setSubtab('browse')}>
						<span class="material-symbols" aria-hidden="true">search</span>
						{m('socialClubs.findAClub')}
					</button>
					<button class="btn btn-outline" type="button" onclick={() => (showClubModal = true)}>
						<span class="material-symbols" aria-hidden="true">add</span>
						{m('socialClubs.createOneInstead')}
					</button>
				{/snippet}
			</EmptyState>
		{:else if search.trim()}
			<EmptyState
				icon="search_off"
				title={m('socialClubs.noClubsMatch', { query: search.trim() })}
				text={m('socialClubs.missingClubText')}
				data-testid="clubs-missing-club"
			>
				{#snippet actions()}
					{@render missingClubActions(search)}
					<button
						type="button"
						class="btn btn-secondary"
						onclick={() => { search = ''; loadBrowse(); }}
					>
						{m('socialClubs.clearSearch')}
					</button>
				{/snippet}
			</EmptyState>
		{:else}
			<EmptyState
				icon="groups"
				title={m('socialClubs.noPublicClubsTitle')}
				text={m('socialClubs.noPublicClubsText')}
				data-testid="clubs-missing-club"
			>
				{#snippet actions()}
					{@render missingClubActions('')}
				{/snippet}
			</EmptyState>
		{/if}
	{:else}
		{@render clubGrid()}
	{/if}

	<!-- Hidden rather than unmounted on Browse, so switching tabs does not
	     re-ask Strava (the list is rate-limited per caller). -->
	<div hidden={subtab !== 'mine'}>
		<StravaClubsSection {adminClubs} />
	</div>
</div>

<Modal
	open={showClubModal}
	title={m('socialClubs.createAClub')}
	onclose={() => (showClubModal = false)}
>
	<ClubEditor oncreated={handleClubCreated} oncancel={() => (showClubModal = false)} />
</Modal>

<style>
	.membership-unknown {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
		margin: 0 0 var(--space-sm);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.clubs-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.tabs {
		display: flex;
		gap: 0.5rem;
		border-bottom: 1px solid var(--color-border);
	}
	.tab {
		background: none;
		border: none;
		padding: 0.6rem 0.2rem;
		margin-inline-end: 1rem;
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		cursor: pointer;
		font-weight: 500;
	}
	.tab:hover { color: var(--color-text); }
	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}
	.create-club {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.create-club .material-symbols { font-size: 1.05rem; }
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(22rem, 100%), 1fr));
		gap: var(--space-md);
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
		transition: transform var(--transition-base),
			box-shadow var(--transition-base),
			border-color var(--transition-base);
		color: inherit;
		text-decoration: none;
	}
	.card:hover {
		transform: translateY(-2px);
		box-shadow: var(--shadow-md);
		border-color: color-mix(in srgb, var(--color-primary) 40%, var(--color-border));
	}
	.card-header { display: flex; align-items: center; gap: 0.75rem; }
	.card-title { flex: 1; min-width: 0; }
	.card-title h3 {
		font-size: 1.05rem;
		font-weight: 700;
		margin: 0 0 0.15rem 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.location {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		color: var(--color-text-secondary);
		font-size: 0.8rem;
	}
	.location .material-symbols { font-size: 0.95rem; }
	.badge {
		font-size: var(--font-size-section-label);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-tertiary);
		background: var(--color-bg-tertiary);
		padding: 0.15rem 0.5rem;
		border-radius: var(--radius-sm);
	}
	.desc {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.4;
		overflow: hidden;
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
	}
	.card-foot {
		display: flex;
		justify-content: space-between;
		align-items: center;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.members { display: inline-flex; align-items: center; gap: 0.3rem; }
	.members .material-symbols { font-size: 1rem; }
	.chip-mine {
		background: var(--color-primary-light);
		color: var(--color-primary);
		padding: 0.15rem 0.55rem;
		border-radius: var(--radius-sm);
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: capitalize;
	}
	.chip-pending {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text));
		padding: 0.15rem 0.55rem;
		border-radius: var(--radius-sm);
		font-size: 0.75rem;
		font-weight: 600;
	}
	.material-symbols { font-family: 'Material Symbols Outlined'; }
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		pointer-events: none;
	}
	.skel-card-header {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		margin-bottom: 0.2rem;
	}
	.skel-card-title {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
</style>
