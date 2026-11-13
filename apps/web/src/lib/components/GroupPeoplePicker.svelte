<script lang="ts">
	// Picks people to invite to a group (issue #1365 slice 2). The list is the
	// viewer's follow graph in both directions, the people they could message
	// 1:1 without a request (D1); a shared club or event also admits an invite,
	// and the server decides every one with a single refusal (dm_recipients.ts
	// explains why a block is never drawn here).
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import Avatar from '#lib/components/Avatar.svelte';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import { hashHue } from '#lib/format/avatar.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { fetchFollowGraph } from '#lib/core/data.ts';
	import { dmRecipientCandidates, filterDmRecipients, type DmRecipient } from '#lib/social/dm_recipients.ts';

	interface Props {
		selected: string[];
		/// People already in the group or holding an invite.
		exclude?: ReadonlySet<string>;
		/// Seats left; further people cannot be ticked once it is reached.
		max: number;
		disabled?: boolean;
	}

	let { selected = $bindable(), exclude = new Set<string>(), max, disabled = false }: Props = $props();

	let loading = $state(true);
	let loadFailed = $state(false);
	let candidates = $state<DmRecipient[]>([]);
	let query = $state('');

	const available = $derived(candidates.filter((c) => !exclude.has(c.id)));
	const shown = $derived(filterDmRecipients(available, query));
	const full = $derived(selected.length >= max);

	async function load() {
		const me = auth.user?.id;
		if (!me) return;
		loading = true;
		loadFailed = false;
		try {
			const { followers, following } = await fetchFollowGraph(me);
			candidates = dmRecipientCandidates(followers, following, me);
		} catch {
			// "Nobody to invite" and "couldn't find out who" are different answers.
			candidates = [];
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		void load();
	});

	function toggle(id: string, on: boolean) {
		if (on) {
			if (!selected.includes(id) && selected.length < max) selected = [...selected, id];
		} else {
			selected = selected.filter((s) => s !== id);
		}
	}
</script>

<div class="picker" data-testid="group-people-picker">
	{#if loading}
		<p class="muted">{tr('shell.loading')}</p>
	{:else if loadFailed}
		<p class="muted" role="alert">
			{tr('groups.peopleLoadFailed')}
			<button type="button" class="btn btn-secondary btn-sm" onclick={() => void load()}>
				{tr('messages.retry')}
			</button>
		</p>
	{:else if available.length === 0}
		<p class="muted">{tr('groups.peopleEmpty')}</p>
	{:else}
		<AppSearchField bind:value={query} label={tr('groups.peopleSearch')} testid="group-people-search" />
		<p class="count" aria-live="polite" data-testid="group-people-count">
			{tr('groups.peopleSelected', { count: selected.length, max })}
		</p>
		{#if shown.length === 0}
			<p class="muted">{tr('groups.peopleNoMatches')}</p>
		{:else}
			<ul>
				{#each shown as r (r.id)}
					{@const checked = selected.includes(r.id)}
					<li>
						<label class="person" class:checked>
							<input
								type="checkbox"
								{checked}
								disabled={disabled || (!checked && full)}
								onchange={(e) => toggle(r.id, e.currentTarget.checked)}
								data-testid="group-person"
								data-user-id={r.id}
							/>
							<Avatar
								url={r.avatarUrl}
								name={r.displayName}
								size="2rem"
								font="0.85rem"
								bg="seed"
								seedHue={hashHue(r.id)}
							/>
							<span class="who">{r.displayName ?? tr('messages.runnerFallback')}</span>
						</label>
					</li>
				{/each}
			</ul>
		{/if}
		{#if full}
			<p class="muted" data-testid="group-people-full">{tr('groups.peopleFull', { max: max })}</p>
		{/if}
	{/if}
</div>

<style>
	.muted {
		color: var(--color-text-secondary);
	}
	.count {
		margin: var(--space-sm) 0 0;
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
	}
	ul {
		list-style: none;
		margin: var(--space-sm) 0 0;
		padding: 0;
		max-height: 18rem;
		overflow-y: auto;
	}
	.person {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		min-height: 2.75rem;
		padding: var(--space-xs) var(--space-sm);
		border-radius: var(--radius-md);
		cursor: pointer;
	}
	.person:hover,
	.person.checked {
		background: var(--color-bg-secondary);
	}
	.person input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.who {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
</style>
