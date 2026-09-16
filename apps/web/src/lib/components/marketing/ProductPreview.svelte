<script lang="ts">
	import { browser } from '$app/environment';
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

	/// Material Symbols `directions_run`, extracted from the shipped font's
	/// own outline and normalised to a 24x24 box. Inlined rather than drawn
	/// as an icon ligature because this marker is positioned along an SVG
	/// path, and a font glyph cannot be placed that way — inlining it also
	/// keeps the icon out of the subset, which is cut from what the tree
	/// NAMES.
	const RUNNER_GLYPH =
		'M13 23V17L10.9 15L9.9 19.4L3 18L3.4 16L8.2 17L9.8 8.9L8 9.6V13H6V8.3L9.95 6.6Q10.83 6.22 11.24 6.11Q11.65 6 12 6Q12.53 6 12.98 6.28Q13.43 6.55 13.7 7L14.7 8.6Q15.35 9.65 16.46 10.32Q17.57 11 19 11V13Q17.35 13 15.91 12.31Q14.48 11.62 13.5 10.5L12.9 13.5L15 15.5V23ZM13.5 5.5Q12.68 5.5 12.09 4.91Q11.5 4.32 11.5 3.5Q11.5 2.67 12.09 2.09Q12.68 1.5 13.5 1.5Q14.33 1.5 14.91 2.09Q15.5 2.67 15.5 3.5Q15.5 4.32 14.91 4.91Q14.33 5.5 13.5 5.5Z';

	const slowest = Math.max(...DEMO_SPLITS.map((s) => s.seconds));
	const fastest = Math.min(...DEMO_SPLITS.map((s) => s.seconds));

	// Bar heights spread across the real range rather than starting at
	// zero: eight bars within 40s of each other would otherwise read as a
	// flat block. Floor of 22% keeps the slowest bar visible.
	function barHeight(seconds: number): number {
		const span = slowest - fastest || 1;
		return 22 + ((slowest - seconds) / span) * 78;
	}

	/// Plays the shot once: the route draws itself, its direction chevrons
	/// and end caps fade in behind it, then the splits rise and the zone bar
	/// wipes across.
	///
	/// Driven from here rather than from TrackPreview, which is the same
	/// component the /runs and /routes lists draw with — a marketing
	/// flourish does not belong in a list-card renderer. The parent reaches
	/// in through the rendered SVG instead, so nothing about the shared
	/// component changes.
	///
	/// Every element's RESTING state is its finished state. The animation
	/// only ever moves an element away from where it already is and back, so
	/// a visitor with no JS, a failed hydration, or reduced-motion set sees
	/// the completed shot rather than an empty frame.
	function animateShot(node: HTMLElement) {
		if (!browser) return;
		if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;
		if (typeof node.animate !== 'function') return;

		const EASE = 'cubic-bezier(0.33, 0, 0.2, 1)';
		const plays: Animation[] = [];

		for (const svg of node.querySelectorAll('svg.track-preview')) {
			// The phone trace is the same route at a smaller scale; draw it
			// alongside rather than after, so the two frames read as one shot.
			const paths = svg.querySelectorAll<SVGPathElement>('path');
			let drew = false;
			for (const path of paths) {
				const length = path.getTotalLength?.() ?? 0;
				if (!length) continue;
				drew = true;
				plays.push(
					path.animate(
						[
							{ strokeDasharray: `${length}`, strokeDashoffset: `${length}` },
							{ strokeDasharray: `${length}`, strokeDashoffset: '0' },
						],
						{ duration: 1400, easing: EASE, fill: 'backwards' },
					),
				);
			}
			if (!drew) continue;

			// A runner travelling the loop, rather than the static end cap
			// standing in for one. CSS offset-path does the work, so the
			// browser owns the timing and throttles it offscreen and in a
			// background tab — an rAF loop would run forever at full rate.
			const route = paths[paths.length - 1];
			const d = route.getAttribute('d');
			if (d && CSS.supports?.('offset-path', 'path("M0 0")')) {
				const NS = 'http://www.w3.org/2000/svg';
				const pacer = document.createElementNS(NS, 'g');
				pacer.setAttribute('class', 'pacer');
				const disc = document.createElementNS(NS, 'circle');
				disc.setAttribute('r', '5');
				const figure = document.createElementNS(NS, 'path');
				figure.setAttribute('d', RUNNER_GLYPH);
				figure.setAttribute('transform', 'translate(-3.5 -3.5) scale(0.29)');
				pacer.append(disc, figure);
				pacer.style.offsetPath = `path("${d}")`;
				svg.append(pacer);
			}
			// Chevrons and the start/end caps belong to a line that has been
			// drawn, so they arrive once it has.
			for (const mark of svg.querySelectorAll('g, circle')) {
				plays.push(
					mark.animate([{ opacity: 0 }, { opacity: 0 }, { opacity: 1 }], {
						duration: 1800,
						easing: 'linear',
						fill: 'backwards',
					}),
				);
			}
		}

		node.querySelectorAll<HTMLElement>('.bar').forEach((bar, i) => {
			plays.push(
				bar.animate([{ transform: 'scaleY(0)' }, { transform: 'scaleY(1)' }], {
					duration: 520,
					delay: 900 + i * 70,
					easing: EASE,
					fill: 'backwards',
				}),
			);
		});

		const zones = node.querySelector<HTMLElement>('.zones');
		if (zones) {
			plays.push(
				zones.animate([{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], {
					duration: 700,
					delay: 1250,
					easing: EASE,
					fill: 'backwards',
				}),
			);
		}

		return {
			destroy() {
				for (const play of plays) play.cancel();
			},
		};
	}
</script>

<figure class="shot" use:animateShot>
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
					<span class="metric-label">{m('landing.previewSplits')}</span>
					<div class="splits">
						{#each DEMO_SPLITS as split (split.km)}
							<div class="split">
								<div class="bar" style="height: {barHeight(split.seconds)}%"></div>
							</div>
						{/each}
					</div>
				</div>

				<div class="metric-block">
					<span class="metric-label">{m('landing.previewZones')}</span>
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
		<span class="side-btn side-btn--mute"></span>
		<span class="side-btn side-btn--up"></span>
		<span class="side-btn side-btn--down"></span>
		<span class="side-btn side-btn--power"></span>

		<div class="handset-screen">
			<div class="status-bar">
				<span class="status-time">9:41</span>
				<span class="island"></span>
				<span class="status-icons">
					<svg viewBox="0 0 18 12" class="status-glyph">
						<rect x="0" y="8" width="3" height="4" rx="1" />
						<rect x="5" y="5.5" width="3" height="6.5" rx="1" />
						<rect x="10" y="3" width="3" height="9" rx="1" />
						<rect x="15" y="0.5" width="3" height="11.5" rx="1" opacity="0.4" />
					</svg>
					<svg viewBox="0 0 16 12" class="status-glyph">
						<path d="M8 11.2 5.6 8.6a3.4 3.4 0 0 1 4.8 0Z" />
						<path d="M3.1 6.1a7 7 0 0 1 9.8 0l-1.5 1.6a4.8 4.8 0 0 0-6.8 0Z" />
						<path d="M0.6 3.5a10.5 10.5 0 0 1 14.8 0l-1.5 1.6a8.3 8.3 0 0 0-11.8 0Z" />
					</svg>
					<svg viewBox="0 0 26 12" class="status-glyph">
						<rect x="0.5" y="0.5" width="21" height="11" rx="3.2" fill="none" stroke="currentColor" opacity="0.5" />
						<rect x="2.2" y="2.2" width="14" height="7.6" rx="1.9" />
						<path d="M23.4 4.2v3.6a2.4 2.4 0 0 0 0-3.6Z" opacity="0.5" />
					</svg>
				</span>
			</div>

			<div class="handset-app">
				<span class="rec"><span class="rec-dot"></span>{m('landing.previewRecording')}</span>
				<span class="elapsed">24:17</span>
				<div class="handset-stats">
					<div>
						<span class="stat-label">{m('landing.previewDistance')}</span>
						<span class="handset-value">4.82</span>
					</div>
					<div>
						<span class="stat-label">{m('landing.previewPace')}</span>
						<span class="handset-value">5:02</span>
					</div>
				</div>
				<div class="handset-trace">
					<TrackPreview points={DEMO_TRACK} aspect={0.95} />
				</div>
			</div>

			<span class="home-indicator"></span>
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
		transform-origin: bottom;
		border-radius: var(--radius-sm) var(--radius-sm) 0 0;
		background: var(--color-primary);
	}

	.zones {
		display: flex;
		/* The bar wipes in from the inline START, which is the right edge in
		   RTL. transform-origin has no logical form, so the position is
		   computed: --dir-sign is 1 in LTR (0% = left) and -1 in RTL (100%
		   = right). */
		transform-origin: calc(50% - 50% * var(--dir-sign)) center;
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

	/* A real device, not a rounded rectangle: true 19.5:9 screen, an even
	   bezel, a titanium-ish rim highlight, the four side buttons in their
	   actual positions, a Dynamic Island, a status bar and a home indicator.
	   Everything is drawn from tokens, so it follows the theme like the rest
	   of the shot. */
	.handset {
		position: absolute;
		inset-block-end: -3rem;
		inset-inline-end: -3.5rem;
		width: 7.6rem;
		aspect-ratio: 9 / 19.5;
		border-radius: 1.6rem;
		padding: 0.28rem;
		background: linear-gradient(145deg, #6E6A72 0%, #2A2830 28%, #1A1920 62%, #55525C 100%);
		box-shadow:
			0 1.5rem 3rem rgba(0, 0, 0, 0.55),
			inset 0 0 0 1px rgba(255, 255, 255, 0.14);
	}

	.side-btn {
		position: absolute;
		width: 2px;
		border-radius: 2px;
		background: linear-gradient(180deg, #4A4750 0%, #23222A 100%);
	}

	.side-btn--mute {
		inset-inline-start: -2px;
		top: 3.3rem;
		height: 0.68rem;
	}

	.side-btn--up {
		inset-inline-start: -2px;
		top: 4.4rem;
		height: 1.2rem;
	}

	.side-btn--down {
		inset-inline-start: -2px;
		top: 5.8rem;
		height: 1.2rem;
	}

	.side-btn--power {
		inset-inline-end: -2px;
		top: 4.8rem;
		height: 1.75rem;
	}

	.handset-screen {
		position: relative;
		height: 100%;
		border-radius: 1.35rem;
		background: var(--color-surface);
		overflow: hidden;
		display: flex;
		flex-direction: column;
	}

	.status-bar {
		position: relative;
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.34rem 0.6rem 0.1rem;
		flex-shrink: 0;
	}

	.status-time {
		font-size: 0.42rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		letter-spacing: 0.01em;
	}

	.island {
		position: absolute;
		/* Physical left + translateX is the direction-AGNOSTIC centring pair;
		   a %-based inset-inline-start with a physical translateX cannot
		   mirror. The island is centred on the device either way. */
		left: 50%;
		transform: translateX(-50%);
		top: 0.26rem;
		width: 2.3rem;
		height: 0.66rem;
		border-radius: var(--radius-pill);
		background: #0B0B0F;
	}

	.status-icons {
		display: flex;
		align-items: center;
		gap: 0.16rem;
		color: var(--color-text);
	}

	.status-glyph {
		height: 0.38rem;
		width: auto;
		fill: currentColor;
	}

	.handset-app {
		flex: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-2xs);
		padding: 0.5rem var(--space-sm) 0;
	}

	.home-indicator {
		width: 33%;
		height: 2.5px;
		border-radius: var(--radius-pill);
		background: var(--color-text);
		opacity: 0.35;
		margin: 0.3rem auto 0.32rem;
		flex-shrink: 0;
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
		animation: rec-pulse 2s ease-in-out infinite;
	}

	/* The one looping animation in the shot, and the cheapest possible one:
	   it says "this is recording right now" without a repaint budget. */
	@keyframes rec-pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.25; }
	}

	.elapsed {
		font-size: 1.25rem;
		font-weight: 800;
		letter-spacing: -0.02em;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		line-height: 1.1;
	}

	.handset-stats {
		display: flex;
		gap: var(--space-sm);
		width: 100%;
		justify-content: center;
	}

	.handset-stats > div {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-2xs);
	}

	/* The phone is 7.6rem wide; "AVG PACE" broke over two lines at the
	   shared label size. */
	.handset-stats .stat-label {
		text-transform: none;
		letter-spacing: normal;
		white-space: nowrap;
	}

	.handset-value {
		font-size: 0.8rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}

	.handset-trace {
		width: 100%;
		flex: 1;
		min-height: 0;
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

	/* TrackPreview draws a white casing under the line so it survives on top
	   of map tiles. There are no tiles here, and at this size the casing read
	   as a thick rubbery outline around the route rather than as contrast.
	   Thinned from the outside so the list-card renderer keeps its own. */
	.trace :global(svg.track-preview path:first-of-type),
	.handset-trace :global(svg.track-preview path:first-of-type) {
		stroke-width: 3.2;
		stroke-opacity: 0.16;
	}

	.trace :global(svg.track-preview path:nth-of-type(2)),
	.handset-trace :global(svg.track-preview path:nth-of-type(2)) {
		stroke-width: 2.2;
	}

	/* The direction chevrons are a list-card affordance; beside a moving
	   runner they are noise. */
	.trace :global(svg.track-preview g:not(.pacer)),
	.handset-trace :global(svg.track-preview g:not(.pacer)) {
		opacity: 0.35;
	}

	.shot :global(.pacer circle) {
		fill: var(--color-primary);
		stroke: var(--color-surface);
		stroke-width: 1.2;
	}

	/* TrackPreview's start/end caps mark where a finished trace begins and
	   ends. With a runner travelling the loop they are three markers stacked
	   on one point — the loop closes, so start and end are the same place. */
	.trace :global(svg.track-preview > circle),
	.handset-trace :global(svg.track-preview > circle) {
		display: none;
	}

	.shot :global(.pacer path) {
		fill: var(--color-on-primary);
	}

	.shot :global(.pacer) {
		/* Declared `-global-pace` so the name survives Svelte's scoping (the
		   marker is created in JS and carries no scoping class), but the
		   REFERENCE drops the prefix -- with it, the name resolves to nothing
		   and the marker sits still at the start of the route. */
		animation: pace 16s linear infinite;
		/* offset-rotate defaults to `auto`, which turns the element to follow
		   the path tangent -- a runner upside down at the top of the loop.
		   He travels the route; he does not cartwheel around it. */
		offset-rotate: 0deg;
	}

	@keyframes -global-pace {
		from { offset-distance: 0%; }
		to { offset-distance: 100%; }
	}

	@media (prefers-reduced-motion: reduce) {
		.rec-dot {
			animation: none;
		}
		.shot :global(.pacer) {
			display: none;
		}
	}
</style>
