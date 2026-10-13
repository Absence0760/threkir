<script lang="ts">
	import Modal from './Modal.svelte';
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import { initial } from '#lib/format/avatar.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { addShare, fetchFollowers, fetchFollowing, sendDm } from '#lib/core/data.ts';
	import {
		dmRecipientCandidates,
		filterDmRecipients,
		type DmRecipient
	} from '#lib/social/dm_recipients.ts';

	interface Props {
		open: boolean;
		/// The link sent as the message body. For a public route it is the
		/// /share/route/[id] URL, already made reachable by the host's
		/// ensure-public step: the forwardable artifact the dialog's own copy
		/// promises the recipient gets, and what the inbox preview line and the
		/// Art 20 export read, neither of which resolves the attachment below.
		/// For a private send (`grantAccess`) it is the in-app /routes/[id]
		/// link, which opens only for the people the route is shared with.
		shareUrl: string;
		/// Share the route with the recipient (a `route_shares` grant) before
		/// sending, instead of the host having made it public. The route stays
		/// private and the owner can revoke the grant at any time (decisions
		/// § R7SHARE-1). Only the owner sends this way; the INSERT policy
		/// refuses anyone else.
		grantAccess?: boolean;
		/// The typed attachment (route_direct_share.md v2). The thread renders
		/// it as a card whose polyline is clipped for the reader; the INSERT
		/// policy refuses an id the sender cannot see.
		routeId: string;
		onclose: () => void;
	}

	let { open, shareUrl, routeId, grantAccess = false, onclose }: Props = $props();

	let loading = $state(false);
	let loadFailed = $state(false);
	let candidates = $state<DmRecipient[]>([]);
	let query = $state('');
	let sendingTo = $state<string | null>(null);
	let sendError = $state<string | null>(null);
	let sentTo = $state<DmRecipient | null>(null);

	const shown = $derived(filterDmRecipients(candidates, query));

	// Mirrors the /messages thread-list latch: the fetch is driven off `open`
	// rather than a mount-time gate, because auth.ready() can resolve on its
	// safety timeout before the session settles.
	let requested = false;
	$effect(() => {
		if (!open) {
			requested = false;
			loading = false;
			loadFailed = false;
			candidates = [];
			query = '';
			sendingTo = null;
			sendError = null;
			sentTo = null;
			return;
		}
		if (requested) return;
		requested = true;
		void load();
	});

	async function load() {
		const me = auth.user?.id;
		if (!me) return;
		loading = true;
		loadFailed = false;
		try {
			const [followers, following] = await Promise.all([fetchFollowers(me), fetchFollowing(me)]);
			candidates = dmRecipientCandidates(followers, following, me);
		} catch {
			// Never degrade to an empty list: "you have nobody to send to" and
			// "we couldn't find out who you could send to" are different
			// answers, and only one of them is worth acting on.
			candidates = [];
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	function retry() {
		requested = true;
		void load();
	}

	async function send(recipient: DmRecipient) {
		if (sendingTo) return;
		sendingTo = recipient.id;
		sendError = null;
		try {
			// Grant first: a message whose link does not open for its reader is
			// worse than no message, so a refused grant stops the send.
			if (grantAccess) await addShare('route', routeId, recipient.id);
			await sendDm(recipient.id, shareUrl, routeId);
			sentTo = recipient;
		} catch (e) {
			sendError = e instanceof Error ? e.message : `${e}`;
		} finally {
			sendingTo = null;
		}
	}

	function nameOf(r: DmRecipient): string {
		return r.displayName ?? tr('messages.runnerFallback');
	}

	function relationLabel(r: DmRecipient): string {
		if (r.relation === 'mutual') return tr('routeDetail.sendDm.relationMutual');
		if (r.relation === 'follows_you') return tr('routeDetail.sendDm.relationFollowsYou');
		return tr('routeDetail.sendDm.relationYouFollow');
	}
</script>

<Modal {open} {onclose} title={tr('routeDetail.sendDm.title')} narrow data-testid="send-route-dialog">
	{#if sentTo}
		<p class="sent" data-testid="send-route-sent">
			{tr('routeDetail.sendDm.sent', { name: nameOf(sentTo) })}
		</p>
		<div class="actions">
			<a class="btn btn-primary btn-sm" href={`/messages/${sentTo.id}`}>
				{tr('routeDetail.sendDm.openThread')}
			</a>
			<button type="button" class="btn btn-outline btn-sm" onclick={onclose}>
				{tr('routeDetail.sendDm.done')}
			</button>
		</div>
	{:else}
		<p class="intro">{tr('routeDetail.sendDm.intro')}</p>
		<p class="note" data-testid="send-route-note">
			{grantAccess ? tr('routeDetail.sendDm.privateNote') : tr('routeDetail.sendDm.linkNote')}
		</p>

		{#if sendError}
			<p class="send-error" role="alert" data-testid="send-route-error">
				{tr('routeDetail.sendDm.sendFailed', { error: sendError })}
			</p>
		{/if}

		{#if loading}
			<p class="muted">{tr('shell.loading')}</p>
		{:else if loadFailed}
			<p class="muted" role="alert" data-testid="send-route-load-error">
				{tr('routeDetail.sendDm.loadFailed')}
				<button type="button" class="btn btn-secondary btn-sm" onclick={retry}>
					{tr('messages.retry')}
				</button>
			</p>
		{:else if candidates.length === 0}
			<p class="muted">{tr('routeDetail.sendDm.empty')}</p>
		{:else}
			<label class="search">
				<span class="material-symbols" aria-hidden="true">search</span>
				<input
					type="text"
					bind:value={query}
					placeholder={tr('routeDetail.sendDm.searchPlaceholder')}
					aria-label={tr('routeDetail.sendDm.searchPlaceholder')}
					data-testid="send-route-search"
				/>
			</label>
			{#if shown.length === 0}
				<p class="muted">{tr('routeDetail.sendDm.noMatches')}</p>
			{:else}
				<ul>
					{#each shown as r (r.id)}
						<li>
							<button
								type="button"
								class="recipient"
								disabled={sendingTo !== null}
								onclick={() => send(r)}
							>
								<span class="avatar" aria-hidden="true">{initial(r.displayName)}</span>
								<span class="who">
									<strong>{nameOf(r)}</strong>
									<span class="relation">{relationLabel(r)}</span>
								</span>
								<span class="cta">
									{sendingTo === r.id
										? tr('routeDetail.sendDm.sending')
										: tr('routeDetail.sendDm.send')}
								</span>
							</button>
						</li>
					{/each}
				</ul>
			{/if}
		{/if}
	{/if}
</Modal>

<style>
	.intro {
		margin: 0 0 var(--space-xs);
	}
	.note,
	.muted {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.note {
		margin: 0 0 var(--space-md);
	}
	.send-error {
		color: var(--color-danger-text);
		margin: 0 0 var(--space-sm);
	}
	.search {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0 var(--space-sm);
		margin-block-end: var(--space-sm);
	}
	.search input {
		flex: 1 1 auto;
		border: none;
		background: none;
		color: inherit;
		padding: var(--space-sm) 0;
	}
	.search input:focus {
		outline: none;
	}
	.search input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.recipient:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	ul {
		list-style: none;
		margin: 0;
		padding: 0;
		max-height: 22rem;
		overflow-y: auto;
	}
	.recipient {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		inline-size: 100%;
		text-align: start;
		background: none;
		border: none;
		border-radius: var(--radius-md);
		padding: var(--space-sm);
		color: inherit;
		cursor: pointer;
	}
	.recipient:hover:not(:disabled) {
		background: var(--color-bg-secondary);
	}
	.recipient:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.avatar {
		inline-size: 2rem;
		block-size: 2rem;
		border-radius: 50%;
		background: var(--color-bg-secondary);
		display: grid;
		place-items: center;
		flex: 0 0 auto;
	}
	.who {
		display: flex;
		flex-direction: column;
		min-inline-size: 0;
		flex: 1 1 auto;
	}
	.who strong {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.relation {
		color: var(--color-text-secondary);
		font-size: 0.8rem;
	}
	.cta {
		color: var(--color-primary);
		font-size: 0.85rem;
		flex: 0 0 auto;
	}
	.sent {
		margin: 0 0 var(--space-md);
	}
	.actions {
		display: flex;
		gap: var(--space-sm);
	}
</style>
