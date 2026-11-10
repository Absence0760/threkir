<script lang="ts">
	// "Report a problem with this course" (issue #1346, decisions § 2449).
	// Works signed out: park staff need no account. The Edge Function is the
	// trust boundary; this form only spares a round trip on an obvious mistake.
	// Everything typed here is sent as text and shown back only as text.
	import Modal from '../Modal.svelte';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { submitParkCourseReport } from '#lib/core/data.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import {
		COURSE_REPORT_EMAIL_MAX,
		COURSE_REPORT_NOTES_MAX,
		COURSE_REPORT_REASONS,
		COURSE_REPORT_REASON_LABELS,
		courseReportEmailOk,
		type CourseReportReason,
	} from '#lib/parks/course_report.ts';

	interface Props {
		open: boolean;
		courseId: string;
		courseName: string;
		onclose: () => void;
	}

	let { open, courseId, courseName, onclose }: Props = $props();

	let reason = $state<CourseReportReason>('course_hazard');
	let notes = $state('');
	let email = $state('');
	let website = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);

	const emailOk = $derived(courseReportEmailOk(email));
	const canSubmit = $derived(!busy && notes.trim().length > 0 && emailOk);

	function reset() {
		reason = 'course_hazard';
		notes = '';
		email = '';
		website = '';
		error = null;
		busy = false;
	}

	function handleClose() {
		reset();
		onclose();
	}

	async function handleSubmit() {
		if (!canSubmit) return;
		busy = true;
		error = null;
		try {
			await submitParkCourseReport({ courseId, reason, notes, contactEmail: email, website });
			showToast(m('parks.report.sent'), 'success');
			handleClose();
		} catch (e) {
			error = errorCopy(e, m, 'parks.report.errorFailed', 'parks.report.errorFailed');
		} finally {
			busy = false;
		}
	}
</script>

<Modal {open} title={m('parks.report.title')} narrow onclose={handleClose} bodyClass="course-report-body" data-testid="park-course-report-dialog">
	<p class="intro">
		<strong>{courseName}</strong>. {m('parks.report.explainer')}
	</p>

	<fieldset>
		<legend class="section-label">{m('parks.report.reasonLegend')}</legend>
		{#each COURSE_REPORT_REASONS as r (r)}
			<label class="radio">
				<input type="radio" name="course-report-reason" value={r} bind:group={reason} data-testid="park-course-report-reason-{r}" />
				<span>
					<strong>{m(COURSE_REPORT_REASON_LABELS[r])}</strong>
					{#if r === 'land_manager_request'}
						<span class="hint">{m('parks.report.reasonLandManagerHint')}</span>
					{/if}
				</span>
			</label>
		{/each}
	</fieldset>

	<label class="field">
		<span class="section-label">{m('parks.report.notesLabel')}</span>
		<textarea
			bind:value={notes}
			rows="4"
			maxlength={COURSE_REPORT_NOTES_MAX}
			placeholder={m('parks.report.notesPlaceholder')}
			data-testid="park-course-report-notes"
		></textarea>
	</label>

	<label class="field">
		<span class="section-label">{m('parks.report.emailLabel')}</span>
		<input
			type="email"
			autocomplete="email"
			bind:value={email}
			maxlength={COURSE_REPORT_EMAIL_MAX}
			aria-invalid={!emailOk}
			aria-describedby="course-report-email-hint"
			data-testid="park-course-report-email"
		/>
		<span class="hint" id="course-report-email-hint">
			{#if !emailOk}{m('parks.report.errorEmail')}{:else}{m('parks.report.emailHint')}{/if}
			<a href="/privacy">{m('parks.report.privacyLink')}</a>
		</span>
	</label>

	<!-- A person never sees or fills this; the function files nothing when it is set. -->
	<div class="trap" aria-hidden="true">
		<label>
			{m('parks.report.websiteLabel')}
			<input type="text" name="website" tabindex="-1" autocomplete="off" bind:value={website} />
		</label>
	</div>

	{#if error}
		<p class="error" role="alert" data-testid="park-course-report-error">{error}</p>
	{/if}

	<div class="actions">
		<button type="button" class="btn btn-secondary" onclick={handleClose} disabled={busy}>
			{m('parks.report.cancel')}
		</button>
		<button
			type="button"
			class="btn btn-primary"
			onclick={handleSubmit}
			disabled={!canSubmit}
			data-testid="park-course-report-submit"
		>
			{busy ? m('parks.report.submitting') : m('parks.report.submit')}
		</button>
	</div>
</Modal>

<style>
	:global(.course-report-body) {
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
	.intro {
		margin: 0;
		font-size: 0.85rem;
		line-height: 1.45;
		color: var(--color-text-secondary);
	}
	fieldset {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		padding: 0.7rem 0.9rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
	}
	.section-label {
		font-weight: 600;
		font-size: 0.85rem;
	}
	legend.section-label {
		padding: 0 0.3rem;
	}
	.radio {
		display: flex;
		align-items: flex-start;
		gap: 0.5rem;
		font-size: 0.88rem;
		cursor: pointer;
	}
	.radio input {
		margin-top: 0.3rem;
	}
	.radio span {
		display: flex;
		flex-direction: column;
	}
	.hint {
		font-size: 0.8rem;
		line-height: 1.4;
		color: var(--color-text-secondary);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	textarea,
	input[type='email'] {
		padding: 0.5rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		font: inherit;
		color: inherit;
	}
	textarea {
		resize: vertical;
	}
	textarea:focus-visible,
	input[type='email']:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	input[aria-invalid='true'] {
		border-color: var(--color-danger);
	}
	.trap {
		position: absolute;
		left: -10000px;
		width: 1px;
		height: 1px;
		overflow: hidden;
	}
	.error {
		margin: 0;
		padding: 0.5rem 0.7rem;
		border-radius: var(--radius-md);
		background: var(--color-danger-light);
		color: var(--color-danger-text);
		font-size: 0.85rem;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
</style>
