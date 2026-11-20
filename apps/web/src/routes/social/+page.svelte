<script lang="ts">
	import { page } from '$app/state';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { goto } from '$app/navigation';
	import SocialFeed from '#lib/components/SocialFeed.svelte';
	import SocialPeople from '#lib/components/SocialPeople.svelte';
	import SocialClubs from '#lib/components/SocialClubs.svelte';
	import SocialDiscover from '#lib/components/SocialDiscover.svelte';
	import ChallengesPanel from '#lib/components/ChallengesPanel.svelte';
	import ChallengeEditor from '#lib/components/ChallengeEditor.svelte';
	import Modal from '#lib/components/Modal.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';

	// Feed · Clubs · Events · Challenges · People (issue #1374, owner decision
	// "Social tabs"): Events is the cross-club activity search that was called
	// Discover, named for what it lists, and People goes last. The mobile hub
	// has the same five in the same order.
	type Tab = 'feed' | 'clubs' | 'events' | 'challenges' | 'people';
	const TABS: { id: Tab; labelKey: MessageKey; icon: string }[] = [
		{ id: 'feed', labelKey: 'socialHub.tabFeed', icon: 'dynamic_feed' },
		{ id: 'clubs', labelKey: 'socialHub.tabClubs', icon: 'groups' },
		{ id: 'events', labelKey: 'socialHub.tabEvents', icon: 'event_available' },
		{ id: 'challenges', labelKey: 'challenges.title', icon: 'trophy' },
		{ id: 'people', labelKey: 'socialHub.tabPeople', icon: 'person_search' },
	];
	const TAB_IDS = new Set<string>(TABS.map((t) => t.id));

	let tab = $state<Tab>('feed');
	// One primary action per tab on the title row, as mobile's FAB: Clubs
	// creates a club, Challenges a challenge; the other tabs have none.
	let createClubOpen = $state(false);
	let createChallengeOpen = $state(false);

	$effect(() => {
		const t = page.url.searchParams.get('tab');
		// The Events tab's old URL keeps working: a saved or shared
		// `?tab=discover` is rewritten in place, so Back does not return to it.
		if (t === 'discover') {
			const url = new URL(page.url.href);
			url.searchParams.set('tab', 'events');
			goto(url, { replace: true });
			tab = 'events';
			return;
		}
		tab = t !== null && TAB_IDS.has(t) ? (t as Tab) : 'feed';
	});

	function setTab(next: Tab) {
		if (next === tab) return;
		const url = new URL(page.url.href);
		if (next === 'feed') url.searchParams.delete('tab');
		else url.searchParams.set('tab', next);
		// Clear the Clubs subtab when leaving Clubs so a back-nav doesn't
		// re-deep-link into Browse.
		if (next !== 'clubs') url.searchParams.delete('clubs-sub');
		goto(url, { replace: false, reset: false });
		tab = next;
	}
</script>

<svelte:head>
	<title>{m('socialHub.pageTitle')}</title>
</svelte:head>

<div class="page">
	<PageHeader flush title={m('socialHub.heading')}>
		{#snippet actions()}
			{#if tab === 'clubs'}
				<button class="btn btn-primary" type="button" onclick={() => (createClubOpen = true)}>
					<span class="material-symbols" aria-hidden="true">add</span>
					{m('socialClubs.createClub')}
				</button>
			{:else if tab === 'challenges'}
				<button class="btn btn-primary" type="button" onclick={() => (createChallengeOpen = true)}>
					<span class="material-symbols" aria-hidden="true">add</span>
					{m('challenges.create')}
				</button>
			{/if}
		{/snippet}
	</PageHeader>

	<div class="tabs" role="tablist" aria-label={m('socialHub.sectionsLabel')}>
		{#each TABS as t}
			<button
				type="button"
				role="tab"
				class="tab"
				class:active={tab === t.id}
				aria-selected={tab === t.id}
				aria-controls="social-panel-{t.id}"
				onclick={() => setTab(t.id)}
			>
				<span class="material-symbols" aria-hidden="true">{t.icon}</span>
				<span>{m(t.labelKey)}</span>
			</button>
		{/each}
	</div>

	<div
		id="social-panel-{tab}"
		role="tabpanel"
		tabindex="0"
		aria-label={m('socialHub.panelLabel', {
			section: m(TABS.find((t) => t.id === tab)?.labelKey ?? 'socialHub.tabFeed'),
		})}
	>
		{#if tab === 'feed'}
			<SocialFeed />
		{:else if tab === 'people'}
			<SocialPeople />
		{:else if tab === 'clubs'}
			<SocialClubs bind:createOpen={createClubOpen} />
		{:else if tab === 'challenges'}
			<div class="challenges-tab">
				<ChallengesPanel />
				<a class="btn btn-primary" href="/challenges">{m('challenges.browse')}</a>
			</div>
		{:else}
			<SocialDiscover />
		{/if}
	</div>
</div>

<Modal
	open={createChallengeOpen}
	onclose={() => (createChallengeOpen = false)}
	title={m('challenges.create')}
>
	<ChallengeEditor
		oncreated={(ch) => {
			createChallengeOpen = false;
			goto(`/challenges/${ch.id}`);
		}}
		oncancel={() => (createChallengeOpen = false)}
	/>
</Modal>

<style>
	.challenges-tab {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		align-items: flex-start;
	}
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.tabs {
		display: flex;
		gap: 0.4rem;
		border-bottom: 1px solid var(--color-border);
		overflow-x: auto;
	}
	.tab {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: none;
		border: none;
		padding: 0.7rem 0.25rem;
		margin-inline-end: 1rem;
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		cursor: pointer;
		font-weight: 600;
		white-space: nowrap;
	}
	.tab:hover { color: var(--color-text); }
	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}
	.tab .material-symbols { font-size: 1.1rem; }
	.material-symbols { font-family: 'Material Symbols Outlined'; }
</style>
