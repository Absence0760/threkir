<script lang="ts">
	// Claim a race, link its course, suggest a course, and review suggestions
	// (issue #1297, decisions § 2381). Every action is a definer RPC that
	// re-checks the caller; this component only decides which to offer.
	import Modal from './Modal.svelte';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { deferDestructive } from '#lib/stores/undo.svelte.ts';
	import {
		claimRaceListing,
		fetchClubRoutes,
		fetchMyClubs,
		fetchMyPublicRoutes,
		fetchMyRaceCourseSuggestion,
		fetchRaceCourseSuggestionsForReview,
		linkRaceCourse,
		reviewRaceCourseSuggestion,
		suggestRaceCourse,
		type RaceCourseSuggestion,
		type RaceListingDetail
	} from '#lib/core/data.ts';
	import {
		organiserClubsOf,
		raceCourseAccess,
		type OrganiserClubCandidate
	} from '#lib/integrations/race_course_access.ts';
	import type { RaceCourseSource } from '#lib/types.ts';

	interface Props {
		race: RaceListingDetail;
		signedIn: boolean;
		/// Called after a write that changes what the race page shows.
		onchanged: () => void;
		/// The review queue (decisions § 2396) offers claim and review only.
		allowSuggest?: boolean;
		/// The runner's organiser clubs, when the caller already read them, so a
		/// page listing many races reads them once.
		organiserClubs?: OrganiserClubCandidate[];
		/// Hides the course on the page while its removal waits out the undo
		/// window; returns the function that puts it back.
		onhidecourse?: () => () => void;
	}
	let {
		race,
		signedIn,
		onchanged,
		allowSuggest = true,
		organiserClubs,
		onhidecourse
	}: Props = $props();

	let myClubs = $state<OrganiserClubCandidate[]>([]);
	let mySuggestionRouteId = $state<string | null>(null);
	let suggestions = $state<RaceCourseSuggestion[]>([]);
	let busy = $state(false);

	const baseAccess = $derived(
		raceCourseAccess({
			signedIn,
			organiserClubId: race.organiser?.id ?? null,
			myOrganiserClubs: myClubs
		})
	);
	const access = $derived({ ...baseAccess, canSuggest: allowSuggest && baseAccess.canSuggest });

	// Auxiliary: a failed read hides the tools, never breaks the race page.
	async function loadContext(listingId: string) {
		if (!signedIn) return;
		if (organiserClubs) {
			myClubs = organiserClubs;
		} else {
			try {
				const clubs = await fetchMyClubs();
				if (race.id === listingId) myClubs = organiserClubsOf(clubs);
			} catch (e) {
				console.error('race course tools: club read failed', e);
			}
		}
		if (allowSuggest) {
			try {
				const mine = await fetchMyRaceCourseSuggestion(listingId);
				if (race.id === listingId) mySuggestionRouteId = mine?.routeId ?? null;
			} catch (e) {
				console.error('race course tools: own suggestion read failed', e);
			}
		}
		await loadSuggestions(listingId);
	}

	async function loadSuggestions(listingId: string) {
		try {
			const rows = await fetchRaceCourseSuggestionsForReview(listingId);
			if (race.id === listingId) suggestions = rows;
		} catch (e) {
			console.error('race course tools: suggestion queue read failed', e);
		}
	}

	$effect(() => {
		const id = race.id;
		myClubs = [];
		mySuggestionRouteId = null;
		suggestions = [];
		void loadContext(id);
	});

	// ── claim ───────────────────────────────────────────────────────────────
	let claimOpen = $state(false);
	let claimClubId = $state<string | null>(null);

	function openClaim() {
		claimClubId = myClubs[0]?.id ?? null;
		claimOpen = true;
	}

	async function submitClaim() {
		if (!claimClubId || busy) return;
		busy = true;
		try {
			await claimRaceListing(race.id, claimClubId);
			claimOpen = false;
			showToast(m('raceCourse.claimed'), 'success');
			onchanged();
		} catch (e) {
			showToast(errorCopy(e, m, 'race claim failed', 'raceCourse.claimFailed'), 'error');
		} finally {
			busy = false;
		}
	}

	// ── link ────────────────────────────────────────────────────────────────
	let linkOpen = $state(false);
	let linkRoutes = $state<{ id: string; name: string }[] | null>(null);
	let linkRouteId = $state<string | null>(null);
	let linkSource = $state<RaceCourseSource>('official');
	/// Set when the link dialog is approving a suggestion rather than linking.
	let approving = $state<RaceCourseSuggestion | null>(null);

	async function openLink(forSuggestion: RaceCourseSuggestion | null = null) {
		approving = forSuggestion;
		linkSource = race.course?.source ?? 'official';
		linkRoutes = null;
		linkOpen = true;
		const clubId = race.organiser?.id;
		if (!clubId) return;
		const routes = await fetchClubRoutes(clubId);
		linkRoutes = routes
			.filter((r) => r.is_public === true)
			.map((r) => ({ id: r.id, name: r.name }));
		const preferred =
			forSuggestion && forSuggestion.routeClubId === clubId
				? forSuggestion.routeId
				: (race.course?.routeId ?? null);
		linkRouteId =
			preferred && linkRoutes.some((r) => r.id === preferred) ? preferred : (linkRoutes[0]?.id ?? null);
	}

	async function submitLink() {
		if (!linkRouteId || busy) return;
		busy = true;
		try {
			if (approving) {
				await reviewRaceCourseSuggestion(approving.id, true, linkRouteId, linkSource);
				showToast(m('raceCourse.reviewApproved'), 'success');
			} else {
				await linkRaceCourse(race.id, linkRouteId, linkSource);
				showToast(m('raceCourse.linked'), 'success');
			}
			linkOpen = false;
			approving = null;
			onchanged();
			void loadSuggestions(race.id);
		} catch (e) {
			showToast(
				errorCopy(e, m, 'race course link failed', approving ? 'raceCourse.reviewFailed' : 'raceCourse.linkFailed'),
				'error'
			);
		} finally {
			busy = false;
		}
	}

	async function markChecked() {
		const routeId = race.course?.routeId;
		if (!routeId || busy) return;
		busy = true;
		try {
			await linkRaceCourse(race.id, routeId, race.course?.source ?? 'official');
			showToast(m('raceCourse.checkedDone'), 'success');
			onchanged();
		} catch (e) {
			showToast(errorCopy(e, m, 'race course check failed', 'raceCourse.linkFailed'), 'error');
		} finally {
			busy = false;
		}
	}

	// Removing the course is held for the undo window rather than confirmed:
	// linking it again would not restore it, because a relink stamps a new
	// checked date (conventions.md § Destructive actions).
	function unlink() {
		if (busy) return;
		const listingId = race.id;
		linkOpen = false;
		const restore = onhidecourse?.();
		deferDestructive({
			message: m('raceCourse.unlinked'),
			commit: async () => {
				await linkRaceCourse(listingId, null, null);
				onchanged();
			},
			restore: () => restore?.(),
			onCommitError: (e) =>
				showToast(errorCopy(e, m, 'race course unlink failed', 'raceCourse.linkFailed'), 'error')
		});
	}

	// A rejected suggestion cannot be put back into the queue, so the reject is
	// held for the undo window too.
	function reject(s: RaceCourseSuggestion) {
		if (busy) return;
		const before = suggestions;
		suggestions = suggestions.filter((x) => x.id !== s.id);
		deferDestructive({
			message: m('raceCourse.reviewRejected'),
			commit: async () => {
				await reviewRaceCourseSuggestion(s.id, false);
				onchanged();
			},
			restore: () => {
				suggestions = before;
			},
			onCommitError: (e) =>
				showToast(errorCopy(e, m, 'race course reject failed', 'raceCourse.reviewFailed'), 'error')
		});
	}

	// ── suggest ─────────────────────────────────────────────────────────────
	let suggestOpen = $state(false);
	let suggestRoutes = $state<{ id: string; name: string }[] | null>(null);
	let suggestRouteId = $state<string | null>(null);
	let suggestNote = $state('');

	async function openSuggest() {
		suggestRoutes = null;
		suggestNote = '';
		suggestOpen = true;
		try {
			suggestRoutes = await fetchMyPublicRoutes();
		} catch (e) {
			console.error('race course tools: own routes read failed', e);
			suggestRoutes = [];
		}
		suggestRouteId =
			mySuggestionRouteId && suggestRoutes.some((r) => r.id === mySuggestionRouteId)
				? mySuggestionRouteId
				: (suggestRoutes[0]?.id ?? null);
	}

	async function submitSuggest() {
		if (!suggestRouteId || busy) return;
		busy = true;
		try {
			await suggestRaceCourse(race.id, suggestRouteId, suggestNote);
			mySuggestionRouteId = suggestRouteId;
			suggestOpen = false;
			showToast(m('raceCourse.suggested'), 'success');
			void loadSuggestions(race.id);
		} catch (e) {
			showToast(errorCopy(e, m, 'race course suggest failed', 'raceCourse.suggestFailed'), 'error');
		} finally {
			busy = false;
		}
	}
</script>

{#if access.canClaim || access.canManage || access.canSuggest || suggestions.length > 0}
	<section class="tools" aria-labelledby="race-course-tools-heading" data-testid="race-course-tools">
		<h2 id="race-course-tools-heading">{m('raceCourse.toolsHeading')}</h2>
		<div class="actions">
			{#if access.canClaim}
				<button type="button" class="btn btn-outline" onclick={openClaim} data-testid="race-course-claim">
					{m('raceCourse.claim')}
				</button>
			{/if}
			{#if access.canManage}
				<button type="button" class="btn btn-outline" onclick={() => void openLink()} data-testid="race-course-link">
					{race.course?.routeId ? m('raceCourse.changeCourse') : m('raceCourse.linkCourse')}
				</button>
				{#if race.course?.routeId}
					<button
						type="button"
						class="btn btn-outline"
						onclick={markChecked}
						disabled={busy}
						data-testid="race-course-mark-checked"
					>
						{m('raceCourse.markChecked')}
					</button>
				{/if}
			{/if}
			{#if access.canSuggest}
				<button type="button" class="btn btn-outline" onclick={openSuggest} data-testid="race-course-suggest">
					{m('raceCourse.suggest')}
				</button>
			{/if}
		</div>
		{#if access.canSuggest && mySuggestionRouteId}
			<p class="hint" data-testid="race-course-suggest-pending">{m('raceCourse.suggestPending')}</p>
		{/if}

		{#if suggestions.length > 0}
			<h3>{m('raceCourse.reviewHeading')}</h3>
			{#if !access.canManage}
				<p class="hint" data-testid="race-course-review-claim-first">{m('raceCourse.reviewClaimFirst')}</p>
			{/if}
			<ul class="suggestions" data-testid="race-course-suggestions">
				{#each suggestions as s (s.id)}
					<li class="suggestion">
						<a href="/routes/{s.routeId}">{s.routeName}</a>
						{#if s.note}<span class="note">{s.note}</span>{/if}
						{#if access.canManage}
							<span class="actions">
								<button
									type="button"
									class="btn btn-primary btn-sm"
									onclick={() => void openLink(s)}
									disabled={busy}
									data-testid="race-course-approve"
								>
									{m('raceCourse.reviewApprove')}
								</button>
								<button
									type="button"
									class="btn btn-outline btn-sm"
									onclick={() => reject(s)}
									disabled={busy}
									data-testid="race-course-reject"
								>
									{m('raceCourse.reviewReject')}
								</button>
							</span>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</section>
{/if}

<Modal open={claimOpen} title={m('raceCourse.claimTitle')} narrow onclose={() => (claimOpen = false)}>
	<div class="editor-form dialog-body">
		<p class="hint">{m('raceCourse.claimBody')}</p>
		<label>
			<span>{m('raceCourse.claimClub')}</span>
			<select bind:value={claimClubId} data-testid="race-course-claim-club">
				{#each myClubs as c (c.id)}
					<option value={c.id}>{c.name}</option>
				{/each}
			</select>
		</label>
		<div class="dialog-actions">
			<button type="button" class="btn btn-secondary" onclick={() => (claimOpen = false)} disabled={busy}>
				{m('common.cancel')}
			</button>
			<button
				type="button"
				class="btn btn-primary"
				onclick={submitClaim}
				disabled={busy || !claimClubId}
				data-testid="race-course-claim-confirm"
			>
				{m('raceCourse.claimConfirm')}
			</button>
		</div>
	</div>
</Modal>

<Modal
	open={linkOpen}
	title={approving ? m('raceCourse.reviewApproveTitle') : m('raceCourse.linkTitle')}
	narrow
	onclose={() => {
		linkOpen = false;
		approving = null;
	}}
>
	<div class="editor-form dialog-body">
		{#if approving}
			<p class="hint">{m('raceCourse.reviewApproveBody', { route: approving.routeName })}</p>
		{/if}
		{#if linkRoutes === null}
			<p class="hint">{m('races.loading')}</p>
		{:else if linkRoutes.length === 0}
			<p class="hint" data-testid="race-course-link-empty">{m('raceCourse.linkNoRoutes')}</p>
		{:else}
			<label>
				<span>{m('raceCourse.linkRoute')}</span>
				<select bind:value={linkRouteId} data-testid="race-course-link-route">
					{#each linkRoutes as r (r.id)}
						<option value={r.id}>{r.name}</option>
					{/each}
				</select>
			</label>
			<fieldset>
				<legend>{m('raceCourse.linkSourceLabel')}</legend>
				<label class="radio">
					<input type="radio" name="race-course-source" value="official" bind:group={linkSource} />
					<span>{m('raceCourse.sourceOptionOfficial')}</span>
				</label>
				<label class="radio">
					<input
						type="radio"
						name="race-course-source"
						value="traced"
						bind:group={linkSource}
						data-testid="race-course-source-traced"
					/>
					<span>{m('raceCourse.sourceOptionTraced')}</span>
				</label>
			</fieldset>
		{/if}
		<div class="dialog-actions">
			{#if !approving && race.course?.routeId}
				<button
					type="button"
					class="btn btn-outline"
					onclick={unlink}
					disabled={busy}
					data-testid="race-course-unlink"
				>
					{m('raceCourse.unlink')}
				</button>
			{/if}
			<button
				type="button"
				class="btn btn-secondary"
				onclick={() => {
					linkOpen = false;
					approving = null;
				}}
				disabled={busy}
			>
				{m('common.cancel')}
			</button>
			<button
				type="button"
				class="btn btn-primary"
				onclick={submitLink}
				disabled={busy || !linkRouteId}
				data-testid="race-course-link-confirm"
			>
				{approving ? m('raceCourse.reviewApprove') : m('raceCourse.linkConfirm')}
			</button>
		</div>
	</div>
</Modal>

<Modal open={suggestOpen} title={m('raceCourse.suggestTitle')} narrow onclose={() => (suggestOpen = false)}>
	<div class="editor-form dialog-body">
		<p class="hint">{m('raceCourse.suggestBody')}</p>
		{#if suggestRoutes === null}
			<p class="hint">{m('races.loading')}</p>
		{:else if suggestRoutes.length === 0}
			<p class="hint" data-testid="race-course-suggest-empty">{m('raceCourse.suggestNoRoutes')}</p>
		{:else}
			<label>
				<span>{m('raceCourse.suggestRoute')}</span>
				<select bind:value={suggestRouteId} data-testid="race-course-suggest-route">
					{#each suggestRoutes as r (r.id)}
						<option value={r.id}>{r.name}</option>
					{/each}
				</select>
			</label>
			<label>
				<span>{m('raceCourse.suggestNote')}</span>
				<textarea bind:value={suggestNote} rows="3" maxlength="500" data-testid="race-course-suggest-note"
				></textarea>
			</label>
		{/if}
		<div class="dialog-actions">
			<button type="button" class="btn btn-secondary" onclick={() => (suggestOpen = false)} disabled={busy}>
				{m('common.cancel')}
			</button>
			<button
				type="button"
				class="btn btn-primary"
				onclick={submitSuggest}
				disabled={busy || !suggestRouteId}
				data-testid="race-course-suggest-confirm"
			>
				{m('raceCourse.suggestConfirm')}
			</button>
		</div>
	</div>
</Modal>

<style>
	.tools {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.tools h2 {
		font-size: 1.1rem;
		margin: 0;
	}
	.tools h3 {
		font-size: 1rem;
		margin: var(--space-sm) 0 0;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.hint {
		color: var(--color-text-secondary);
		margin: 0;
	}
	.suggestions {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.suggestion {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
	}
	.note {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		overflow-wrap: anywhere;
	}
	.dialog-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
</style>
