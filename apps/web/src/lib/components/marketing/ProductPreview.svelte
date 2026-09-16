<script lang="ts">
	import TrackPreview from '$lib/components/TrackPreview.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import {
		DEMO_HR_ZONES,
		DEMO_SPLITS,
		DEMO_TRACK,
	} from '$lib/marketing/demo_preview';

	// The landing hero's product shot. Everything inside the two device
	// frames is the product's own rendering — TrackPreview draws the route
	// here exactly as it draws one in the /runs list — so this cannot drift
	// from the real UI the way a committed PNG does.
	//
	// The frames themselves are built from surface tokens rather than
	// literals so the shot follows the visitor's theme instead of shipping
	// a light-mode screenshot onto a dark page.

	const slowest = Math.max(...DEMO_SPLITS.map((s) => s.seconds));
	const fastest = Math.min(...DEMO_SPLITS.map((s) => s.seconds));

	// Bar heights spread across the real range rather than starting at
	// zero: eight bars within 40s of each other would otherwise read as a
	// flat block. Floor of 22% keeps the slowest bar visible.
	function barHeight(seconds: number): number {
		const span = slowest - fastest || 1;
		return 22 + ((slowest - seconds) / span) * 78;
	}
</script>

<figure class="shot">
	<figcaption class="visually-hidden">{m('landing.previewCaption')}</figcaption>

	<div class="browser" aria-hidden="true">
		<div class="chrome">
			<span class="dot"></span>
			<span class="dot"></span>
			<span class="dot"></span>
			<span class="url">threkir.app</span>
		</div>

		<div class="app">
			<div class="trace">
				<TrackPreview points={DEMO_TRACK} aspect={1.35} />
			</div>

			<div class="panel">
				<div class="stats">
					<div class="stat">
						<span class="stat-label">{m('landing.previewDistance')}</span>
						<span class="stat-value">8.04<small>km</small></span>
					</div>
					<div class="stat">
						<span class="stat-label">{m('landing.previewTime')}</span>
						<span class="stat-value">39:54</span>
					</div>
					<div class="stat">
						<span class="stat-label">{m('landing.previewPace')}</span>
						<span class="stat-value">4:58<small>/km</small></span>
					</div>
				</div>

				<div class="metric-block">
					<span class="block-label">{m('landing.previewSplits')}</span>
					<div class="splits">
						{#each DEMO_SPLITS as split (split.km)}
							<div class="split">
								<div class="bar" style="height: {barHeight(split.seconds)}%"></div>
							</div>
						{/each}
					</div>
				</div>

				<div class="metric-block">
					<span class="block-label">{m('landing.previewZones')}</span>
					<div class="zones">
						{#each DEMO_HR_ZONES as share, i (i)}
							<span class="zone zone-{i + 1}" style="flex: {share}"></span>
						{/each}
					</div>
				</div>
			</div>
		</div>
	</div>

	<div class="handset" aria-hidden="true">
		<div class="handset-screen">
			<span class="rec"><span class="rec-dot"></span>{m('landing.previewRecording')}</span>
			<span class="elapsed">24:17</span>
			<div class="handset-stats">
				<div><span class="stat-label">{m('landing.previewDistance')}</span><span class="handset-value">4.82</span></div>
				<div><span class="stat-label">{m('landing.previewPace')}</span><span class="handset-value">5:02</span></div>
			</div>
			<div class="handset-trace">
				<TrackPreview points={DEMO_TRACK} aspect={0.95} />
			</div>
		</div>
	</div>
</figure>

<style>
	.shot {
		position: relative;
		margin: 0 auto;
		max-width: 60rem;
		width: 100%;
	}

	/* --- desktop frame ------------------------------------------------ */

	.browser {
		border-radius: var(--radius-xl);
		overflow: hidden;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		/* A deeper shadow than --shadow-lg: this floats over a dark hero
		   ramp, where the token's near-black at 10% is invisible. */
		box-shadow: 0 2rem 4rem rgba(0, 0, 0, 0.45);
	}

	.chrome {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-bg-secondary);
		border-bottom: 1px solid var(--color-border);
	}

	.dot {
		width: 0.55rem;
		height: 0.55rem;
		border-radius: var(--radius-pill);
		background: var(--color-border);
	}

	.url {
		margin-inline-start: var(--space-md);
		padding: 0.15rem var(--space-md);
		border-radius: var(--radius-pill);
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		font-size: var(--font-size-section-label);
		color: var(--color-text-tertiary);
	}

	.app {
		display: grid;
		grid-template-columns: 1.35fr 1fr;
		min-height: 23rem;
	}

	.trace {
		background: var(--color-bg-tertiary);
		border-inline-end: 1px solid var(--color-border);
		padding: var(--space-md);
	}

	.panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		padding: var(--space-lg);
	}

	.stats {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-sm);
	}

	.stat {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}

	.stat-label,
	.metric-label {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.07em;
		text-transform: uppercase;
		color: var(--color-text-tertiary);
	}

	.stat-value {
		font-size: 1.15rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}

	.stat-value small {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		color: var(--color-text-tertiary);
		margin-inline-start: 0.1rem;
	}

	.metric-block {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.splits {
		display: flex;
		align-items: flex-end;
		gap: var(--space-xs);
		height: 4.5rem;
	}

	.split {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: flex-end;
		height: 100%;
		gap: var(--space-2xs);
	}

	.bar {
		width: 100%;
		border-radius: var(--radius-sm) var(--radius-sm) 0 0;
		background: var(--color-primary);
	}

	.zones {
		display: flex;
		height: 0.6rem;
		border-radius: var(--radius-pill);
		overflow: hidden;
	}

	.zone {
		display: block;
	}

	/* One class per band rather than an interpolated `var(--zone-{i})`:
	   css_token_guard can only verify a token name it can read literally. */
	.zone-1 { background: var(--zone-1); }
	.zone-2 { background: var(--zone-2); }
	.zone-3 { background: var(--zone-3); }
	.zone-4 { background: var(--zone-4); }
	.zone-5 { background: var(--zone-5); }

	/* --- phone frame --------------------------------------------------- */

	.handset {
		position: absolute;
		inset-block-end: -3.25rem;
		inset-inline-end: -1.75rem;
		width: 10rem;
		border-radius: 1.75rem;
		padding: 0.4rem;
		background: var(--color-text);
		box-shadow: 0 1.5rem 3rem rgba(0, 0, 0, 0.5);
	}

	.handset-screen {
		border-radius: 1.4rem;
		background: var(--color-surface);
		padding: var(--space-md) var(--space-sm) var(--space-sm);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-xs);
	}

	.rec {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-danger-text);
	}

	.rec-dot {
		width: 0.4rem;
		height: 0.4rem;
		border-radius: var(--radius-pill);
		background: var(--color-danger);
	}

	.elapsed {
		font-size: 1.6rem;
		font-weight: 800;
		letter-spacing: -0.02em;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		line-height: 1.1;
	}

	.handset-stats {
		display: flex;
		gap: var(--space-md);
		width: 100%;
		justify-content: center;
	}

	.handset-stats > div {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-2xs);
	}

	.handset-value {
		font-size: 0.95rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}

	.handset-trace {
		width: 100%;
		height: 4rem;
		border-radius: var(--radius-md);
		background: var(--color-bg-tertiary);
		padding: var(--space-xs);
		margin-block-start: var(--space-2xs);
	}

	/* Below ~60rem the phone would cover the desktop frame's panel, so it
	   steps out of the overlap and the two frames stack. */
	@media (max-width: 60rem) {
		.app { grid-template-columns: minmax(0, 1fr); }
		.trace { border-inline-end: none; border-block-end: 1px solid var(--color-border); }
		.handset { display: none; }
	}
</style>
