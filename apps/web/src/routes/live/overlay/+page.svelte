<script lang="ts">
	// The streamer overlay (decisions § 2265): an OBS browser source. It is
	// chromeless and transparent, holds no session, and reads only what
	// `live_overlay_feed` admits for the token in the fragment. The delay, the
	// trace and heart rate are decided by the server; the query string only
	// picks how the result looks.
	import { onDestroy, onMount } from 'svelte';
	import { supabase } from '#lib/core/supabase.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { formatDistance, formatPace, setUnit } from '#lib/format/units.svelte.ts';
	import { formatDuration } from '#lib/format/time.ts';
	import {
		DEFAULT_OVERLAY_CONFIG,
		OVERLAY_FULL_READ_EVERY,
		OVERLAY_POLL_MS,
		fetchLiveOverlayFeed,
		liveOverlayEnabled,
		readOverlayGate,
		overlayPaceSpan,
		overlayTracePath,
		parseOverlayConfig,
		parseOverlayToken,
		type OverlayConfig,
		type OverlayPing,
	} from '#lib/runs/live_overlay.ts';

	// A long stream at one ping per 5 s is ~720 an hour; the trace keeps the
	// last few hours and the stats only ever read the newest.
	const MAX_PINGS = 4000;

	type Status = 'loading' | 'waiting' | 'live' | 'unavailable' | 'bad-link';
	let status = $state<Status>('loading');
	let config = $state<OverlayConfig>(DEFAULT_OVERLAY_CONFIG);
	let pings = $state.raw<OverlayPing[]>([]);
	let token: string | null = null;
	let cursor: string | null = null;
	let polls = 0;
	let timer: ReturnType<typeof setTimeout> | null = null;
	let stopped = false;

	const latest = $derived(pings.at(-1) ?? null);
	const paceSpan = $derived(overlayPaceSpan(pings));
	const trace = $derived(config.map ? overlayTracePath(pings) : null);
	const show = (stat: OverlayConfig['stats'][number]) => config.stats.includes(stat);

	async function poll() {
		if (!token || stopped) return;
		const full = cursor == null || polls % OVERLAY_FULL_READ_EVERY === 0;
		polls++;
		try {
			const rows = await fetchLiveOverlayFeed(supabase, token, full ? null : cursor);
			if (full) pings = rows.slice(-MAX_PINGS);
			else if (rows.length > 0) pings = [...pings, ...rows].slice(-MAX_PINGS);
			const newest = pings.at(-1);
			cursor = newest?.at ?? null;
			status = newest ? 'live' : 'waiting';
		} catch (err) {
			// Keep the last figures on screen: a dropped poll on a stream is
			// better shown as a number that pauses than as a blank overlay.
			console.warn('live overlay: poll failed', err);
			if (status === 'loading') status = 'waiting';
		}
		if (!stopped) timer = setTimeout(() => void poll(), OVERLAY_POLL_MS);
	}

	onMount(() => {
		document.documentElement.classList.add('live-overlay');
		config = parseOverlayConfig(new URLSearchParams(window.location.search));
		setUnit(config.units);
		token = parseOverlayToken(window.location.hash);
		if (!token) {
			status = 'bad-link';
			return;
		}
		void openGate();
	});

	async function openGate() {
		if (stopped) return;
		const gate = await readOverlayGate(() => liveOverlayEnabled(supabase));
		if (stopped) return;
		if (gate === 'open') {
			await poll();
			return;
		}
		status = 'unavailable';
		if (gate === 'error') timer = setTimeout(() => void openGate(), OVERLAY_POLL_MS);
	}

	onDestroy(() => {
		stopped = true;
		if (timer) clearTimeout(timer);
		if (typeof document !== 'undefined') document.documentElement.classList.remove('live-overlay');
	});
</script>

<svelte:head>
	<title>{m('liveOverlay.pageTitle')}</title>
	<meta name="robots" content="noindex, nofollow" />
</svelte:head>

<main id="main-content" class="overlay" class:column={config.layout === 'column'} data-testid="live-overlay">
	{#if status === 'live' && latest}
		<div class="plate stats" role="group" aria-label={m('liveOverlay.statsAria')}>
			{#if show('distance')}
				<div class="stat" data-testid="overlay-distance">
					<span class="value">{formatDistance(latest.distance_m ?? 0)}</span>
					<span class="label">{m('live.statDistance')}</span>
				</div>
			{/if}
			{#if show('pace')}
				<div class="stat" data-testid="overlay-pace">
					<span class="value">{paceSpan ? formatPace(paceSpan.seconds, paceSpan.metres) : '--:--'}</span>
					<span class="label">{m('live.statPace')}</span>
				</div>
			{/if}
			{#if show('elapsed')}
				<div class="stat" data-testid="overlay-elapsed">
					<span class="value">{formatDuration(latest.elapsed_s ?? 0)}</span>
					<span class="label">{m('liveOverlay.statElapsed')}</span>
				</div>
			{/if}
			{#if show('hr') && latest.bpm != null}
				<div class="stat" data-testid="overlay-heart-rate">
					<span class="value">{m('live.bpmValue', { bpm: latest.bpm })}</span>
					<span class="label">{m('live.statHeartRate')}</span>
				</div>
			{/if}
		</div>
		{#if trace}
			<svg
				class="plate trace"
				viewBox="0 0 100 100"
				role="img"
				aria-label={m('liveOverlay.traceAria')}
				data-testid="overlay-trace"
			>
				<path d={trace.d} />
				<circle cx={trace.end.x} cy={trace.end.y} r="3" />
			</svg>
		{/if}
	{:else if status === 'waiting'}
		<p class="plate note" data-testid="overlay-waiting">{m('liveOverlay.waiting')}</p>
	{:else if status === 'unavailable'}
		<p class="plate note" data-testid="overlay-unavailable">{m('liveOverlay.unavailable')}</p>
	{:else if status === 'bad-link'}
		<p class="plate note" data-testid="overlay-bad-link">{m('liveOverlay.badLink')}</p>
	{/if}
</main>

<style>
	:global(html.live-overlay),
	:global(html.live-overlay body) {
		background: transparent;
	}
	.overlay {
		--overlay-ink: #fff;
		--overlay-ink-soft: rgb(255 255 255 / 0.78);
		--overlay-plate: rgb(0 0 0 / 0.6);
		--overlay-trace: #ff6b4a;
		display: flex;
		align-items: flex-start;
		gap: 0.75rem;
		padding: 0.75rem;
		color: var(--overlay-ink);
		font-variant-numeric: tabular-nums;
	}
	.overlay.column {
		flex-direction: column;
	}
	.plate {
		background: var(--overlay-plate);
		border-radius: 0.75rem;
		margin: 0;
	}
	.stats {
		display: flex;
		gap: 1.25rem;
		padding: 0.6rem 1rem;
	}
	.column .stats {
		flex-direction: column;
		gap: 0.4rem;
	}
	.stat {
		display: flex;
		flex-direction: column;
	}
	.value {
		font-size: 2rem;
		font-weight: 800;
		line-height: 1.1;
	}
	.label {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--overlay-ink-soft);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.trace {
		width: 9rem;
		height: 9rem;
	}
	.trace path {
		fill: none;
		stroke: var(--overlay-trace);
		stroke-width: 2.5;
		stroke-linecap: round;
		stroke-linejoin: round;
	}
	.trace circle {
		fill: var(--overlay-ink);
		stroke: var(--overlay-trace);
		stroke-width: 1.5;
	}
	.note {
		padding: 0.5rem 0.9rem;
		font-size: 1rem;
		font-weight: 600;
	}
</style>
