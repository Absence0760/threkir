<script lang="ts">
	import { goto, afterNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import ClubEditor from '#lib/components/ClubEditor.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { prefilledClubName } from '#lib/social/club_setup.ts';
	import {
		STRAVA_CLUB_LINK_ERROR_KEYS,
		parseStravaClubParam,
		prefilledClubLocation,
	} from '#lib/integrations/strava_clubs.ts';
	import { isStravaConfigured, linkStravaClub, StravaClubLinkFailure } from '#lib/integrations/strava.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';

	const initialName = prefilledClubName(page.url.searchParams.get('name'));
	const initialLocation = prefilledClubLocation(page.url.searchParams.get('location'));
	// Set by "Set up on Threkir" in Your Strava clubs: the new club is linked to
	// that Strava club once it exists (decisions § 1959).
	const stravaClubId = isStravaConfigured()
		? parseStravaClubParam(page.url.searchParams.get('strava_club'))
		: null;

	async function handleCreated(club: { slug: string; id: string }): Promise<void> {
		if (stravaClubId !== null) {
			try {
				await linkStravaClub(club.id, stravaClubId);
				showToast(m('stravaClubs.linkedNew'), 'success');
			} catch (e) {
				console.warn('clubs/new: strava link failed', e);
				const reason = e instanceof StravaClubLinkFailure ? e.reason : 'generic';
				showToast(
					m('stravaClubs.createdNotLinked', { reason: m(STRAVA_CLUB_LINK_ERROR_KEYS[reason]) }),
					'error',
					8000
				);
			}
		}
		await goto(`/clubs/${club.slug}`);
	}

	let cameFromClubs = $state(false);
	afterNavigate(({ from }) => {
		if (cameFromClubs || !from) return;
		const p = from.url.pathname;
		if (p === '/clubs' || p.startsWith('/clubs?') || p === '/social') {
			cameFromClubs = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromClubs) {
			e.preventDefault();
			history.back();
		}
	}

	function handleCancel(): void {
		if (cameFromClubs) history.back();
		else goto('/social?tab=clubs');
	}
</script>

<svelte:head>
	<title>{m('clubsNewPage.documentTitle')}</title>
</svelte:head>

<div class="page">
	<a href="/social?tab=clubs" class="back-link" onclick={handleBack}>
		<span class="material-symbols">arrow_back</span>
		{m('clubsNewPage.backToClubs')}
	</a>

	<header class="page-header">
		<p class="kicker">{m('clubsNewPage.kicker')}</p>
		<h1>{m('clubsNewPage.heading')}</h1>
		<p class="tagline">
			{m('clubsNewPage.tagline')}
		</p>
		{#if stravaClubId !== null}
			<p class="tagline" data-testid="clubs-new-strava-note">{m('stravaClubs.setUpNote')}</p>
		{/if}
	</header>

	<ClubEditor
		{initialName}
		{initialLocation}
		oncreated={handleCreated}
		oncancel={handleCancel}
	/>
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 44rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		padding: var(--space-xs) 0;
		margin-bottom: var(--space-md);
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link .material-symbols {
		font-size: 1.1rem;
	}
	.page-header {
		margin-bottom: var(--space-xl);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-2xs);
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 800;
		line-height: 1.2;
		margin: 0 0 var(--space-xs);
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 38rem;
	}
	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
