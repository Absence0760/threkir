<script lang="ts">
	// Share with coach (issue #1215 Phase 3): the athlete picks which
	// paragraphs of one Coach answer go to which of their coaches. The server
	// copies the text by index, so what is offered here is the same split.
	import Modal from './Modal.svelte';
	import SharedText from './SharedText.svelte';
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { shareCoachMessage, type CoachAthleteLink } from '#lib/core/data.ts';
	import {
		COACH_SHARE_MAX_CHARS,
		coachAnswerParagraphs,
		coachShareExcerpt,
	} from '#lib/social/coach_share.ts';

	interface Props {
		open: boolean;
		messageId: string;
		content: string;
		coaches: CoachAthleteLink[];
		onclose: () => void;
	}

	let { open, messageId, content, coaches, onclose }: Props = $props();

	const paragraphs = $derived(coachAnswerParagraphs(content));
	let picked = $state<number[]>([]);
	let coachId = $state<string | null>(null);
	let sending = $state(false);
	let sendError = $state<string | null>(null);
	let sentTo = $state<CoachAthleteLink | null>(null);

	$effect(() => {
		if (!open) return;
		picked = paragraphs.map((_, i) => i);
		coachId = coaches[0]?.user_id ?? null;
		sending = false;
		sendError = null;
		sentTo = null;
	});

	const excerpt = $derived(coachShareExcerpt(paragraphs, picked));
	const tooLong = $derived(excerpt.length > COACH_SHARE_MAX_CHARS);

	function nameOf(c: CoachAthleteLink): string {
		return c.display_name ?? tr('messages.runnerFallback');
	}

	function toggle(i: number) {
		picked = picked.includes(i) ? picked.filter((p) => p !== i) : [...picked, i];
	}

	async function send() {
		const coach = coaches.find((c) => c.user_id === coachId);
		if (!coach || picked.length === 0 || tooLong || sending) return;
		sending = true;
		sendError = null;
		try {
			await shareCoachMessage(messageId, coach.user_id, picked);
			sentTo = coach;
		} catch (e) {
			sendError = errorCopy(e, tr, 'CoachShareDialog: send');
		} finally {
			sending = false;
		}
	}
</script>

<Modal {open} {onclose} title={tr('coachShare.title')} data-testid="coach-share-dialog">
	{#if sentTo}
		<p class="sent" data-testid="coach-share-sent">{tr('coachShare.sent', { name: nameOf(sentTo) })}</p>
		<div class="actions">
			<a class="btn btn-primary btn-sm" href={`/messages/${sentTo.user_id}`}>{tr('coachShare.openThread')}</a>
			<button type="button" class="btn btn-outline btn-sm" onclick={onclose}>{tr('coachShare.done')}</button>
		</div>
	{:else}
		<p class="intro">{tr('coachShare.intro')}</p>
		{#if coaches.length > 1}
			<fieldset class="coaches">
				<legend>{tr('coachShare.coachLegend')}</legend>
				{#each coaches as c (c.user_id)}
					<label class="choice">
						<input type="radio" name="coach-share-coach" value={c.user_id} bind:group={coachId} />
						{nameOf(c)}
					</label>
				{/each}
			</fieldset>
		{:else if coaches[0]}
			<p class="to">{tr('coachShare.to', { name: nameOf(coaches[0]) })}</p>
		{/if}
		<fieldset class="paragraphs">
			<legend>{tr('coachShare.paragraphsLegend')}</legend>
			{#each paragraphs as p, i (i)}
				<label class="paragraph" data-testid="coach-share-paragraph">
					<input type="checkbox" checked={picked.includes(i)} onchange={() => toggle(i)} />
					<span class="text"><SharedText text={p} /></span>
				</label>
			{/each}
		</fieldset>
		{#if tooLong}
			<p class="send-error" role="alert">{tr('coachShare.tooLong', { max: COACH_SHARE_MAX_CHARS })}</p>
		{/if}
		{#if sendError}
			<p class="send-error" role="alert" data-testid="coach-share-error">{sendError}</p>
		{/if}
		<p class="note">{tr('coachShare.labelNote')}</p>
		<div class="actions">
			<button type="button" class="btn btn-outline btn-sm" onclick={onclose}>{tr('common.cancel')}</button>
			<button
				type="button"
				class="btn btn-primary btn-sm"
				data-testid="coach-share-send"
				disabled={sending || picked.length === 0 || tooLong || !coachId}
				onclick={() => void send()}
			>
				{sending ? tr('coachShare.sending') : tr('coachShare.send')}
			</button>
		</div>
	{/if}
</Modal>

<style>
	.intro,
	.to,
	.sent {
		margin: 0 0 var(--space-sm);
	}
	.note {
		margin: var(--space-sm) 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	fieldset {
		border: none;
		margin: 0 0 var(--space-sm);
		padding: 0;
	}
	legend {
		font-weight: 600;
		margin-bottom: var(--space-xs);
	}
	.choice {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		padding: var(--space-xs) 0;
	}
	.paragraphs {
		max-height: 22rem;
		overflow-y: auto;
	}
	.paragraph {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		margin-bottom: var(--space-xs);
	}
	.paragraph input {
		margin-top: 0.2rem;
	}
	.text {
		flex: 1 1 auto;
		min-inline-size: 0;
	}
	.send-error {
		color: var(--color-danger-text);
		margin: 0 0 var(--space-sm);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
</style>
