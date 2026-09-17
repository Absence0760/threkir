<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { effective, updateUniversal } from '$lib/settings/settings';
	import { m } from '$lib/i18n/store.svelte';
	import { setDiscoverableArea, clearDiscoverableArea, fetchMyDiscoverableArea } from '$lib/core/data';
	import { NEARBY_RUNNERS_ENABLED } from '$lib/social/nearby_flag';
	import { geocodePlace } from '$lib/routes/geocoding';
	import { PRIVACY_ZONES_KEY, type PrivacyZone } from '$lib/routes/privacy';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { consent } from '$lib/settings/consent.svelte';
	import { createPrefsPage } from '$lib/settings/prefs_page.svelte';
	import PrefsPage from '$lib/components/settings/PrefsPage.svelte';

	let privacyDefault = $state<'public' | 'followers' | 'private'>('followers');
	let stravaAutoShare = $state(false);
	// Default true for back-compat: every existing account stays findable until
	// it opts out. The `search_user_profiles` RPC reads the same key.
	let discoverableInSearch = $state(true);
	let discoverableNearby = $state(false);
	let nearbyAreaLabel = $state<string | null>(null);
	let nearbyAreaInput = $state('');
	let nearbySavingArea = $state(false);

	// Privacy zones — geofences clipped from public track renders.
	let privacyZones = $state<PrivacyZone[]>([]);
	let showZonePicker = $state(false);
	// PrivacyZonePicker pulls in maplibre-gl (~250KB gz). Lazy-load it the first
	// time the picker opens so a visit to this page doesn't ship the map engine
	// in its initial chunk.
	let PrivacyZonePicker = $state<typeof import('$lib/components/PrivacyZonePicker.svelte').default | null>(null);
	async function openZonePicker() {
		if (!PrivacyZonePicker) {
			PrivacyZonePicker = (await import('$lib/components/PrivacyZonePicker.svelte')).default;
		}
		showZonePicker = true;
	}

	const prefs = createPrefsPage(async ({ settings }) => {
		privacyDefault = effective(settings, 'privacy_default', 'followers') ?? 'followers';
		stravaAutoShare = effective(settings, 'strava_auto_share', false) ?? false;
		discoverableInSearch = effective(settings, 'discoverable_in_search', true) ?? true;
		discoverableNearby = effective(settings, 'discoverable_nearby', false) ?? false;
		if (NEARBY_RUNNERS_ENABLED) {
			nearbyAreaLabel = await fetchMyDiscoverableArea();
		}
		privacyZones = effective<PrivacyZone[]>(settings, PRIVACY_ZONES_KEY) ?? [];
	});

	// Opt-in "runners nearby" area (issue #466). Geocodes the typed place to a
	// coarse centroid via MapTiler (same path as ClubEditor), then hands it to
	// the definer RPC which rounds it to ~1 km before storing. Never live GPS.
	async function saveNearbyArea() {
		const q = nearbyAreaInput.trim();
		if (!q || nearbySavingArea) return;
		nearbySavingArea = true;
		try {
			const place = await geocodePlace(q);
			if (!place) {
				showToast(m('prefs.nearbyAreaNotFound'), 'error');
				return;
			}
			const stored = await setDiscoverableArea(place.center.lng, place.center.lat, q);
			nearbyAreaLabel = stored ?? q;
			nearbyAreaInput = '';
			showToast(m('prefs.nearbyAreaSaved'), 'success');
		} catch (e) {
			showToast(m('prefs.nearbyAreaFailed', { error: (e as Error).message }), 'error');
		} finally {
			nearbySavingArea = false;
		}
	}

	async function clearNearbyArea() {
		if (nearbySavingArea) return;
		nearbySavingArea = true;
		try {
			await clearDiscoverableArea();
			nearbyAreaLabel = null;
			showToast(m('prefs.nearbyAreaCleared'), 'success');
		} catch (e) {
			showToast(m('prefs.nearbyAreaFailed', { error: (e as Error).message }), 'error');
		} finally {
			nearbySavingArea = false;
		}
	}

	// A refused zone write must never look like a saved one: the whole point of
	// the zone is that the area is clipped out of every public share, and a
	// runner who believes their home is hidden when it isn't is the worst
	// outcome on this page.
	async function persistZones(next: PrivacyZone[]) {
		if (!auth.user) return;
		try {
			// Projected field by field on the way into the jsonb bag, which pins
			// what a zone persists as: § 33 makes that a privacy contract, so a
			// field later added to `PrivacyZone` has to be admitted here rather
			// than riding along.
			await updateUniversal(auth.user.id, {
				[PRIVACY_ZONES_KEY]: next.map((z) => ({
					lat: z.lat,
					lng: z.lng,
					radius_m: z.radius_m,
				})),
			});
			privacyZones = next;
		} catch (e) {
			showToast(m('prefs.zoneSaveFailed', { error: (e as Error).message }), 'error');
		}
	}

	async function addZone(zone: PrivacyZone) {
		showZonePicker = false;
		await persistZones([...privacyZones, zone]);
	}

	// Removing a privacy zone re-exposes that area on every public share, so it
	// confirms first (the write persists immediately via persistZones).
	let removeZoneIdx = $state<number | null>(null);
	async function removeZone(idx: number) {
		await persistZones(privacyZones.filter((_, i) => i !== idx));
	}
</script>

<PrefsPage heading={m('prefs.privacySharingHeading')} tagline={m('prefs.privacyTagline')} page={prefs}>
	<section class="card">
		<h2>{m('prefs.yourRunsHeading')}</h2>
		<div class="form-stack">
			<div class="field">
				<label class="field">
					<span class="label-text">{m('prefs.defaultVisibility')}</span>
					<select bind:value={privacyDefault} onchange={() => prefs.save({ privacy_default: privacyDefault })} aria-describedby="default-visibility-hint">
						<option value="public">{m('prefs.visibilityPublic')}</option>
						<option value="followers">{m('prefs.visibilityFollowers')}</option>
						<option value="private">{m('prefs.visibilityPrivate')}</option>
					</select>
				</label>
				<p class="hint" id="default-visibility-hint">{m('prefs.defaultVisibilityHint')}</p>
			</div>
			<label class="checkbox-row">
				<input type="checkbox" bind:checked={stravaAutoShare} onchange={() => prefs.save({ strava_auto_share: stravaAutoShare })} />
				<span>
					{m('prefs.autoPushStrava')}
					<span class="hint">{m('prefs.autoPushStravaHint')}</span>
				</span>
			</label>
		</div>
	</section>

	<section class="card">
		<h2>{m('prefs.beingFoundHeading')}</h2>
		<div class="form-stack">
			<label class="checkbox-row">
				<input type="checkbox" bind:checked={discoverableInSearch} onchange={() => prefs.save({ discoverable_in_search: discoverableInSearch })} />
				<span>
					{m('prefs.showInSearch')}
					<span class="hint">{m('prefs.showInSearchHint')}</span>
				</span>
			</label>
			{#if NEARBY_RUNNERS_ENABLED}
				<label class="checkbox-row">
					<input
						type="checkbox"
						bind:checked={discoverableNearby}
						onchange={() => prefs.save({ discoverable_nearby: discoverableNearby })}
					/>
					<span>
						{m('prefs.discoverableNearby')}
						<span class="hint">{m('prefs.discoverableNearbyHint')}</span>
					</span>
				</label>
				<div class="nearby-area">
					<span class="label-text">{m('prefs.nearbyAreaLabel')}</span>
					<p class="hint" id="nearby-area-status" data-testid="nearby-area-status">
						{nearbyAreaLabel
							? m('prefs.nearbyAreaCurrent', { label: nearbyAreaLabel })
							: m('prefs.nearbyAreaNone')}
					</p>
					<div class="nearby-area-row">
						<input
							type="text"
							bind:value={nearbyAreaInput}
							placeholder={m('prefs.nearbyAreaPlaceholder')}
							aria-label={m('prefs.nearbyAreaLabel')}
							aria-describedby="nearby-area-status"
						/>
						<button
							type="button"
							class="btn btn-outline btn-sm"
							disabled={nearbySavingArea || nearbyAreaInput.trim().length === 0}
							onclick={saveNearbyArea}
						>
							{m('prefs.nearbyAreaSet')}
						</button>
						{#if nearbyAreaLabel}
							<button
								type="button"
								class="btn btn-outline btn-sm"
								disabled={nearbySavingArea}
								onclick={clearNearbyArea}
							>
								{m('prefs.nearbyAreaClear')}
							</button>
						{/if}
					</div>
				</div>
			{/if}
		</div>
	</section>

	<!-- Privacy zones — clipped from the start and end of public tracks. -->
	<section class="card" id="privacy-zones">
		<h2>{m('prefs.privacyZonesHeading')}</h2>
		<p class="section-hint">{m('prefs.privacyZonesDesc')}</p>

		{#if privacyZones.length === 0}
			<div class="inline-empty">
				<span class="material-symbols" aria-hidden="true">my_location</span>
				<p>{m('prefs.privacyZonesEmpty')}</p>
			</div>
		{:else}
			<ul class="zone-list">
				{#each privacyZones as zone, idx (idx)}
					<li class="zone-row">
						<div>
							<div class="zone-coords">
								{zone.lat.toFixed(5)}, {zone.lng.toFixed(5)}
							</div>
							<div class="zone-radius">{m('prefs.zoneRadius', { radius: String(zone.radius_m) })}</div>
						</div>
						<button class="btn btn-outline btn-sm" type="button" onclick={() => (removeZoneIdx = idx)}>
							{m('prefs.removeZone')}
						</button>
					</li>
				{/each}
			</ul>
		{/if}

		<div>
			<button class="btn btn-primary" type="button" onclick={openZonePicker}>
				<span class="material-symbols">add</span>
				{m('prefs.addZone')}
			</button>
		</div>
	</section>

	<!-- Telemetry consent (Sentry). Mirrors the cookie banner's accept/reject
	     choice so a returning runner can withdraw an earlier acceptance per
	     GDPR Art 7(3) / Art 21. hooks.server.ts + hooks.client.ts gate Sentry
	     on this state. -->
	<section class="card">
		<h2>{m('prefs.telemetryHeading')}</h2>
		<p class="section-desc" id="telemetry-desc">{m('prefs.telemetryDesc')}</p>
		<label class="consent-checkbox">
			<input
				type="checkbox"
				checked={consent.choice === 'accepted'}
				aria-describedby="telemetry-desc"
				onchange={(e) => {
					const enabled = (e.currentTarget as HTMLInputElement).checked;
					consent.set(enabled ? 'accepted' : 'rejected');
					showToast(
						enabled ? m('prefs.telemetryEnabledToast') : m('prefs.telemetryDisabledToast'),
						'success',
					);
				}}
			/>
			<span>{m('prefs.telemetryConsent')}</span>
		</label>
		{#if consent.timestamp}
			<p class="section-hint">
				{m('prefs.choiceRecordedOn', { date: new Date(consent.timestamp).toLocaleDateString() })}
			</p>
		{/if}
	</section>
</PrefsPage>

<Modal
	open={showZonePicker}
	title={m('prefs.addZoneModalTitle')}
	onclose={() => (showZonePicker = false)}
	wide
>
	{#if PrivacyZonePicker}
		<PrivacyZonePicker oncreated={addZone} oncancel={() => (showZonePicker = false)} />
	{/if}
</Modal>

<ConfirmDialog
	open={removeZoneIdx !== null}
	title={m('prefs.removeZoneTitle')}
	message={m('prefs.removeZoneMessage')}
	confirmLabel={m('prefs.removeZone')}
	onconfirm={() => {
		const idx = removeZoneIdx;
		removeZoneIdx = null;
		if (idx !== null) removeZone(idx);
	}}
	oncancel={() => (removeZoneIdx = null)}
	danger
/>

<style>
	.inline-empty {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-md);
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-md);
		margin-bottom: var(--space-md);
	}
	.inline-empty .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.4rem;
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}
	.inline-empty p {
		margin: 0;
		font-size: 0.88rem;
		color: var(--color-text-secondary);
		line-height: 1.4;
	}
	.nearby-area { margin-top: var(--space-sm); }
	.nearby-area .hint { margin: 0 0 var(--space-xs); }
	.nearby-area-row { display: flex; flex-wrap: wrap; gap: var(--space-sm); align-items: center; }
	.nearby-area-row input { flex: 1 1 14rem; width: auto; }
	.zone-list { list-style: none; padding: 0; margin: 0 0 var(--space-md) 0; display: flex; flex-direction: column; gap: var(--space-sm); }
	.zone-row { display: flex; align-items: center; justify-content: space-between; gap: var(--space-md); padding: var(--space-sm) var(--space-md); background: var(--color-bg-tertiary); border-radius: var(--radius-md); }
	.zone-coords { font-variant-numeric: tabular-nums; font-weight: 600; }
	.zone-radius { font-size: 0.85rem; color: var(--color-text-secondary); }
</style>
