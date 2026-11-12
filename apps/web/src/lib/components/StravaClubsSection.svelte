<script lang="ts">
	import { onMount } from 'svelte';
	import Avatar from '#lib/components/Avatar.svelte';
	import { hashHue } from '#lib/format/avatar.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { deferDestructive } from '#lib/stores/undo.svelte.ts';
	import {
		fetchMyStravaClubs,
		isStravaConfigured,
		linkStravaClub,
		StravaClubLinkFailure,
		unlinkStravaClub,
	} from '#lib/integrations/strava.ts';
	import {
		STRAVA_CLUB_LINK_ERROR_KEYS,
		stravaClubLocation,
		stravaClubSetupHref,
		type StravaClub,
		type StravaClubsResult,
	} from '#lib/integrations/strava_clubs.ts';

	interface AdminClub {
		id: string;
		name: string;
		slug: string;
	}
	interface Props {
		/// The Threkir clubs the viewer owns or administers — the only ones a
		/// Strava club can be linked to, and the only links they may clear.
		adminClubs: AdminClub[];
	}
	let { adminClubs }: Props = $props();

	let phase = $state<'idle' | 'loading' | 'error' | 'done'>('idle');
	let result = $state<StravaClubsResult | null>(null);
	let pickerFor = $state<number | null>(null);
	let pickedClubId = $state('');
	let busy = $state(false);

	let clubs = $derived(result?.status === 'connected' ? result.clubs : []);
	let adminClubIds = $derived(new Set(adminClubs.map((c) => c.id)));

	async function load() {
		phase = 'loading';
		try {
			result = await fetchMyStravaClubs();
			phase = 'done';
		} catch (e) {
			console.warn('strava clubs: load failed', e);
			phase = 'error';
		}
	}

	onMount(() => {
		if (isStravaConfigured()) load();
	});

	function openPicker(club: StravaClub) {
		pickerFor = club.stravaClubId;
		pickedClubId = adminClubs[0]?.id ?? '';
	}

	async function link(club: StravaClub) {
		const target = adminClubs.find((c) => c.id === pickedClubId);
		if (!target || busy) return;
		busy = true;
		try {
			await linkStravaClub(target.id, club.stravaClubId);
			club.linkedClub = { id: target.id, slug: target.slug, name: target.name };
			if (result?.status === 'connected') {
				for (const other of result.clubs) {
					if (other !== club && other.linkedClub?.id === target.id) other.linkedClub = null;
				}
			}
			pickerFor = null;
			showToast(m('stravaClubs.linked', { name: target.name }), 'success');
		} catch (e) {
			const reason = e instanceof StravaClubLinkFailure ? e.reason : 'generic';
			showToast(m(STRAVA_CLUB_LINK_ERROR_KEYS[reason]), 'error');
		} finally {
			busy = false;
		}
	}

	function unlink(club: StravaClub) {
		const before = club.linkedClub;
		if (!before) return;
		club.linkedClub = null;
		deferDestructive({
			message: m('stravaClubs.unlinked', { name: before.name }),
			commit: () => unlinkStravaClub(before.id),
			restore: () => {
				club.linkedClub = before;
			},
			onCommitError: () => showToast(m('stravaClubs.errUnlink'), 'error'),
		});
	}
</script>

{#if phase === 'error'}
	<section class="strava-clubs" aria-labelledby="strava-clubs-heading" data-testid="strava-clubs">
		<h2 id="strava-clubs-heading">{m('stravaClubs.heading')}</h2>
		<p class="note" role="alert">
			{m('stravaClubs.loadError')}
			<button class="btn btn-secondary btn-sm" type="button" onclick={load}>{m('socialClubs.retry')}</button>
		</p>
	</section>
{:else if phase === 'done' && result?.status === 'reconnect_required'}
	<section class="strava-clubs" aria-labelledby="strava-clubs-heading" data-testid="strava-clubs">
		<h2 id="strava-clubs-heading">{m('stravaClubs.heading')}</h2>
		<p class="note">
			{m('stravaClubs.reconnectText')}
			<a class="btn btn-outline btn-sm" href="/settings/integrations">{m('stravaClubs.reconnect')}</a>
		</p>
	</section>
{:else if phase === 'done' && result?.status === 'connected'}
	<section class="strava-clubs" aria-labelledby="strava-clubs-heading" data-testid="strava-clubs">
		<h2 id="strava-clubs-heading">{m('stravaClubs.heading')}</h2>
		<p class="intro">{m('stravaClubs.intro')}</p>
		{#if clubs.length === 0}
			<p class="note">{m('stravaClubs.empty')}</p>
		{:else}
			<ul class="list">
				{#each clubs as club (club.stravaClubId)}
					{@const location = stravaClubLocation(club)}
					<li class="row" data-testid="strava-club-row">
						<Avatar name={club.name} size="2.25rem" font="1rem" bg="seed" seedHue={hashHue(String(club.stravaClubId))} />
						<div class="info">
							<span class="name">{club.name}</span>
							<span class="meta">
								{#if location}<span>{location}</span>{/if}
								{#if club.memberCount !== null}
									<span>
										{m(club.memberCount === 1 ? 'socialClubs.memberCountOne' : 'socialClubs.memberCountMany', { n: club.memberCount })}
									</span>
								{/if}
							</span>
						</div>
						<div class="actions">
							{#if club.linkedClub}
								<a class="btn btn-outline btn-sm" href="/clubs/{club.linkedClub.slug}">
									{m('stravaClubs.viewOnThrekir', { name: club.linkedClub.name })}
								</a>
								{#if adminClubIds.has(club.linkedClub.id)}
									<button class="btn btn-secondary btn-sm" type="button" onclick={() => unlink(club)}>
										{m('stravaClubs.unlink')}
									</button>
								{/if}
							{:else if club.viewerIsAdmin === false}
								<span class="hint">{m('stravaClubs.adminOnly')}</span>
							{:else if pickerFor === club.stravaClubId}
								<select class="picker" bind:value={pickedClubId} aria-label={m('stravaClubs.pickClubLabel')}>
									{#each adminClubs as c (c.id)}
										<option value={c.id}>{c.name}</option>
									{/each}
								</select>
								<button class="btn btn-primary btn-sm" type="button" disabled={busy || !pickedClubId} onclick={() => link(club)}>
									{m('stravaClubs.linkConfirm')}
								</button>
								<button class="btn btn-secondary btn-sm" type="button" disabled={busy} onclick={() => (pickerFor = null)}>
									{m('stravaClubs.cancel')}
								</button>
							{:else}
								<a class="btn btn-primary btn-sm" href={stravaClubSetupHref(club)}>
									{m('stravaClubs.setUp')}
								</a>
								{#if adminClubs.length > 0}
									<button class="btn btn-outline btn-sm" type="button" onclick={() => openPicker(club)}>
										{m('stravaClubs.linkToMine')}
									</button>
								{/if}
							{/if}
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
{/if}

<style>
	.strava-clubs {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-top: var(--space-lg);
	}
	h2 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0;
	}
	.intro,
	.note,
	.hint {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0;
	}
	.note {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.row {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-sm);
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.info {
		display: flex;
		flex-direction: column;
		min-width: 0;
		flex: 1 1 12rem;
	}
	.name {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.meta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-xs);
	}
	.picker {
		max-width: 14rem;
	}
</style>
