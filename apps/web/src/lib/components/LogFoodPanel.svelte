<script lang="ts">
	// Every place a runner logs food: the manual composer, plus the
	// "Log from a photo" entry when the plate-photo logger is live. Hosting
	// both here is what keeps a new Log food surface from shipping without it.
	import FoodLogEditor from '#lib/components/FoodLogEditor.svelte';
	import PlatePhotoLogger from '#lib/components/PlatePhotoLogger.svelte';
	import { coachEnabled } from '#lib/coach/coach_flag.ts';
	import { platePhotoEnabled } from '#lib/nutrition/plate_photo_flag.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import HealthConsentNotice from '#lib/components/HealthConsentNotice.svelte';
	import { fetchHealthDataConsented } from '#lib/core/data.ts';

	interface Props {
		oncreated: () => void;
		diaryDate?: string;
		/// Open the photo logger straight away instead of behind its button.
		photoOpen?: boolean;
	}
	let { oncreated, diaryDate, photoOpen = false }: Props = $props();

	// It runs on the Coach's Anthropic key, so it needs both gates (decisions
	// § 1972). Pro is checked per call; the refusal links to the upgrade.
	const platePhotoLive = coachEnabled() && platePhotoEnabled();
	let showPhoto = $state(false);
	let photoVisible = $derived(showPhoto || photoOpen);

	// A food log is health data, stored only with health-data consent
	// (decisions § 2514): without it the database refuses the write, so the
	// composer is replaced by the notice that says why and where to consent.
	// A failed read shows the composer; the database still refuses the save.
	let consent = $state<'unknown' | 'given' | 'absent'>('unknown');
	$effect(() => {
		fetchHealthDataConsented().then(
			(given) => (consent = given ? 'given' : 'absent'),
			() => (consent = 'given'),
		);
	});
</script>

<div class="log-food">
	{#if consent === 'absent'}
		<HealthConsentNotice testid="food-consent-notice" message={m('healthConsent.foodNeedsConsent')} />
	{:else if consent === 'given'}
	{#if platePhotoLive}
		{#if photoVisible}
			<PlatePhotoLogger {oncreated} {diaryDate} />
		{:else}
			<button class="btn btn-outline photo-btn" type="button" onclick={() => (showPhoto = true)} data-testid="log-from-photo">
				<span class="material-symbols" aria-hidden="true">photo_camera</span>
				{m('nutrition.platePhotoHeading')}
				<span class="pro-pill">{m('nutrition.platePhotoProBadge')}</span>
			</button>
		{/if}
	{/if}
	<FoodLogEditor {oncreated} {diaryDate} />
	{/if}
</div>

<style>
	.log-food {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.photo-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		align-self: flex-start;
	}
	.pro-pill {
		font-size: 0.72rem;
		font-weight: 700;
		padding: 0.1rem 0.45rem;
		border-radius: 9999px;
		background: color-mix(in srgb, var(--color-primary) 14%, transparent);
		color: var(--color-primary);
	}
</style>
