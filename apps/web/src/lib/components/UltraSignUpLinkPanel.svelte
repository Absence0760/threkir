<script lang="ts">
	// Settings → Integrations: the runner says who they are on UltraSignup.
	//
	// UltraSignup's results feed is keyed by name and answers with everyone who
	// shares it, so linking is two steps — type the name you race under, then
	// pick yourself from the people UltraSignup returns. The pick is stored on
	// the runner's `integrations` row; every per-race import on /races uses it
	// (decisions § 1841).
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { deferDestructive } from '#lib/stores/undo.svelte.ts';
	import {
		fetchUltraSignUpLink,
		linkUltraSignUpPerson,
		lookupUltraSignUpPeople,
		unlinkUltraSignUpPerson
	} from '#lib/core/data.ts';
	import {
		linkFromCandidate,
		ULTRASIGNUP_NAME_MAX_LEN,
		ultraSignUpNameReady,
		type UltraSignUpCandidate,
		type UltraSignUpPersonLink
	} from '#lib/integrations/ultrasignup_person.ts';

	// `undefined` until the stored link has been read, so the panel never
	// flashes the search form at a runner who is already linked.
	let link = $state<UltraSignUpPersonLink | null | undefined>(undefined);
	let firstName = $state('');
	let lastName = $state('');
	let searching = $state(false);
	let saving = $state(false);
	// `null` = no search run yet; `[]` = searched and nobody answered.
	let candidates = $state<UltraSignUpCandidate[] | null>(null);

	onMount(async () => {
		try {
			link = await fetchUltraSignUpLink();
		} catch {
			link = null;
		}
	});

	async function search(e: SubmitEvent) {
		e.preventDefault();
		if (searching || !ultraSignUpNameReady(firstName, lastName)) return;
		searching = true;
		try {
			candidates = await lookupUltraSignUpPeople(firstName, lastName);
		} catch {
			candidates = null;
			showToast(m('integrations.ultrasignupLookupFailed'), 'error');
		} finally {
			searching = false;
		}
	}

	async function pick(c: UltraSignUpCandidate) {
		if (saving) return;
		saving = true;
		const next = linkFromCandidate(c);
		try {
			await linkUltraSignUpPerson(next);
			link = next;
			candidates = null;
			showToast(m('integrations.ultrasignupLinked'), 'success');
		} catch {
			showToast(m('integrations.ultrasignupLinkFailed'), 'error');
		} finally {
			saving = false;
		}
	}

	function unlink() {
		// Honestly reversible — the same person is one search away, and runs
		// already imported are not touched — so it gets the undo bar, not a
		// dialog (conventions.md § Destructive actions).
		const before = link;
		link = null;
		deferDestructive({
			message: m('integrations.ultrasignupUnlinked'),
			commit: unlinkUltraSignUpPerson,
			restore: () => {
				link = before;
			},
			onCommitError: () => showToast(m('integrations.ultrasignupUnlinkFailed'), 'error')
		});
	}
</script>

<div class="us-link" id="ultrasignup-link" data-testid="ultrasignup-link">
	{#if link}
		<p class="linked" data-testid="ultrasignup-linked-as">
			{m('integrations.ultrasignupLinkedAs', {
				name: `${link.firstName} ${link.lastName}`,
				id: link.personId
			})}
		</p>
		<button
			type="button"
			class="btn btn-outline btn-sm"
			onclick={unlink}
			data-testid="ultrasignup-unlink"
		>
			{m('integrations.ultrasignupUnlink')}
		</button>
	{:else if link === null}
		<form class="find" onsubmit={search} aria-describedby="ultrasignup-name-hint">
			<h3>{m('integrations.ultrasignupFindLabel')}</h3>
			<p class="hint" id="ultrasignup-name-hint">{m('integrations.ultrasignupNameHint')}</p>
			<div class="names">
				<label>
					<span>{m('integrations.ultrasignupFirstName')}</span>
					<input
						type="text"
						autocomplete="given-name"
						maxlength={ULTRASIGNUP_NAME_MAX_LEN}
						bind:value={firstName}
						data-testid="ultrasignup-first-name"
					/>
				</label>
				<label>
					<span>{m('integrations.ultrasignupLastName')}</span>
					<input
						type="text"
						autocomplete="family-name"
						maxlength={ULTRASIGNUP_NAME_MAX_LEN}
						bind:value={lastName}
						data-testid="ultrasignup-last-name"
					/>
				</label>
			</div>
			<button
				type="submit"
				class="btn btn-connect btn-sm"
				disabled={searching || !ultraSignUpNameReady(firstName, lastName)}
				data-testid="ultrasignup-find"
			>
				{searching ? m('integrations.ultrasignupSearching') : m('integrations.ultrasignupFind')}
			</button>
		</form>
	{/if}
	<!-- Mounted unconditionally so the first result is announced (decisions § 736). -->
	<div class="results" aria-live="polite">
		{#if link === null && candidates !== null}
			{#if candidates.length === 0}
				<p class="hint" data-testid="ultrasignup-no-matches">
					{m('integrations.ultrasignupNoMatches')}
				</p>
			{:else}
				<p class="prompt">{m('integrations.ultrasignupPickPrompt')}</p>
				<ul class="candidates" data-testid="ultrasignup-candidates">
					{#each candidates as c (c.id)}
						<li data-testid="ultrasignup-candidate">
							<div class="who">
								<strong>{c.firstName} {c.lastName}</strong>
								<span class="meta">
									{#if c.age != null}{m('integrations.ultrasignupCandidateAge', {
											age: c.age
										})} · {/if}{m('integrations.ultrasignupCandidateResults', {
										n: c.resultCount
									})}
								</span>
								{#if c.recentEvents.length > 0}
									<span class="events">
										{c.recentEvents
											.map((e) => (e.date ? `${e.name} (${e.date.slice(0, 4)})` : e.name))
											.join(' · ')}
									</span>
								{/if}
							</div>
							<button
								type="button"
								class="btn btn-outline btn-sm"
								disabled={saving}
								onclick={() => pick(c)}
								data-testid="ultrasignup-pick-{c.id}"
							>
								{m('integrations.ultrasignupThisIsMe')}
							</button>
						</li>
					{/each}
				</ul>
			{/if}
		{/if}
	</div>
</div>

<style>
	.us-link {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-top: var(--space-md);
		padding-top: var(--space-md);
		border-top: 1px solid var(--color-border);
	}
	.us-link h3 {
		margin: 0;
		font-size: 1rem;
	}
	.hint,
	.prompt,
	.linked {
		margin: 0;
	}
	.hint {
		color: var(--color-text-secondary);
	}
	.find {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		align-items: flex-start;
	}
	.names {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		width: 100%;
	}
	.names label {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		flex: 1 1 10rem;
		min-width: 0;
	}
	.candidates {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.candidates li {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.who {
		display: flex;
		flex-direction: column;
		min-width: 0;
		overflow-wrap: anywhere;
	}
	.meta,
	.events {
		color: var(--color-text-secondary);
		font-size: 0.875rem;
	}
</style>
