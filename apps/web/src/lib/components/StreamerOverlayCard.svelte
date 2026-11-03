<script lang="ts">
	// Settings → Privacy card for the streamer overlay (decisions § 2265). What
	// the overlay may show (delay, trace, heart rate) is saved with the token
	// and enforced by the server; how it looks (stats, units, layout) is part
	// of the URL the creator copies into OBS.
	import { onMount } from 'svelte';
	import { supabase } from '#lib/core/supabase.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { getUnit } from '#lib/format/units.svelte.ts';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import { rateLimitErrorMessage } from '#lib/i18n/rate_limit_message.ts';
	import {
		OVERLAY_DELAY_PRESETS,
		OVERLAY_STATS,
		createLiveOverlayToken,
		fetchLiveOverlay,
		liveOverlayEnabled,
		overlayUrl,
		revokeLiveOverlayToken,
		saveLiveOverlaySettings,
		type LiveOverlaySettings,
		type OverlayLayout,
		type OverlayStat,
		type OverlayUnits,
	} from '#lib/runs/live_overlay.ts';

	let enabled = $state(false);
	let loading = $state(true);
	let loadFailed = $state(false);
	let overlay = $state<LiveOverlaySettings | null>(null);
	let busy = $state(false);
	let actionError = $state<string | null>(null);
	let copied = $state(false);
	let confirming = $state<'replace' | 'revoke' | null>(null);

	let stats = $state<OverlayStat[]>([...OVERLAY_STATS]);
	let units = $state<OverlayUnits>(getUnit() === 'mi' ? 'mi' : 'km');
	let layout = $state<OverlayLayout>('row');

	const url = $derived(
		overlay
			? overlayUrl(window.location.origin, overlay.token, {
					stats,
					units,
					layout,
					map: overlay.showMap,
				})
			: null,
	);
	const delayOptions = $derived(
		overlay && !(OVERLAY_DELAY_PRESETS as readonly number[]).includes(overlay.delayS)
			? [...OVERLAY_DELAY_PRESETS, overlay.delayS].sort((a, b) => a - b)
			: [...OVERLAY_DELAY_PRESETS],
	);

	const STAT_LABEL: Record<OverlayStat, () => string> = {
		distance: () => m('streamerOverlay.statDistance'),
		pace: () => m('streamerOverlay.statPace'),
		elapsed: () => m('streamerOverlay.statElapsed'),
		hr: () => m('streamerOverlay.statHeartRate'),
	};

	function delayLabel(s: number): string {
		if (s === 0) return m('streamerOverlay.delayNone');
		if (s < 60 || s % 60 !== 0) return m('streamerOverlay.delaySeconds', { n: s });
		return m('streamerOverlay.delayMinutes', { n: s / 60 });
	}

	async function load() {
		loading = true;
		loadFailed = false;
		try {
			enabled = await liveOverlayEnabled(supabase);
			overlay = enabled ? await fetchLiveOverlay(supabase) : null;
		} catch (e) {
			console.error('streamer overlay: load failed', e);
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	onMount(load);

	async function create() {
		busy = true;
		actionError = null;
		copied = false;
		try {
			await createLiveOverlayToken(supabase);
			overlay = await fetchLiveOverlay(supabase);
		} catch (e) {
			console.error('streamer overlay: create failed', e);
			actionError =
				rateLimitErrorMessage(m, e as { code?: string; message?: string }) ??
				m('streamerOverlay.createFailed');
		} finally {
			busy = false;
			confirming = null;
		}
	}

	async function revoke() {
		busy = true;
		actionError = null;
		try {
			await revokeLiveOverlayToken(supabase);
			overlay = null;
			copied = false;
		} catch (e) {
			console.error('streamer overlay: revoke failed', e);
			actionError = m('streamerOverlay.revokeFailed');
		} finally {
			busy = false;
			confirming = null;
		}
	}

	async function save(next: Partial<Pick<LiveOverlaySettings, 'delayS' | 'showMap' | 'showHeartRate'>>) {
		if (!overlay) return;
		const before = overlay;
		overlay = { ...overlay, ...next };
		actionError = null;
		copied = false;
		try {
			overlay = await saveLiveOverlaySettings(supabase, next);
		} catch (e) {
			console.error('streamer overlay: save failed', e);
			overlay = before;
			actionError = m('streamerOverlay.saveFailed');
		}
	}

	function toggleStat(stat: OverlayStat, on: boolean) {
		stats = OVERLAY_STATS.filter((s) => (s === stat ? on : stats.includes(s)));
		copied = false;
	}

	async function copy() {
		if (!url) return;
		try {
			await navigator.clipboard.writeText(url);
			copied = true;
		} catch (e) {
			console.error('streamer overlay: copy failed', e);
			actionError = m('streamerOverlay.copyFailed');
		}
	}
</script>

{#if loading || loadFailed || enabled}
	<section class="card" data-testid="streamer-overlay-card">
		<h2>{m('streamerOverlay.title')}</h2>
		<p class="section-desc">{m('streamerOverlay.description')}</p>

		{#if loading}
			<p class="section-hint" role="status">{m('streamerOverlay.loading')}</p>
		{:else if loadFailed}
			<p class="error" role="alert" data-testid="streamer-overlay-load-error">
				{m('streamerOverlay.loadFailed')}
			</p>
			<button type="button" class="btn btn-outline btn-sm" onclick={load}>
				{m('streamerOverlay.retry')}
			</button>
		{:else if overlay === null}
			<button
				type="button"
				class="btn btn-primary btn-sm"
				onclick={create}
				disabled={busy}
				data-testid="streamer-overlay-create"
			>
				{m('streamerOverlay.create')}
			</button>
		{:else}
			<label class="url-label" for="streamer-overlay-url">{m('streamerOverlay.urlLabel')}</label>
			<input
				id="streamer-overlay-url"
				class="url"
				type="text"
				readonly
				value={url ?? ''}
				onfocus={(e) => e.currentTarget.select()}
				data-testid="streamer-overlay-url"
			/>
			<div class="actions">
				<button
					type="button"
					class="btn btn-primary btn-sm"
					onclick={copy}
					data-testid="streamer-overlay-copy"
				>
					{copied ? m('streamerOverlay.copied') : m('streamerOverlay.copy')}
				</button>
				<button
					type="button"
					class="btn btn-outline btn-sm"
					onclick={() => (confirming = 'replace')}
					disabled={busy}
					data-testid="streamer-overlay-replace"
				>
					{m('streamerOverlay.replace')}
				</button>
				<button
					type="button"
					class="btn btn-outline btn-sm danger"
					onclick={() => (confirming = 'revoke')}
					disabled={busy}
					data-testid="streamer-overlay-revoke"
				>
					{m('streamerOverlay.revoke')}
				</button>
			</div>
			<p class="section-hint">{m('streamerOverlay.privacyNote')}</p>

			<h3>{m('streamerOverlay.whatHeading')}</h3>
			<label class="field">
				<span>{m('streamerOverlay.delayLabel')}</span>
				<select
					value={overlay.delayS}
					onchange={(e) => void save({ delayS: Number(e.currentTarget.value) })}
					aria-describedby="streamer-overlay-delay-help"
					data-testid="streamer-overlay-delay"
				>
					{#each delayOptions as d (d)}
						<option value={d}>{delayLabel(d)}</option>
					{/each}
				</select>
			</label>
			<p class="section-hint" id="streamer-overlay-delay-help">{m('streamerOverlay.delayHelp')}</p>

			<label class="consent-checkbox">
				<input
					type="checkbox"
					checked={overlay.showMap}
					aria-describedby="streamer-overlay-map-help"
					onchange={(e) => void save({ showMap: e.currentTarget.checked })}
					data-testid="streamer-overlay-map"
				/>
				<span>{m('streamerOverlay.showMap')}</span>
			</label>
			<p class="section-hint" id="streamer-overlay-map-help">{m('streamerOverlay.showMapHelp')}</p>

			<label class="consent-checkbox">
				<input
					type="checkbox"
					checked={overlay.showHeartRate}
					disabled={!overlay.heartRateConsent && !overlay.showHeartRate}
					aria-describedby="streamer-overlay-hr-help"
					onchange={(e) => void save({ showHeartRate: e.currentTarget.checked })}
					data-testid="streamer-overlay-heart-rate"
				/>
				<span>{m('streamerOverlay.showHeartRate')}</span>
			</label>
			<p class="section-hint" id="streamer-overlay-hr-help">
				{overlay.heartRateConsent
					? m('streamerOverlay.showHeartRateHelp')
					: m('streamerOverlay.heartRateNeedsConsent')}
			</p>

			<h3>{m('streamerOverlay.lookHeading')}</h3>
			<fieldset class="look">
				<legend>{m('streamerOverlay.statsLegend')}</legend>
				{#each OVERLAY_STATS as stat (stat)}
					<label class="consent-checkbox">
						<input
							type="checkbox"
							checked={stats.includes(stat)}
							onchange={(e) => toggleStat(stat, e.currentTarget.checked)}
							data-testid={`streamer-overlay-stat-${stat}`}
						/>
						<span>{STAT_LABEL[stat]()}</span>
					</label>
				{/each}
			</fieldset>
			<fieldset class="look">
				<legend>{m('streamerOverlay.unitsLegend')}</legend>
				<label class="consent-checkbox">
					<input type="radio" name="streamer-overlay-units" value="km" bind:group={units} />
					<span>{m('streamerOverlay.unitsKm')}</span>
				</label>
				<label class="consent-checkbox">
					<input
						type="radio"
						name="streamer-overlay-units"
						value="mi"
						bind:group={units}
						data-testid="streamer-overlay-units-mi"
					/>
					<span>{m('streamerOverlay.unitsMi')}</span>
				</label>
			</fieldset>
			<fieldset class="look">
				<legend>{m('streamerOverlay.layoutLegend')}</legend>
				<label class="consent-checkbox">
					<input type="radio" name="streamer-overlay-layout" value="row" bind:group={layout} />
					<span>{m('streamerOverlay.layoutRow')}</span>
				</label>
				<label class="consent-checkbox">
					<input type="radio" name="streamer-overlay-layout" value="column" bind:group={layout} />
					<span>{m('streamerOverlay.layoutColumn')}</span>
				</label>
			</fieldset>
			<p class="section-hint">{m('streamerOverlay.lookNote')}</p>
		{/if}

		{#if actionError}
			<p class="error" role="alert" data-testid="streamer-overlay-error">{actionError}</p>
		{/if}
	</section>
{/if}

<ConfirmDialog
	open={confirming === 'replace'}
	title={m('streamerOverlay.replaceTitle')}
	message={m('streamerOverlay.replaceMessage')}
	confirmLabel={m('streamerOverlay.replace')}
	onconfirm={create}
	oncancel={() => (confirming = null)}
/>
<ConfirmDialog
	open={confirming === 'revoke'}
	title={m('streamerOverlay.revokeTitle')}
	message={m('streamerOverlay.revokeMessage')}
	confirmLabel={m('streamerOverlay.revoke')}
	danger
	onconfirm={revoke}
	oncancel={() => (confirming = null)}
/>

<style>
	h3 {
		font-size: 0.95rem;
		font-weight: 700;
		margin: var(--space-lg) 0 var(--space-sm);
	}
	.url-label {
		display: block;
		font-size: 0.85rem;
		font-weight: 600;
		margin-bottom: var(--space-2xs);
	}
	.url {
		width: 100%;
		box-sizing: border-box;
		font-family: var(--font-mono, monospace);
		font-size: 0.8rem;
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
		margin-bottom: var(--space-xs);
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.field {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		font-weight: 600;
		font-size: 0.9rem;
	}
	.look {
		border: none;
		padding: 0;
		margin: 0 0 var(--space-sm);
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs) var(--space-md);
	}
	.look legend {
		font-size: 0.85rem;
		font-weight: 600;
		margin-bottom: var(--space-2xs);
		width: 100%;
	}
	.danger {
		color: var(--color-danger-text);
		border-color: var(--color-danger-text);
	}
	.error {
		color: var(--color-danger-text);
		font-size: 0.85rem;
		margin: var(--space-sm) 0 0;
	}
</style>
