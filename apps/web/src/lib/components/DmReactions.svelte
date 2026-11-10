<script lang="ts">
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import {
		DM_REACTIONS,
		dmReactionGlyph,
		myDmReaction,
		summarizeDmReactions,
		type DmReaction,
		type DmReactionRow
	} from '#lib/social/dm_reactions.ts';

	let {
		messageId,
		rows,
		me,
		canReact,
		onset
	}: {
		messageId: string;
		rows: readonly DmReactionRow[];
		me: string | null;
		canReact: boolean;
		onset: (reaction: DmReaction | null) => void;
	} = $props();

	let picking = $state(false);
	const chips = $derived(summarizeDmReactions(rows, messageId, me));
	const mine = $derived(myDmReaction(rows, messageId, me));

	function choose(reaction: DmReaction) {
		picking = false;
		onset(mine === reaction ? null : reaction);
	}
</script>

{#if chips.length > 0 || canReact}
	<div class="reactions" data-testid="dm-reactions">
		{#each chips as c (c.reaction)}
			<button
				type="button"
				class="chip"
				class:mine={c.mine}
				aria-pressed={c.mine}
				disabled={!canReact}
				aria-label={tr('messages.reactionChipLabel', {
					reaction: tr(`messages.reaction.${c.reaction}`),
					count: c.count
				})}
				onclick={() => choose(c.reaction)}
				data-testid="dm-reaction-chip"
				data-reaction={c.reaction}
			>
				<span aria-hidden="true">{dmReactionGlyph(c.reaction)}</span>
				<span class="count" aria-hidden="true">{c.count}</span>
			</button>
		{/each}
		{#if canReact}
			<button
				type="button"
				class="react"
				aria-expanded={picking}
				onclick={() => (picking = !picking)}
				data-testid="dm-react"
			>{tr('messages.react')}</button>
		{/if}
		{#if picking && canReact}
			<div class="picker" role="group" aria-label={tr('messages.reactPickerLabel')} data-testid="dm-reaction-picker">
				{#each DM_REACTIONS as r (r)}
					<button
						type="button"
						class:mine={mine === r}
						aria-pressed={mine === r}
						aria-label={tr(`messages.reaction.${r}`)}
						onclick={() => choose(r)}
						data-testid="dm-reaction-option"
						data-reaction={r}
					><span aria-hidden="true">{dmReactionGlyph(r)}</span></button>
				{/each}
			</div>
		{/if}
	</div>
{/if}

<style>
	.reactions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.25rem;
		margin-top: 0.25rem;
	}
	.chip,
	.react,
	.picker button {
		min-height: 1.75rem;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		background: var(--color-surface);
		color: var(--color-text);
		padding: 0 0.5rem;
		font-size: 0.8rem;
		cursor: pointer;
	}
	.chip:disabled {
		cursor: default;
	}
	.chip.mine,
	.picker button.mine {
		border-color: var(--color-primary);
	}
	.count {
		margin-inline-start: 0.2rem;
	}
	.picker {
		display: flex;
		gap: 0.25rem;
	}
	.picker button {
		min-width: 2.25rem;
		font-size: 1rem;
	}
</style>
