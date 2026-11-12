<script lang="ts">
	import { onMount } from 'svelte';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import {
		challengeInviteLinksEnabled,
		getChallengeInviteToken,
		rotateChallengeInviteToken
	} from '#lib/core/data.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { buildChallengeShareCanonical } from '#lib/share/share_challenge_meta.ts';
	import { withShareRef } from '#lib/share/share_ref.ts';
	import { ownShareRef } from '#lib/share/share_attribution.ts';

	let {
		challengeId,
		creatorId,
		isPublic,
		canManage
	}: { challengeId: string; creatorId: string | null; isPublic: boolean; canManage: boolean } =
		$props();

	// The invite link waits on the challenge_invite_links gate (decisions
	// § 2261); the public share page does not, because a public challenge is
	// already readable by anyone.
	let enabled = $state(false);
	let token = $state<string | null>(null);
	let loadFailed = $state(false);
	let busy = $state(false);
	let confirmRotate = $state(false);
	let copied = $state<'invite' | 'share' | null>(null);
	let actionError = $state<string | null>(null);
	// The creator's own share link carries their ref (decisions § 2268); a club
	// admin handing it out is not the creator, so theirs goes out bare.
	let shareRef = $state<string | null>(null);

	const inviteUrl = $derived(
		token && typeof location !== 'undefined'
			? `${location.origin}/challenges/join/${encodeURIComponent(token)}`
			: null
	);
	const shareUrl = $derived(
		typeof location !== 'undefined'
			? withShareRef(buildChallengeShareCanonical(location.origin, challengeId), shareRef)
			: null
	);

	async function load() {
		loadFailed = false;
		if (!canManage) return;
		try {
			enabled = await challengeInviteLinksEnabled();
			if (enabled) token = await getChallengeInviteToken(challengeId);
			shareRef = await ownShareRef(creatorId);
		} catch (e) {
			console.error('challenge invite link: load failed', e);
			loadFailed = true;
		}
	}

	onMount(load);

	async function copy(which: 'invite' | 'share') {
		const url = which === 'invite' ? inviteUrl : shareUrl;
		if (!url) return;
		actionError = null;
		try {
			await navigator.clipboard.writeText(url);
			copied = which;
		} catch (e) {
			console.error('challenge invite link: copy failed', e);
			actionError = m('challengeInvite.copyFailed');
		}
	}

	async function rotate() {
		confirmRotate = false;
		busy = true;
		actionError = null;
		copied = null;
		try {
			token = await rotateChallengeInviteToken(challengeId);
		} catch (e) {
			console.error('challenge invite link: rotate failed', e);
			actionError = m('challengeInvite.rotateFailed');
		} finally {
			busy = false;
		}
	}
</script>

{#if (canManage && (enabled || loadFailed)) || isPublic}
	<section class="card invite-link" data-testid="challenge-invite-link">
		<h2>{m('challengeInvite.title')}</h2>
		{#if canManage && loadFailed}
			<p class="error" role="alert">{m('challengeInvite.loadFailed')}</p>
			<button type="button" class="btn btn-outline btn-sm" onclick={load}>
				{m('challenges.retry')}
			</button>
		{:else if canManage && inviteUrl}
			<p class="card-sub">
				{isPublic ? m('challengeInvite.bodyPublic') : m('challengeInvite.bodyPrivate')}
			</p>
			<label class="url-label" for="challenge-invite-url">{m('challengeInvite.urlLabel')}</label>
			<input
				id="challenge-invite-url"
				class="url"
				type="text"
				readonly
				value={inviteUrl}
				onfocus={(e) => e.currentTarget.select()}
				data-testid="challenge-invite-url"
			/>
			<div class="actions">
				<button
					type="button"
					class="btn btn-primary btn-sm"
					onclick={() => copy('invite')}
					data-testid="challenge-invite-copy"
				>
					{copied === 'invite' ? m('challengeInvite.copied') : m('challengeInvite.copy')}
				</button>
				<button
					type="button"
					class="btn btn-outline btn-sm"
					onclick={() => (confirmRotate = true)}
					disabled={busy}
					data-testid="challenge-invite-rotate"
				>
					{m('challengeInvite.rotate')}
				</button>
			</div>
		{/if}
		{#if isPublic && shareUrl}
			<p class="card-sub">{m('challengeInvite.shareBody')}</p>
			<div class="actions">
				<button
					type="button"
					class="btn btn-outline btn-sm"
					onclick={() => copy('share')}
					data-testid="challenge-share-copy"
				>
					{copied === 'share' ? m('challengeInvite.copied') : m('challengeInvite.copyShare')}
				</button>
				<a class="btn btn-outline btn-sm" href={shareUrl} data-testid="challenge-share-view">
					{m('challengeInvite.viewShare')}
				</a>
			</div>
		{/if}
		{#if actionError}
			<p class="error" role="alert">{actionError}</p>
		{/if}
	</section>
{/if}

<ConfirmDialog
	open={confirmRotate}
	title={m('challengeInvite.rotateTitle')}
	message={m('challengeInvite.rotateMessage')}
	confirmLabel={m('challengeInvite.rotate')}
	onconfirm={rotate}
	oncancel={() => (confirmRotate = false)}
/>

<style>
	.invite-link {
		padding: var(--space-lg);
		margin: var(--space-md) 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.invite-link h2 {
		font-size: 1.1rem;
		margin: 0;
	}
	.card-sub {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.url-label {
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.url {
		width: 100%;
		min-width: 0;
		font-family: var(--font-mono, monospace);
		font-size: 0.85rem;
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		color: var(--color-text);
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.error {
		margin: 0;
		color: var(--color-danger-text);
		font-size: 0.88rem;
	}
</style>
