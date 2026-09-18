<script lang="ts">
	import { submitRaceListing, type RaceListingInput } from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';

	interface Props {
		oncreated?: (listing: { id: string }) => void;
		oncancel?: () => void;
	}
	let { oncreated, oncancel }: Props = $props();

	let name = $state('');
	let raceDate = $state('');
	let distanceM = $state<number | null>(null);
	let locationLabel = $state('');
	let entryUrl = $state('');
	let resultsUrl = $state('');
	let saving = $state(false);

	let canSave = $derived(name.trim().length > 0 && raceDate.length > 0 && !saving);

	async function save() {
		if (!canSave) return;
		saving = true;
		try {
			const input: RaceListingInput = {
				provider: 'manual',
				name: name.trim(),
				race_date: raceDate,
				distance_m: distanceM,
				location_label: locationLabel,
				entry_url: entryUrl,
				results_url: resultsUrl
			};
			const listing = await submitRaceListing(input);
			oncreated?.({ id: listing.id });
		} catch {
			showToast(m('races.submitFailed'), 'error');
		} finally {
			saving = false;
		}
	}
</script>

<form
	class="editor-form"
	onsubmit={(e) => {
		e.preventDefault();
		save();
	}}
>
	<div class="field">
		<label>
			<span>{m('races.fieldName')}</span>
			<input
				type="text"
				bind:value={name}
				required
				data-testid="race-name"
				aria-describedby="race-name-hint"
			/>
		</label>
		<span class="field-hint" id="race-name-hint">{m('races.fieldNameHint')}</span>
	</div>
	<div class="field">
		<label>
			<span>{m('races.fieldDate')}</span>
			<input
				type="date"
				bind:value={raceDate}
				required
				data-testid="race-date"
				aria-describedby="race-date-hint"
			/>
		</label>
		<span class="field-hint" id="race-date-hint">{m('races.fieldDateHint')}</span>
	</div>
	<div class="field">
		<label>
			<span>{m('races.fieldDistance')}</span>
			<input
				type="number"
				inputmode="numeric"
				min="0"
				bind:value={distanceM}
				data-testid="race-distance"
				aria-describedby="race-distance-hint"
			/>
		</label>
		<span class="field-hint" id="race-distance-hint">{m('races.fieldDistanceHint')}</span>
	</div>
	<div class="field">
		<label>
			<span>{m('races.fieldLocation')}</span>
			<input
				type="text"
				bind:value={locationLabel}
				data-testid="race-location"
				aria-describedby="race-location-hint"
			/>
		</label>
		<span class="field-hint" id="race-location-hint">{m('races.fieldLocationHint')}</span>
	</div>
	<div class="field">
		<label>
			<span>{m('races.fieldEntryUrl')}</span>
			<input
				type="url"
				bind:value={entryUrl}
				placeholder="https://"
				data-testid="race-entry-url"
				aria-describedby="race-entry-url-hint"
			/>
		</label>
		<span class="field-hint" id="race-entry-url-hint">{m('races.fieldEntryUrlHint')}</span>
	</div>
	<div class="field">
		<label>
			<span>{m('races.fieldResultsUrl')}</span>
			<input
				type="url"
				bind:value={resultsUrl}
				placeholder="https://"
				data-testid="race-results-url"
				aria-describedby="race-results-url-hint"
			/>
		</label>
		<span class="field-hint" id="race-results-url-hint">{m('races.fieldResultsUrlHint')}</span>
	</div>
	<div class="form-actions">
		<button type="button" class="btn btn-outline" onclick={() => oncancel?.()}>
			{m('races.cancel')}
		</button>
		<button type="submit" class="btn btn-primary" disabled={!canSave} data-testid="race-save">
			{m('races.save')}
		</button>
	</div>
</form>
