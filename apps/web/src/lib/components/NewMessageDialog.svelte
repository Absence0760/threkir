<script lang="ts">
	// Start a 1:1 conversation from the inbox (issue #1374, decisions § 2493;
	// twin of mobile's New message). The list is the viewer's follow graph in
	// both directions, which is exactly who the send gate admits without a
	// request (`dm_recipients.ts`; a block is decided by the server and
	// surfaces on send in the thread). Picking someone opens the thread with
	// them, existing or not: the composer there sends the first message.
	import Modal from './Modal.svelte';
	import Avatar from './Avatar.svelte';
	import AppSearchField from './AppSearchField.svelte';
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import { hashHue } from '#lib/format/avatar.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { fetchFollowers, fetchFollowing } from '#lib/core/data.ts';
	import { dmRecipientCandidates, filterDmRecipients, type DmRecipient } from '#lib/social/dm_recipients.ts';
	import { dmRelationLabelKey } from '#lib/social/dm_relation_label.ts';

	let { open, onclose }: { open: boolean; onclose: () => void } = $props();

	let loading = $state(true);
	let loadFailed = $state(false);
	let candidates = $state<DmRecipient[]>([]);
	let query = $state('');
	const shown = $derived(filterDmRecipients(candidates, query));

	async function load() {
		const me = auth.user?.id;
		if (!me) return;
		loading = true;
		loadFailed = false;
		try {
			const [followers, following] = await Promise.all([fetchFollowers(me), fetchFollowing(me)]);
			candidates = dmRecipientCandidates(followers.rows, following.rows, me);
		} catch (e) {
			// "Nobody to message" and "couldn't find out who" are different answers.
			console.warn('new message: people read failed', e);
			candidates = [];
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		if (!open) {
			query = '';
			return;
		}
		void load();
	});
</script>

<Modal {open} {onclose} title={tr('messages.newMessage')} narrow data-testid="new-message-dialog">
	{#if loading}
		<p class="muted">{tr('shell.loading')}</p>
	{:else if loadFailed}
		<p class="muted" role="alert" data-testid="new-message-load-error">
			{tr('messages.newMessageLoadFailed')}
			<button type="button" class="btn btn-secondary btn-sm" onclick={() => void load()}>
				{tr('messages.retry')}
			</button>
		</p>
	{:else if candidates.length === 0}
		<p class="muted" data-testid="new-message-empty">{tr('messages.newMessageNobody')}</p>
	{:else}
		<AppSearchField bind:value={query} label={tr('groups.peopleSearch')} testid="new-message-search" />
		{#if shown.length === 0}
			<p class="muted">{tr('groups.peopleNoMatches')}</p>
		{:else}
			<ul>
				{#each shown as r (r.id)}
					<li>
						<a class="recipient" href={`/messages/${r.id}`} onclick={onclose} data-testid="new-message-person">
							<Avatar
								url={r.avatarUrl}
								name={r.displayName}
								size="2rem"
								font="0.85rem"
								bg="seed"
								seedHue={hashHue(r.id)}
							/>
							<span class="who">
								<strong>{r.displayName ?? tr('messages.runnerFallback')}</strong>
								<span class="relation">{tr(dmRelationLabelKey(r.relation))}</span>
							</span>
						</a>
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</Modal>

<style>
	.muted {
		color: var(--color-text-secondary);
	}
	ul {
		list-style: none;
		margin: var(--space-sm) 0 0;
		padding: 0;
		max-height: 22rem;
		overflow-y: auto;
	}
	.recipient {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		min-height: 2.75rem;
		padding: var(--space-xs) var(--space-sm);
		border-radius: var(--radius-md);
		color: var(--color-text);
		text-decoration: none;
	}
	.recipient:hover,
	.recipient:focus-visible {
		background: var(--color-bg-secondary);
	}
	.who {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.who strong {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.relation {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
</style>
