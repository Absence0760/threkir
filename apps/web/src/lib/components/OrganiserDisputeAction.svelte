<script lang="ts">
	// "Report as your organisation" (issue #1363, decisions § 2441). Rendered
	// only for an owner or admin of a verified club other than the one the
	// content belongs to; submit_organiser_dispute is the real gate.
	import Modal from './Modal.svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { fetchMyClubs, submitOrganiserDispute } from '#lib/core/data.ts';
	import { organiserClubsOf, type OrganiserClubCandidate } from '#lib/integrations/race_course_access.ts';
	import { DISPUTE_NOTES_MAX, disputeClubsFor } from '#lib/social/organiser_dispute.ts';
	import type { OrganiserDisputeTargetKind } from '#lib/types.ts';

	interface Props {
		targetKind: OrganiserDisputeTargetKind;
		targetId: string;
		targetLabel?: string;
		/// The club the content belongs to (a club is its own), so the
		/// organiser is not offered a dispute against itself.
		targetClubId?: string | null;
		/// Who answers for the content, when the page knows; their own content
		/// is never offered.
		ownerId?: string | null;
		/// The runner's organiser clubs, when the page already read them.
		organiserClubs?: OrganiserClubCandidate[];
	}

	let { targetKind, targetId, targetLabel, targetClubId = null, ownerId = null, organiserClubs }: Props =
		$props();

	let loaded = $state<OrganiserClubCandidate[]>([]);
	let open = $state(false);
	let clubId = $state<string | null>(null);
	let notes = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);

	const clubs = $derived(
		ownerId != null && auth.user?.id === ownerId ? [] : disputeClubsFor(organiserClubs ?? loaded, targetClubId),
	);

	// Auxiliary: a failed read hides the action, never breaks the page.
	$effect(() => {
		if (organiserClubs || !auth.loggedIn) return;
		let live = true;
		fetchMyClubs()
			.then((rows) => {
				if (live) loaded = organiserClubsOf(rows);
			})
			.catch((e) => console.error('organiser dispute: club read failed', e));
		return () => {
			live = false;
		};
	});

	function openDialog() {
		clubId = clubs[0]?.id ?? null;
		notes = '';
		error = null;
		open = true;
	}

	function close() {
		if (busy) return;
		open = false;
	}

	async function submit() {
		if (busy || !clubId) return;
		busy = true;
		error = null;
		try {
			await submitOrganiserDispute({ targetKind, targetId, clubId, notes });
			open = false;
			showToast(m('organiserDispute.toastSubmitted'), 'success');
		} catch (e) {
			error = errorCopy(e, m, 'organiser dispute failed', 'organiserDispute.errorSubmitFailed');
		} finally {
			busy = false;
		}
	}
</script>

{#if clubs.length > 0}
	<button
		type="button"
		class="btn btn-outline btn-sm"
		data-testid="organiser-dispute-open"
		onclick={openDialog}
	>{m('organiserDispute.action')}</button>

	<Modal {open} title={m('organiserDispute.title')} narrow onclose={close} bodyClass="dispute-body">
		<p class="lead">
			{#if targetLabel}
				{m('reportDialog.reportingPrefix')} <strong>{targetLabel}</strong>.
			{/if}
			{m('organiserDispute.explainer')}
		</p>

		{#if clubs.length > 1}
			<label class="field">
				<span class="section-label">{m('organiserDispute.clubLabel')}</span>
				<select bind:value={clubId} data-testid="organiser-dispute-club">
					{#each clubs as c (c.id)}
						<option value={c.id}>{c.name}</option>
					{/each}
				</select>
			</label>
		{:else}
			<p class="as-club" data-testid="organiser-dispute-as">
				{m('organiserDispute.asClub', { club: clubs[0].name })}
			</p>
		{/if}

		<label class="field">
			<span class="section-label">{m('organiserDispute.notesLabel')}</span>
			<textarea
				bind:value={notes}
				rows="3"
				maxlength={DISPUTE_NOTES_MAX}
				placeholder={m('organiserDispute.notesPlaceholder')}
				data-testid="organiser-dispute-notes"
			></textarea>
		</label>

		<p class="hint">{m('organiserDispute.reviewNotice')}</p>

		{#if error}
			<p class="error" role="alert">{error}</p>
		{/if}

		<div class="actions">
			<button type="button" class="btn btn-secondary" onclick={close} disabled={busy}>
				{m('reportDialog.cancel')}
			</button>
			<button
				type="button"
				class="btn btn-primary"
				onclick={submit}
				disabled={busy || !clubId}
				data-testid="organiser-dispute-submit"
			>{busy ? m('reportDialog.submitting') : m('reportDialog.submit')}</button>
		</div>
	</Modal>
{/if}

<style>
	:global(.dispute-body) {
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
	.lead,
	.hint,
	.as-club {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.45;
		margin: 0;
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.section-label {
		font-weight: 600;
		font-size: 0.85rem;
	}
	select,
	textarea {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.5rem 0.7rem;
		font: inherit;
		color: inherit;
	}
	textarea {
		resize: vertical;
	}
	select:focus-visible,
	textarea:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.error {
		color: var(--color-danger-text);
		background: var(--color-danger-light);
		padding: 0.5rem 0.7rem;
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		margin: 0;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
</style>
