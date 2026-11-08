<script lang="ts">
	// A club's official verification (issue #1190 § 2, decisions § 2398), shown
	// to the club's owner and admins on the club page. The owner requests,
	// proves the domain and withdraws; an admin sees the status read-only. The
	// review itself happens at /admin/club-verification.
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import {
		checkClubVerificationProof,
		fetchClubVerificationRequests,
		sendClubVerificationEmail,
		submitClubVerification,
		withdrawClubVerification,
	} from '#lib/core/data.ts';
	import {
		checkResultKey,
		type ClubVerificationRequest,
		isLapseReason,
		normaliseEmailLocalPart,
		proofInstructions,
		readVerificationState,
	} from '#lib/social/club_verification.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';

	interface Props {
		club: {
			id: string;
			name: string;
			is_verified: boolean;
			website_url: string | null;
		};
		isOwner: boolean;
	}

	let { club, isOwner }: Props = $props();

	let rows = $state<ClubVerificationRequest[]>([]);
	let loading = $state(true);
	let loadError = $state(false);
	let busy = $state(false);
	let organisation = $state('');
	let note = $state('');
	let localPart = $state('');
	let checkMessage = $state<string | null>(null);
	let emailMessage = $state<string | null>(null);
	let formError = $state<string | null>(null);
	let showWithdraw = $state(false);

	const vstate = $derived(readVerificationState(rows));
	const live = $derived(vstate.live);
	const lastClosed = $derived(vstate.lastClosed);
	const proof = $derived(live && live.status === 'pending' ? proofInstructions(live.domain, live.token) : null);
	const websiteHost = $derived(hostOf(club.website_url));

	function hostOf(url: string | null): string | null {
		if (!url) return null;
		try {
			return new URL(url).hostname.replace(/^www\./, '').toLowerCase();
		} catch {
			return null;
		}
	}

	function methodLabel(method: string | null): string {
		switch (method) {
			case 'dns_txt':
				return m('clubVerification.method.dns_txt');
			case 'well_known':
				return m('clubVerification.method.well_known');
			case 'email':
				return m('clubVerification.method.email');
			case 'manual':
				return m('clubVerification.method.manual');
			default:
				return '';
		}
	}

	function closedLine(r: ClubVerificationRequest): string {
		switch (r.status) {
			case 'rejected':
				return m('clubVerification.statusRejected', { reason: r.decision_reason ?? '' });
			case 'revoked':
				return m('clubVerification.statusRevoked', { reason: r.close_reason ?? '' });
			case 'lapsed':
				return isLapseReason(r.close_reason)
					? m(`clubVerification.statusLapsed.${r.close_reason}` as MessageKey, { domain: r.domain })
					: m('clubVerification.statusRevoked', { reason: r.close_reason ?? '' });
			case 'withdrawn':
				return m('clubVerification.statusWithdrawn');
			default:
				return '';
		}
	}

	async function load() {
		loadError = false;
		try {
			rows = await fetchClubVerificationRequests(club.id);
		} catch (e) {
			console.error('club verification load failed', e);
			loadError = true;
		} finally {
			loading = false;
		}
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy) return;
		formError = null;
		if (organisation.trim() === '') {
			formError = m('clubVerification.organisationRequired');
			return;
		}
		busy = true;
		try {
			await submitClubVerification(club.id, organisation.trim(), note.trim() || null);
			organisation = '';
			note = '';
			await load();
		} catch (e) {
			formError = errorCopy(e, m, 'club verification submit failed');
		} finally {
			busy = false;
		}
	}

	async function checkNow() {
		if (!live || busy) return;
		busy = true;
		checkMessage = null;
		try {
			const result = await checkClubVerificationProof(live.id);
			checkMessage = m(checkResultKey(result) as MessageKey);
			await load();
		} catch (e) {
			checkMessage = errorCopy(e, m, 'club verification check failed', 'clubVerification.checkFailed');
		} finally {
			busy = false;
		}
	}

	async function sendEmail(event: SubmitEvent) {
		event.preventDefault();
		if (!live || busy) return;
		emailMessage = null;
		const local = normaliseEmailLocalPart(localPart);
		if (!local) {
			emailMessage = m('clubVerification.emailInvalid');
			return;
		}
		busy = true;
		try {
			await sendClubVerificationEmail(live.id, local);
			emailMessage = m('clubVerification.emailSent', { address: `${local}@${live.domain}` });
			localPart = '';
		} catch (e) {
			emailMessage = errorCopy(e, m, 'club verification email failed');
		} finally {
			busy = false;
		}
	}

	async function confirmWithdraw() {
		if (!live) return;
		showWithdraw = false;
		busy = true;
		try {
			await withdrawClubVerification(live.id);
			checkMessage = null;
			emailMessage = null;
			await load();
		} catch (e) {
			showToast(m('clubVerification.actionFailed', { error: errorCopy(e, m, 'club verification withdraw failed') }), 'error');
		} finally {
			busy = false;
		}
	}

	async function copy(text: string) {
		try {
			await navigator.clipboard.writeText(text);
			showToast(m('clubVerification.copied'), 'success');
		} catch (e) {
			console.error('club verification copy failed', e);
			showToast(m('clubHome.copyFailed'), 'error');
		}
	}

	onMount(load);
</script>

<section class="verification-card" data-testid="club-verification-card" aria-labelledby="club-verification-title">
	<div class="card-title">
		<span class="material-symbols" aria-hidden="true">verified</span>
		<h2 id="club-verification-title">{m('clubVerification.title')}</h2>
	</div>

	{#if loading}
		<p class="muted">…</p>
	{:else if loadError}
		<p class="error" role="alert">
			{m('clubVerification.loadFailed')}
			<button class="btn-secondary btn-sm" type="button" onclick={load}>{m('clubVerification.retry')}</button>
		</p>
	{:else if club.is_verified}
		<p data-testid="club-verification-verified">
			{live && live.status === 'approved'
				? m('clubVerification.verifiedAs', { org: live.organisation, domain: live.domain })
				: m('clubVerification.verifiedLegacy')}
		</p>
		<p class="muted">{m('clubVerification.lockNote')}</p>
	{:else if live && live.status === 'pending' && proof}
		<div data-testid="club-verification-pending">
			<p class="status">
				<strong>{m('clubVerification.pendingTitle')}</strong>
				· {live.organisation}
			</p>
			<p class="muted">{m('clubVerification.pendingBody', { domain: live.domain })}</p>
			<p class="proof-status" data-testid="club-verification-proof">
				{live.proof_verified_at
					? m('clubVerification.proofFound', { method: methodLabel(live.proof_method) })
					: m('clubVerification.proofNone')}
			</p>

			{#if isOwner}
				<div class="method">
					<h3>{m('clubVerification.dnsTitle')}</h3>
					<dl>
						<dt>{m('clubVerification.dnsName')}</dt>
						<dd>
							<code data-testid="club-verification-txt-name">{proof.txtName}</code>
							<button class="btn-secondary btn-sm" type="button" onclick={() => copy(proof.txtName)}>
								{m('clubVerification.copy')}
							</button>
						</dd>
						<dt>{m('clubVerification.dnsValue')}</dt>
						<dd>
							<code data-testid="club-verification-txt-value">{proof.txtValue}</code>
							<button class="btn-secondary btn-sm" type="button" onclick={() => copy(proof.txtValue)}>
								{m('clubVerification.copy')}
							</button>
						</dd>
					</dl>
				</div>
				<div class="method">
					<h3>{m('clubVerification.fileTitle')}</h3>
					<dl>
						<dt>{m('clubVerification.fileUrl')}</dt>
						<dd><code>{proof.fileUrl}</code></dd>
						<dt>{m('clubVerification.fileBody')}</dt>
						<dd>
							<code>{proof.fileBody}</code>
							<button class="btn-secondary btn-sm" type="button" onclick={() => copy(proof.fileBody)}>
								{m('clubVerification.copy')}
							</button>
						</dd>
					</dl>
				</div>
				<div class="actions">
					<button class="btn-primary btn-sm" type="button" onclick={checkNow} disabled={busy} data-testid="club-verification-check">
						{busy ? m('clubVerification.checking') : m('clubVerification.checkNow')}
					</button>
				</div>
				{#if checkMessage}
					<p class="result" role="status" data-testid="club-verification-check-result">{checkMessage}</p>
				{/if}

				<form class="method editor-form" onsubmit={sendEmail}>
					<h3>{m('clubVerification.emailTitle')}</h3>
					<p class="muted">{m('clubVerification.emailHint', { domain: live.domain })}</p>
					<label for="club-verification-local">{m('clubVerification.emailLocalLabel', { domain: live.domain })}</label>
					<div class="email-row">
						<input
							id="club-verification-local"
							type="text"
							autocomplete="off"
							spellcheck="false"
							maxlength="64"
							bind:value={localPart}
							data-testid="club-verification-local"
						/>
						<span class="at-domain">@{live.domain}</span>
						<button class="btn-secondary btn-sm" type="submit" disabled={busy} data-testid="club-verification-send">
							{m('clubVerification.emailSend')}
						</button>
					</div>
					{#if emailMessage}
						<p class="result" role="status" data-testid="club-verification-email-result">{emailMessage}</p>
					{/if}
				</form>

				<div class="actions">
					<button class="btn-secondary btn-sm" type="button" onclick={() => (showWithdraw = true)} disabled={busy} data-testid="club-verification-withdraw">
						{m('clubVerification.withdraw')}
					</button>
				</div>
			{/if}
		</div>
	{:else}
		{#if lastClosed}
			<p class="closed" data-testid="club-verification-last">{closedLine(lastClosed)}</p>
		{/if}
		<p class="muted">{m('clubVerification.intro')}</p>
		{#if !isOwner}
			<p class="muted">{m('clubVerification.ownerOnly')}</p>
		{:else if !websiteHost}
			<p class="muted" data-testid="club-verification-needs-website">{m('clubVerification.websiteRequired')}</p>
		{:else}
			<form class="editor-form" onsubmit={submit} data-testid="club-verification-form">
				<p class="muted">{m('clubVerification.domainLine', { domain: websiteHost })}</p>
				<label for="club-verification-org">{m('clubVerification.organisationLabel')}</label>
				<input
					id="club-verification-org"
					type="text"
					maxlength="120"
					placeholder={m('clubVerification.organisationPlaceholder')}
					bind:value={organisation}
					data-testid="club-verification-org"
				/>
				<label for="club-verification-note">{m('clubVerification.noteLabel')}</label>
				<textarea id="club-verification-note" rows="2" maxlength="1000" bind:value={note}></textarea>
				{#if formError}
					<p class="error" role="alert">{formError}</p>
				{/if}
				<div class="actions">
					<button class="btn-primary btn-sm" type="submit" disabled={busy} data-testid="club-verification-submit">
						{busy ? m('clubVerification.submitting') : m('clubVerification.submit')}
					</button>
				</div>
			</form>
		{/if}
	{/if}
</section>

<ConfirmDialog
	open={showWithdraw}
	title={m('clubVerification.withdrawTitle')}
	message={m('clubVerification.withdrawBody')}
	confirmLabel={m('clubVerification.withdrawConfirm')}
	onconfirm={confirmWithdraw}
	oncancel={() => (showWithdraw = false)}
	danger
	data-testid="club-verification-withdraw-dialog"
/>

<style>
	.verification-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}

	.card-title {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin-bottom: 0.6rem;
	}

	.card-title h2 {
		font-size: 1rem;
		margin: 0;
	}

	.method {
		margin-top: var(--space-md);
	}

	.method h3 {
		font-size: 0.9rem;
		margin: 0 0 0.4rem;
	}

	dl {
		display: grid;
		grid-template-columns: max-content minmax(0, 1fr);
		gap: 0.35rem 0.75rem;
		margin: 0;
	}

	dt {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}

	dd {
		margin: 0;
		display: flex;
		gap: 0.4rem;
		align-items: center;
		flex-wrap: wrap;
		min-width: 0;
	}

	code {
		background: var(--color-bg-secondary);
		padding: 0.25rem 0.5rem;
		border-radius: var(--radius-md);
		font-size: 0.82rem;
		overflow-wrap: anywhere;
	}

	.email-row {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		flex-wrap: wrap;
	}

	.email-row input {
		flex: 1 1 8rem;
		min-width: 0;
	}

	.at-domain {
		color: var(--color-text-secondary);
		overflow-wrap: anywhere;
	}

	.actions {
		display: flex;
		gap: 0.5rem;
		margin-top: var(--space-sm);
	}

	.muted {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}

	.status,
	.proof-status,
	.closed,
	.result {
		margin: 0.4rem 0;
	}

	.error {
		color: var(--color-danger-text);
	}
</style>
