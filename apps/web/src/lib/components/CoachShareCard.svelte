<script lang="ts">
	// A Coach answer the athlete shared with their coach (issue #1215 Phase 3):
	// a quote labelled as AI output on both sides (Art. 50), drawn as text.
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import AiTag from './AiTag.svelte';
	import SharedText from './SharedText.svelte';
	import { fetchCoachMessagePlanId } from '#lib/core/data.ts';

	interface Props {
		body: string;
		mine: boolean;
		/// The sender's own Coach answer, readable only by the sender. Null for
		/// the coach, and once the answer was deleted or the card unsent.
		coachMessageId: string | null;
		partnerName: string;
	}

	let { body, mine, coachMessageId, partnerName }: Props = $props();

	let sourceHref = $state('/messages/coach');
	$effect(() => {
		if (!mine || !coachMessageId) return;
		let live = true;
		fetchCoachMessagePlanId(coachMessageId)
			.then((planId) => {
				if (live && planId) sourceHref = `/messages/coach?plan=${encodeURIComponent(planId)}`;
			})
			.catch((e) => console.error('[coach-share] source lookup failed', e));
		return () => {
			live = false;
		};
	});
</script>

<figure class="share" data-testid="dm-coach-share">
	<figcaption class="byline">
		<span class="ai-avatar" aria-hidden="true"><span class="material-symbols">sports</span></span>
		<span class="label">{tr('coachShare.cardLabel')}</span>
		<AiTag />
	</figcaption>
	<p class="from">
		{mine ? tr('coachShare.cardFromMe') : tr('coachShare.cardFromAthlete', { name: partnerName })}
	</p>
	<blockquote>
		<SharedText text={body} />
	</blockquote>
	{#if mine && coachMessageId}
		<a class="source" href={sourceHref} data-testid="dm-coach-share-source">{tr('coachShare.openSource')}</a>
	{/if}
</figure>

<style>
	.share {
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		min-inline-size: 0;
	}
	.byline {
		display: flex;
		align-items: center;
		gap: 0.35rem;
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
	}
	.label {
		font-weight: 600;
	}
	.ai-avatar {
		width: 1.35rem;
		height: 1.35rem;
		border-radius: 50%;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background: color-mix(in srgb, var(--section-coach) 14%, var(--color-surface));
		color: var(--section-coach-ink);
	}
	.ai-avatar .material-symbols {
		font-size: 0.85rem;
	}
	.from {
		margin: 0;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	blockquote {
		margin: 0;
		padding: 0.4rem 0.6rem;
		border-inline-start: 3px solid var(--section-coach);
		background: color-mix(in srgb, var(--section-coach) 6%, transparent);
		border-radius: var(--radius-sm);
	}
	.source {
		font-size: 0.8rem;
		align-self: flex-start;
	}
</style>
