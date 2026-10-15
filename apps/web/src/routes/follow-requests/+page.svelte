<script lang="ts">
	import Avatar from '#lib/components/Avatar.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { formatRelativeTime } from '#lib/format/time.ts';
	import {
		approveFollowRequest,
		declineFollowRequest,
		fetchIncomingFollowRequests,
		type IncomingFollowRequest,
	} from '#lib/core/data.ts';

	let requests = $state<IncomingFollowRequest[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let busy = $state<Set<string>>(new Set());

	async function load() {
		loading = true;
		loadError = null;
		try {
			requests = await fetchIncomingFollowRequests();
		} catch (e) {
			loadError = thrownMessage(e);
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		if (auth.loggedIn) load();
	});

	// A decline is not confirmed: it is reversible by the requester asking
	// again, and nothing they could see is taken away.
	async function act(r: IncomingFollowRequest, approve: boolean) {
		if (busy.has(r.id)) return;
		busy = new Set([...busy, r.id]);
		const name = r.display_name ?? m('followRequests.someone');
		try {
			if (approve) await approveFollowRequest(r.id);
			else await declineFollowRequest(r.id);
			requests = requests.filter((x) => x.id !== r.id);
			showToast(
				approve ? m('followRequests.approved', { name }) : m('followRequests.declinedToast'),
				'success'
			);
		} catch (e) {
			showToast(m('followRequests.actionError', { error: thrownMessage(e) }), 'error');
		} finally {
			const next = new Set(busy);
			next.delete(r.id);
			busy = next;
		}
	}
</script>

<svelte:head>
	<title>{m('followRequests.title')}</title>
</svelte:head>

<div class="page">
	<header class="head">
		<h1>{m('followRequests.title')}</h1>
		<p class="tagline">{m('followRequests.tagline')}</p>
	</header>

	{#if loading}
		<p class="muted" role="status">{m('profile.loadingShort')}</p>
	{:else if loadError !== null}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('followRequests.loadError')}</strong>
				{#if loadError}<span class="error-detail">{loadError}</span>{/if}
			</div>
			<button class="btn btn-outline" onclick={load}>{m('followRequests.retry')}</button>
		</div>
	{:else if requests.length === 0}
		<div class="empty-card" data-testid="follow-requests-empty">
			<span class="material-symbols empty-icon" aria-hidden="true">person_add</span>
			<h3>{m('followRequests.emptyTitle')}</h3>
			<p class="empty-text">{m('followRequests.emptyText')}</p>
		</div>
	{:else}
		<ul class="list" data-testid="follow-requests-list">
			{#each requests as r (r.id)}
				{@const name = r.display_name ?? m('followRequests.someone')}
				<li class="row">
					<a class="who" href={`/u/${r.id}`}>
						<Avatar url={r.avatar_url} name={r.display_name} size="2.5rem" font="0.95rem" />
						<span class="who-text">
							<span class="name">{name}</span>
							{#if r.requested_at}
								<span class="when">{formatRelativeTime(r.requested_at)}</span>
							{/if}
						</span>
					</a>
					<div class="actions">
						<button
							type="button"
							class="btn btn-primary btn-sm"
							disabled={busy.has(r.id)}
							aria-label={m('followRequests.approveName', { name })}
							onclick={() => act(r, true)}
						>
							{m('followRequests.approve')}
						</button>
						<button
							type="button"
							class="btn btn-outline btn-sm"
							disabled={busy.has(r.id)}
							aria-label={m('followRequests.declineName', { name })}
							onclick={() => act(r, false)}
						>
							{m('followRequests.decline')}
						</button>
					</div>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 40rem;
		margin: 0 auto;
	}
	.head h1 {
		margin: 0 0 var(--space-xs) 0;
	}
	.tagline,
	.muted,
	.when {
		color: var(--color-text-secondary);
	}
	.list {
		list-style: none;
		margin: var(--space-lg) 0 0 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		flex-wrap: wrap;
		gap: var(--space-sm);
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-border);
	}
	.who {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		min-width: 0;
		color: inherit;
		text-decoration: none;
	}
	.who-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.name {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.when {
		font-size: 0.85rem;
	}
	.actions {
		display: inline-flex;
		gap: var(--space-xs);
	}
</style>
