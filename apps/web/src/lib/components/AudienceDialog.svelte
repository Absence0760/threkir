<script lang="ts">
	import Modal from './Modal.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import { initial } from '#lib/format/avatar.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import {
		addShare,
		fetchFollowers,
		fetchFollowing,
		fetchShares,
		revokeShare,
		setAudience,
		type ShareRecipient,
		type ShareableKind
	} from '#lib/core/data.ts';
	import {
		dmRecipientCandidates,
		filterDmRecipients,
		type DmRecipient
	} from '#lib/social/dm_recipients.ts';
	import {
		AUDIENCE_LEVELS,
		audienceColumns,
		audienceOf,
		type AudienceColumns,
		type AudienceLevel
	} from '#lib/social/run_visibility.ts';

	interface Props {
		open: boolean;
		kind: ShareableKind;
		entityId: string;
		isPublic: boolean;
		followersOnly: boolean;
		/// The columns the row now has, after a level change this dialog wrote.
		onlevel: (columns: AudienceColumns) => void;
		/// Public goes through the host page's own confirm (the privacy-zone
		/// warning for a run, the public-flip confirm for a route), so this
		/// dialog hands it back rather than writing it.
		onrequestpublic: () => void;
		onclose: () => void;
	}

	let { open, kind, entityId, isPublic, followersOnly, onlevel, onrequestpublic, onclose }: Props =
		$props();

	let shares = $state<ShareRecipient[]>([]);
	let sharesLoading = $state(false);
	let sharesFailed = $state(false);
	let candidates = $state<DmRecipient[]>([]);
	let peopleLoading = $state(false);
	let peopleFailed = $state(false);
	let query = $state('');
	let busy = $state(false);
	let pendingRecipient = $state<string | null>(null);
	let confirmRevokeAll = $state(false);
	/// The level the owner picked in this dialog. Specific people with nobody
	/// added yet is still a private row, so it cannot be read back off the
	/// columns; it is held here until the first share lands.
	let picked = $state<AudienceLevel | null>(null);

	const stored = $derived(audienceOf({ is_public: isPublic, followers_only: followersOnly }, shares.length));
	const level = $derived(picked ?? stored);
	const sharedIds = $derived(new Set(shares.map((s) => s.recipientId)));
	const shown = $derived(filterDmRecipients(candidates, query));

	let requested = false;
	$effect(() => {
		if (!open) {
			requested = false;
			shares = [];
			candidates = [];
			query = '';
			picked = null;
			sharesFailed = false;
			peopleFailed = false;
			confirmRevokeAll = false;
			return;
		}
		if (requested) return;
		requested = true;
		void loadShares();
		void loadPeople();
	});

	async function loadShares() {
		sharesLoading = true;
		sharesFailed = false;
		try {
			shares = await fetchShares(kind, entityId);
		} catch {
			shares = [];
			sharesFailed = true;
		} finally {
			sharesLoading = false;
		}
	}

	async function loadPeople() {
		const me = auth.user?.id;
		if (!me) return;
		peopleLoading = true;
		peopleFailed = false;
		try {
			const [followers, following] = await Promise.all([fetchFollowers(me), fetchFollowing(me)]);
			candidates = dmRecipientCandidates(followers, following, me);
		} catch {
			// "Nobody to share with" and "could not find out" are different
			// answers; only the second is worth a retry.
			candidates = [];
			peopleFailed = true;
		} finally {
			peopleLoading = false;
		}
	}

	async function choose(next: AudienceLevel) {
		if (busy || next === level) return;
		if (next === 'public') {
			onrequestpublic();
			return;
		}
		if (next === 'private' && shares.length > 0) {
			confirmRevokeAll = true;
			return;
		}
		await apply(next);
	}

	async function apply(next: Exclude<AudienceLevel, 'public'>) {
		busy = true;
		try {
			await setAudience(kind, entityId, next);
			if (next === 'private') shares = [];
			picked = next === 'specific' ? 'specific' : null;
			onlevel(audienceColumns(next));
			showToast(tr('audience.updated'), 'success');
		} catch (e) {
			showToast(tr('audience.updateFailed', { error: e instanceof Error ? e.message : `${e}` }), 'error');
		} finally {
			busy = false;
		}
	}

	async function confirmOnlyMe() {
		confirmRevokeAll = false;
		await apply('private');
	}

	async function share(person: DmRecipient) {
		if (pendingRecipient || sharedIds.has(person.id)) return;
		pendingRecipient = person.id;
		try {
			await addShare(kind, entityId, person.id);
			shares = [
				...shares,
				{
					recipientId: person.id,
					displayName: person.displayName,
					avatarUrl: person.avatarUrl,
					createdAt: new Date().toISOString()
				}
			];
			showToast(tr('audience.shared', { name: nameOf(person.displayName) }), 'success');
		} catch (e) {
			showToast(tr('audience.shareFailed', { error: e instanceof Error ? e.message : `${e}` }), 'error');
		} finally {
			pendingRecipient = null;
		}
	}

	async function revoke(person: ShareRecipient) {
		if (pendingRecipient) return;
		pendingRecipient = person.recipientId;
		try {
			await revokeShare(kind, entityId, person.recipientId);
			shares = shares.filter((s) => s.recipientId !== person.recipientId);
			if (level === 'specific') picked = 'specific';
			showToast(tr('audience.revoked', { name: nameOf(person.displayName) }), 'success');
		} catch (e) {
			showToast(tr('audience.revokeFailed', { error: e instanceof Error ? e.message : `${e}` }), 'error');
		} finally {
			pendingRecipient = null;
		}
	}

	function nameOf(name: string | null): string {
		return name ?? tr('messages.runnerFallback');
	}

	const LABEL: Record<AudienceLevel, MessageKey> = {
		private: 'audience.levelPrivate',
		followers: 'audience.levelFollowers',
		specific: 'audience.levelSpecific',
		public: 'audience.levelPublic'
	};
	const ICON: Record<AudienceLevel, string> = {
		private: 'lock',
		followers: 'group',
		specific: 'person_add',
		public: 'public'
	};
	const HINT: Record<AudienceLevel, MessageKey> = {
		private: 'audience.levelPrivateHint',
		followers: 'audience.levelFollowersHint',
		specific: 'audience.levelSpecificHint',
		public: 'audience.levelPublicHint'
	};
</script>

<Modal {open} {onclose} title={tr('audience.title')} narrow data-testid="audience-dialog">
	<div class="levels" role="group" aria-label={tr('audience.title')}>
		{#each AUDIENCE_LEVELS as option (option)}
			<button
				type="button"
				class="level"
				class:selected={level === option}
				aria-pressed={level === option}
				disabled={busy}
				onclick={() => choose(option)}
				data-testid={`audience-level-${option}`}
			>
				<span class="material-symbols" aria-hidden="true">{ICON[option]}</span>
				<span class="level-text">
					<strong>{tr(LABEL[option])}</strong>
					<span class="hint">{tr(HINT[option])}</span>
				</span>
			</button>
		{/each}
	</div>
	<p class="note">{tr('audience.clipNote')}</p>

	<section class="shared" aria-labelledby="audience-shared-heading">
		<h3 id="audience-shared-heading">{tr('audience.sharedWith')}</h3>
		{#if sharesLoading}
			<p class="muted">{tr('shell.loading')}</p>
		{:else if sharesFailed}
			<p class="muted" role="alert" data-testid="audience-shares-error">
				{tr('audience.loadFailed')}
				<button type="button" class="btn btn-secondary btn-sm" onclick={loadShares}>
					{tr('audience.retry')}
				</button>
			</p>
		{:else if shares.length === 0}
			<p class="muted">{tr('audience.sharedWithNobody')}</p>
		{:else}
			<ul data-testid="audience-shared-list">
				{#each shares as s (s.recipientId)}
					<li class="person">
						<span class="avatar" aria-hidden="true">{initial(s.displayName)}</span>
						<span class="who"><strong>{nameOf(s.displayName)}</strong></span>
						<button
							type="button"
							class="btn btn-outline btn-sm"
							disabled={pendingRecipient !== null}
							aria-label={tr('audience.revokeAria', { name: nameOf(s.displayName) })}
							onclick={() => revoke(s)}
						>
							<span class="material-symbols" aria-hidden="true">person_remove</span>
							{tr('audience.revoke')}
						</button>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	{#if level === 'specific'}
		<section class="add" aria-labelledby="audience-add-heading">
			<h3 id="audience-add-heading">{tr('audience.addPeople')}</h3>
			{#if peopleLoading}
				<p class="muted">{tr('shell.loading')}</p>
			{:else if peopleFailed}
				<p class="muted" role="alert" data-testid="audience-people-error">
					{tr('audience.peopleLoadFailed')}
					<button type="button" class="btn btn-secondary btn-sm" onclick={loadPeople}>
						{tr('audience.retry')}
					</button>
				</p>
			{:else if candidates.length === 0}
				<p class="muted">{tr('audience.noPeople')}</p>
			{:else}
				<label class="search">
					<span class="material-symbols" aria-hidden="true">search</span>
					<input
						type="text"
						bind:value={query}
						placeholder={tr('audience.searchPlaceholder')}
						aria-label={tr('audience.searchPlaceholder')}
						data-testid="audience-search"
					/>
				</label>
				{#if shown.length === 0}
					<p class="muted">{tr('audience.noMatches')}</p>
				{:else}
					<ul data-testid="audience-people">
						{#each shown as p (p.id)}
							<li>
								<button
									type="button"
									class="candidate"
									disabled={pendingRecipient !== null || sharedIds.has(p.id)}
									onclick={() => share(p)}
								>
									<span class="avatar" aria-hidden="true">{initial(p.displayName)}</span>
									<span class="who"><strong>{nameOf(p.displayName)}</strong></span>
									<span class="cta">
										{#if sharedIds.has(p.id)}
											{tr('audience.alreadyShared')}
										{:else if pendingRecipient === p.id}
											{tr('audience.sharing')}
										{:else}
											{tr('audience.share')}
										{/if}
									</span>
								</button>
							</li>
						{/each}
					</ul>
				{/if}
			{/if}
		</section>
	{/if}
</Modal>

<ConfirmDialog
	open={confirmRevokeAll}
	title={tr('audience.revokeAllTitle')}
	message={tr('audience.revokeAllBody')}
	confirmLabel={tr('audience.revokeAllConfirm')}
	onconfirm={confirmOnlyMe}
	oncancel={() => (confirmRevokeAll = false)}
	data-testid="audience-revoke-all-dialog"
	danger
/>

<style>
	.levels {
		display: grid;
		gap: var(--space-xs);
	}
	.level {
		display: flex;
		gap: var(--space-sm);
		align-items: flex-start;
		inline-size: 100%;
		text-align: start;
		background: none;
		color: inherit;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-sm);
		cursor: pointer;
	}
	.level.selected {
		border-color: var(--color-primary);
		background: var(--color-bg-secondary);
	}
	.level:disabled {
		cursor: default;
		opacity: 0.7;
	}
	.level:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.level-text {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
		min-inline-size: 0;
	}
	.hint,
	.muted,
	.note {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.note {
		margin: var(--space-sm) 0 var(--space-md);
	}
	h3 {
		font-size: 0.95rem;
		margin: var(--space-md) 0 var(--space-xs);
	}
	ul {
		list-style: none;
		margin: 0;
		padding: 0;
		max-height: 16rem;
		overflow-y: auto;
	}
	.person {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-xs) 0;
	}
	.candidate {
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
	.candidate:hover:not(:disabled) {
		background: var(--color-bg-secondary);
	}
	.candidate:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.candidate:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
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
	.cta {
		color: var(--color-primary);
		font-size: 0.85rem;
		flex: 0 0 auto;
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
</style>
