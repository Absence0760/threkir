<script lang="ts">
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { onMount } from 'svelte';
	import HelpLink from '#lib/components/help/HelpLink.svelte';
	import SkeletonBlock from '#lib/components/SkeletonBlock.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import { page } from '$app/state';
	import { afterNavigate, goto } from '$app/navigation';
	import { fetchClubBySlug } from '#lib/core/data.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import EventEditor from '#lib/components/EventEditor.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { ClubWithMeta } from '#lib/types.ts';

	let slug = $derived(page.params.slug as string);
	let club = $state<ClubWithMeta | null>(null);
	let loading = $state(true);

	let cameFromClub = $state(false);
	afterNavigate(({ from }) => {
		if (!cameFromClub && from?.url.pathname === `/clubs/${slug}`) {
			cameFromClub = true;
		}
	});
	function handleBack(e: MouseEvent): void {
		if (cameFromClub) {
			e.preventDefault();
			history.back();
		}
	}

	onMount(async () => {
		// Wait for auth.user before resolving the club — fetchClubBySlug
		// derives `viewer_role` against the caller's identity. Without
		// this guard a fast page-load can hit the fetch while auth is
		// still hydrating, viewer_role comes back null even for the
		// real owner, and the admin-gate goto kicks them back to the
		// club page.
		await auth.ready();
		// A failed read leaves `club` null, so the role gate below bounces to
		// /clubs/[slug] — which now states the failure rather than claiming
		// the club is missing.
		club = (await fetchClubBySlug(slug)).club;
		// owner / admin / event_organiser may create events — the latter is a
		// delegated role the DB RLS (is_event_organiser) already permits. Gating
		// it out here was the sole blocker on the deep-linkable create route.
		const role = club?.viewer_role;
		if (role !== 'owner' && role !== 'admin' && role !== 'event_organiser') {
			goto(`/clubs/${slug}`);
			return;
		}
		loading = false;
	});
</script>

{#if loading}
	<div class="page" aria-busy="true" aria-label={m('eventNew.loadingAria')}>
		<span class="back-skel" aria-hidden="true">
			<span class="material-symbols">arrow_back</span>
			{m('eventNew.backToClub')}
		</span>
		<div class="header-skel" aria-hidden="true">
			<SkeletonBlock height="0.85rem" width="20%" />
			<SkeletonBlock height="0.85rem" width="40%" />
			<SkeletonBlock height="0.85rem" width="60%" />
		</div>
		<div class="form-skel" aria-hidden="true">
			<SkeletonBlock height="2.4rem" radius="var(--radius-md)" />
			<SkeletonBlock height="5.5rem" radius="var(--radius-md)" />
			<SkeletonBlock height="2.4rem" radius="var(--radius-md)" />
		</div>
	</div>
	<p class="visually-hidden" role="status">{m('shell.loading')}</p>
{:else if !club}
	<div class="page">
		<EmptyState icon="search_off" title={m('eventNew.clubNotFound')} text={m('eventNew.clubNotFoundBody')}>
			{#snippet actions()}
				<a href="/clubs" class="btn btn-primary">{m('eventNew.backToClubs')}</a>
			{/snippet}
		</EmptyState>
	</div>
{:else}
	<div class="page">
		<a class="back" href="/clubs/{slug}" onclick={handleBack}>
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{m('eventNew.backToNamedClub', { name: club.name })}
		</a>

		<PageHeader kicker={club.name} title={m('eventNew.title')} subtitle={m('eventNew.tagline')}>
			{#snippet help()}<HelpLink route="/clubs/[slug]/events/new" />{/snippet}
		</PageHeader>

		<EventEditor
			clubId={club.id}
			clubName={club.name}
			clubIsPublic={club.is_public}
			oncreated={(event) => goto(`/clubs/${slug}/events/${event.id}`)}
			oncancel={() => history.back()}
		/>
	</div>
{/if}

<style>
	.page {
		max-width: 64rem;
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
		text-decoration: none;
	}
	.back:hover { color: var(--color-primary); }
	.back .material-symbols { font-size: 1.05rem; }

	.back-skel {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
		opacity: 0.5;
	}
	.header-skel {
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
		margin-bottom: var(--space-lg);
	}
	.form-skel {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}
</style>
