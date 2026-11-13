<script lang="ts">
	// The athlete's consent to the coach assistant on one coaching link (issue
	// #1215 Phase 4). Off until the athlete turns it on; turning it off
	// withdraws at once. The copy names every lane COACH_ASSIST_REGISTRY sends.
	import { m } from '#lib/i18n/store.svelte.ts';
	import ListRow from '#lib/components/ListRow.svelte';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { setCoachAiAssistConsent } from '#lib/core/data.ts';
	import { COACH_ASSIST_CONSENT_VERSION } from '#lib/coach/assist/consent.ts';

	interface Props {
		linkId: string;
		coachName: string;
		version: number | null;
		onchange: (version: number | null) => void;
	}

	let { linkId, coachName, version, onchange }: Props = $props();

	let busy = $state(false);
	let error = $state<string | null>(null);
	const on = $derived(version !== null && version >= 1);

	async function toggle() {
		if (busy) return;
		busy = true;
		error = null;
		try {
			onchange(await setCoachAiAssistConsent(linkId, on ? null : COACH_ASSIST_CONSENT_VERSION));
		} catch (e) {
			error = errorCopy(e, m, 'CoachAssistConsent: toggle');
		} finally {
			busy = false;
		}
	}
</script>

<div class="assist-consent" data-testid="coach-assist-consent">
	<ListRow
		kind="toggle"
		title={m('coachAssist.consentToggle', { name: coachName })}
		checked={on}
		disabled={busy}
		onchange={() => void toggle()}
		testid="coach-assist-consent-toggle"
	/>
	<details>
		<summary>{m('coachAssist.consentWhat')}</summary>
		<p>
			{m('coachAssist.consentIntroPrefix', { name: coachName })}<strong>Anthropic</strong>{m(
				'coachAssist.consentIntroSuffix',
			)}
		</p>
		<ul>
			<li>{m('coachAssist.consentBulletThread')}</li>
			<li>{m('coachAssist.consentBulletPlan')}</li>
			<li>{m('coachAssist.consentBulletRuns')}</li>
		</ul>
		<p>{m('coachAssist.consentOutro', { name: coachName })}</p>
	</details>
	{#if error}<p class="error" role="alert">{error}</p>{/if}
</div>

<style>
	.assist-consent {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		font-size: 0.85rem;
		padding-inline-start: 3rem;
	}
	details p,
	details ul {
		margin: var(--space-xs) 0;
		color: var(--color-text-secondary);
	}
	.error {
		color: var(--color-danger-text);
		margin: 0;
	}
</style>
