<script lang="ts">
	// The coach assistant (issue #1215 Phase 4): a private draft for a coach in
	// a conversation with an athlete they coach. Only this coach sees it; "Use
	// draft" puts it in the composer to edit, and the message it becomes is
	// marked AI-assisted. Every refusal says what would unblock it.
	import { m, currentLocale } from '#lib/i18n/store.svelte.ts';
	import { AI_CONSENT_HREF } from '#lib/core/ai_disclosure.ts';
	import { requestCoachAssistDraft } from '#lib/coach/assist/client.ts';
	import { CoachAssistError, type CoachAssistErrorKind } from '#lib/coach/assist/client_kind.ts';
	import type { CoachAssistMode } from '#lib/coach/assist/context.ts';
	import { todayISO } from '#lib/training/training.ts';

	interface Props {
		athleteId: string;
		athleteName: string;
		onuse: (draft: string) => void;
	}

	let { athleteId, athleteName, onuse }: Props = $props();

	let open = $state(false);
	let mode = $state<CoachAssistMode>('reply');
	let request = $state('');
	let busy = $state(false);
	let draft = $state<string | null>(null);
	let failure = $state<CoachAssistErrorKind | null>(null);

	async function run() {
		if (busy) return;
		busy = true;
		failure = null;
		draft = null;
		try {
			draft = await requestCoachAssistDraft({
				athleteId,
				mode,
				request,
				today: todayISO(),
				locale: currentLocale(),
			});
		} catch (e) {
			failure = e instanceof CoachAssistError ? e.kind : 'unavailable';
		} finally {
			busy = false;
		}
	}

	function use() {
		if (!draft) return;
		onuse(draft);
		draft = null;
		open = false;
	}
</script>

<div class="assist" data-testid="coach-assist-panel">
	{#if !open}
		<button type="button" class="btn btn-secondary btn-sm toggle" onclick={() => (open = true)} data-testid="coach-assist-open">
			<span class="material-symbols" aria-hidden="true">auto_awesome</span>
			{m('coachAssist.openPanel')}
		</button>
	{:else}
		<div class="panel">
			<p class="private">{m('coachAssist.privateNote', { name: athleteName })}</p>
			<fieldset class="modes">
				<legend class="visually-hidden">{m('coachAssist.modeLegend')}</legend>
				<label><input type="radio" bind:group={mode} value="reply" /> {m('coachAssist.modeReply')}</label>
				<label><input type="radio" bind:group={mode} value="plan_tweak" /> {m('coachAssist.modePlanTweak')}</label>
			</fieldset>
			<textarea
				bind:value={request}
				rows="2"
				maxlength="500"
				placeholder={m('coachAssist.requestPlaceholder')}
				aria-label={m('coachAssist.requestPlaceholder')}
				data-testid="coach-assist-request"
			></textarea>
			<div class="actions">
				<button type="button" class="btn btn-outline btn-sm" onclick={() => (open = false)}>{m('common.cancel')}</button>
				<button type="button" class="btn btn-primary btn-sm" disabled={busy} onclick={() => void run()} data-testid="coach-assist-run">
					{busy ? m('coachAssist.drafting') : m('coachAssist.draft')}
				</button>
			</div>
			{#if failure}
				<p class="failure" role="alert" data-testid="coach-assist-error">
					{#if failure === 'athlete_consent'}
						{m('coachAssist.errorAthleteConsent', { name: athleteName })}
					{:else if failure === 'coach_consent'}
						{m('coachAssist.errorCoachConsent')} <a href={AI_CONSENT_HREF}>{m('coachAssist.errorCoachConsentLink')}</a>
					{:else if failure === 'upgrade'}
						{m('coachAssist.errorUpgrade')} <a href="/settings/upgrade">{m('coachAssist.errorUpgradeLink')}</a>
					{:else if failure === 'rate_limited'}
						{m('coachAssist.errorRateLimited')}
					{:else if failure === 'not_your_athlete'}
						{m('coachAssist.errorNotYourAthlete')}
					{:else}
						{m('coachAssist.errorUnavailable')}
					{/if}
				</p>
			{/if}
			{#if draft}
				<div class="assist-draft" data-testid="coach-assist-draft">
					<p class="draft-label">{m('coachAssist.draftLabel')}</p>
					<p class="draft-text">{draft}</p>
					<div class="actions">
						<button type="button" class="btn btn-outline btn-sm" onclick={() => (draft = null)}>{m('coachAssist.discard')}</button>
						<button type="button" class="btn btn-primary btn-sm" onclick={use} data-testid="coach-assist-use">{m('coachAssist.use')}</button>
					</div>
				</div>
			{/if}
		</div>
	{/if}
</div>

<style>
	.assist {
		padding: var(--space-xs) var(--space-sm) 0;
	}
	.toggle {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-sm);
	}
	.private,
	.draft-label {
		margin: 0;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.modes {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		border: none;
		margin: 0;
		padding: 0;
	}
	textarea {
		inline-size: 100%;
		resize: vertical;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-xs);
		flex-wrap: wrap;
	}
	.failure {
		margin: 0;
		color: var(--color-danger-text);
	}
	.assist-draft {
		border-inline-start: 3px solid var(--section-coach);
		padding-inline-start: var(--space-sm);
	}
	.draft-text {
		white-space: pre-wrap;
		overflow-wrap: anywhere;
		margin: var(--space-xs) 0;
	}
</style>
