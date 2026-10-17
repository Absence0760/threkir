<script lang="ts">
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { parseImportCompleteness } from '#lib/integrations/import_completeness.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import {
		importRaceResult,
		fetchUltraSignUpLink,
		RACE_IMPORT_UNAVAILABLE,
		ULTRASIGNUP_NOT_LINKED,
		ULTRASIGNUP_PERSON_NOT_FOUND
	} from '#lib/core/data.ts';
	import { RACE_IMPORT_LEGS, raceImportLegFor } from '#lib/integrations/race_import_providers.ts';
	import {
		raceLegAvailable,
		probeRaceLeg,
		markRaceLegUnavailable
	} from '#lib/integrations/race_import_probe.svelte.ts';
	import Modal from '#lib/components/Modal.svelte';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import type { UltraSignUpPersonLink } from '#lib/integrations/ultrasignup_person.ts';

	interface ImportableRace {
		id: string;
		name: string;
		provider: string;
	}

	interface Props {
		race: ImportableRace | null;
		onclose: () => void;
		onimported?: () => void;
	}
	let { race, onclose, onimported }: Props = $props();

	// The provider needs the import scoped to this runner before it will fetch
	// (issue #360 — an unscoped fetch imports the whole finisher field). Which
	// field that is differs per leg; the spec says which.
	let scopeValue = $state('');
	// A linked-person leg (UltraSignup) is scoped by who the runner picked in
	// Settings, not by anything typed here. `undefined` = not read yet, `null`
	// = no link, so the dialog can say which rather than offer a dead button.
	let linkedPerson = $state<UltraSignUpPersonLink | null | undefined>(undefined);
	let pasteBib = $state('');
	let pasteChip = $state('');
	let pasteGun = $state('');
	let pastePlace = $state<number | null>(null);
	let importBusy = $state(false);

	const importLeg = $derived(race ? raceImportLegFor(race.provider) : null);
	const importSpec = $derived(importLeg ? RACE_IMPORT_LEGS[importLeg] : null);

	async function loadLinkedPerson() {
		linkedPerson = undefined;
		try {
			linkedPerson = await fetchUltraSignUpLink();
		} catch {
			linkedPerson = null;
		}
	}

	// Each opening starts from an empty form, for whichever race it opened on.
	$effect(() => {
		const id = race?.id;
		scopeValue = '';
		pasteBib = '';
		pasteChip = '';
		pasteGun = '';
		pastePlace = null;
		if (!id) return;
		const leg = importLeg;
		if (leg) {
			void probeRaceLeg(leg);
			if (RACE_IMPORT_LEGS[leg].scopeField === 'linkedPerson') void loadLinkedPerson();
		}
	});

	function done() {
		onimported?.();
		onclose();
	}

	async function doProviderImport() {
		if (!race || !importLeg || !importSpec) return;
		const scoped = scopeValue.trim() || undefined;
		importBusy = true;
		try {
			const outcome = await importRaceResult({
				provider: importLeg,
				listingId: race.id,
				bib: importSpec.scopeField === 'bib' ? scoped : undefined,
				ultraSignUpPerson:
					importSpec.scopeField === 'linkedPerson' ? (linkedPerson ?? undefined) : undefined
			});
			// A field read only as far as the cap still imports what it found,
			// so a truncated import used to close the modal looking like a whole
			// one (decisions § 1014).
			const graded = parseImportCompleteness(outcome);
			showToast(
				graded.complete
					? m('races.imported')
					: m('integrations.importPartial', { n: graded.imported }),
				graded.complete ? 'success' : 'error'
			);
			done();
		} catch (e) {
			const message = thrownMessage(e);
			if (message === RACE_IMPORT_UNAVAILABLE[importLeg]) {
				// The leg went unavailable between the probe and the call; correct
				// the dialog as well as saying so, or it keeps offering the form.
				markRaceLegUnavailable(importLeg);
				showToast(m(importSpec.unavailableKey), 'error');
			} else if (message === ULTRASIGNUP_NOT_LINKED) {
				linkedPerson = null;
				showToast(m('races.ultraSignUpNotLinked'), 'error');
			} else if (message === ULTRASIGNUP_PERSON_NOT_FOUND) {
				showToast(m('races.ultraSignUpPersonNotFound'), 'error');
			} else if (message.includes('upstream_results_truncated')) {
				// "We read the whole field and you are not in it" and "we read the
				// first 2,000 finishers and you were not among them" are different
				// sentences, and only the second has the paste form as its answer.
				showToast(m('integrations.importTruncated'), 'error');
			} else {
				showToast(m('races.importFailed'), 'error');
			}
		} finally {
			importBusy = false;
		}
	}

	async function doPasteImport() {
		if (!race) return;
		importBusy = true;
		try {
			await importRaceResult({
				provider: 'paste',
				listingId: race.id,
				result: {
					bib: pasteBib.trim() || undefined,
					chip_time: pasteChip.trim() || undefined,
					gun_time: pasteGun.trim() || undefined,
					overall_place: pastePlace ?? undefined
				}
			});
			showToast(m('races.imported'), 'success');
			done();
		} catch {
			showToast(m('races.importFailed'), 'error');
		} finally {
			importBusy = false;
		}
	}
</script>

<Modal open={race != null} title={race?.name ?? ''} narrow {onclose}>
	{#if race}
		<div class="import-body">
			{#if importLeg && importSpec && raceLegAvailable[importLeg] === true && importSpec.scopeField === 'linkedPerson'}
				{#if linkedPerson}
					<p data-testid={importSpec.inputTestId}>
						{m(importSpec.labelKey, {
							name: `${linkedPerson.firstName} ${linkedPerson.lastName}`,
							id: linkedPerson.personId
						})}
					</p>
					<p class="paste-hint">{m(importSpec.hintKey)}</p>
				{:else if linkedPerson === null}
					<p class="paste-hint" data-testid="ultrasignup-not-linked">
						{m('races.ultraSignUpNotLinked')}
						<a href="/settings/integrations#ultrasignup-link">{m('races.ultraSignUpLinkInSettings')}</a>
					</p>
				{/if}
				<button
					type="button"
					class="btn btn-primary"
					disabled={importBusy || !linkedPerson}
					onclick={doProviderImport}
					data-testid={importSpec.submitTestId}
				>
					{m('races.importResult')}
				</button>
			{:else if importLeg && importSpec && raceLegAvailable[importLeg] === true}
				<label>
					<span>{m(importSpec.labelKey)}</span>
					<input
						type="text"
						bind:value={scopeValue}
						data-testid={importSpec.inputTestId}
						aria-describedby="races-import-scope-hint"
					/>
				</label>
				<p class="paste-hint" id="races-import-scope-hint">{m(importSpec.hintKey)}</p>
				<button
					type="button"
					class="btn btn-primary"
					disabled={importBusy || (importSpec.scopeRequired && !scopeValue.trim())}
					onclick={doProviderImport}
					data-testid={importSpec.submitTestId}
				>
					{m('races.importResult')}
				</button>
			{:else if importLeg && importSpec && raceLegAvailable[importLeg] === false}
				<p class="unavailable" data-testid={importSpec.unavailableTestId}>
					{m(importSpec.unavailableKey)}
				</p>
			{/if}

			<form
				class="editor-form"
				onsubmit={(e) => {
					e.preventDefault();
					doPasteImport();
				}}
			>
				<p class="paste-hint" id="races-paste-hint">{m('races.pasteResultHint')}</p>
				<label>
					<span>{m('races.bib')}</span>
					<input
						type="text"
						bind:value={pasteBib}
						data-testid="paste-bib"
						aria-describedby="races-paste-hint"
					/>
				</label>
				<label>
					<span>{m('races.chipTime')}</span>
					<input
						type="text"
						inputmode="numeric"
						placeholder="1:47:23"
						bind:value={pasteChip}
						data-testid="paste-chip"
						aria-describedby="races-paste-hint"
					/>
				</label>
				<label>
					<span>{m('races.gunTime')}</span>
					<input
						type="text"
						inputmode="numeric"
						placeholder="1:48:01"
						bind:value={pasteGun}
						data-testid="paste-gun"
						aria-describedby="races-paste-hint"
					/>
				</label>
				<label>
					<span>{m('races.overallPlace')}</span>
					<input
						type="number"
						inputmode="numeric"
						min="0"
						bind:value={pastePlace}
						data-testid="paste-place"
						aria-describedby="races-paste-hint"
					/>
				</label>
				<div class="form-actions">
					<button type="button" class="btn btn-outline" onclick={onclose}>
						{m('races.cancel')}
					</button>
					<button
						type="submit"
						class="btn btn-primary"
						disabled={importBusy || (!pasteChip.trim() && !pasteGun.trim())}
						data-testid="paste-save"
					>
						{m('races.matchConfirm')}
					</button>
				</div>
			</form>
		</div>
	{/if}
</Modal>

<style>
	.import-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.paste-hint,
	.unavailable {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0;
	}
</style>
