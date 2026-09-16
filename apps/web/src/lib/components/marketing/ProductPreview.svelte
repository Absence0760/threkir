<script lang="ts">
	import { browser } from '$app/environment';
	import TrackPreview from '$lib/components/TrackPreview.svelte';
	import MapBackdrop from './MapBackdrop.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { DEFAULT_SITE_URL } from '$lib/core/site_url';
	import { countUp } from '$lib/motion/actions';
	import { motion } from '$lib/motion/motion.svelte';
	import { tickClock } from '$lib/motion/motion';
	import {
		DEMO_DISTANCE_KM,
		DEMO_DISTANCE_LABEL,
		DEMO_ELEVATION,
		DEMO_HEART_RATE,
		DEMO_HR_ZONES,
		DEMO_PACE_LABEL,
		DEMO_SPLITS,
		DEMO_TIME_LABEL,
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
	const fastestLabel = `${Math.floor(fastest / 60)}:${String(fastest % 60).padStart(2, '0')}`;
	const avgBpm = Math.round(DEMO_HEART_RATE.reduce((a, b) => a + b, 0) / DEMO_HEART_RATE.length);

	// The address bar reads the brand origin from its one definition rather
	// than spelling it, so a domain move cannot leave the shot behind.
	const SHOT_ADDRESS = `${new URL(DEFAULT_SITE_URL).host}/runs`;

	// The app's sidebar, as icons only. Every one is already in the icon
	// subset because the real sidebar names it.
	const RAIL = ['directions_run', 'route', 'monitoring', 'calendar_month', 'group'];

	/// A series drawn into a 100-wide viewBox as a smoothed line and the area
	/// under it. The chart is stretched to its box (preserveAspectRatio none)
	/// and the line keeps its weight with non-scaling-stroke.
	function chart(values: number[], height: number, pad = 3): { line: string; area: string } {
		const lo = Math.min(...values);
		const hi = Math.max(...values);
		const pts = values.map((v, i): [number, number] => [
			(i / (values.length - 1)) * 100,
			height - pad - ((v - lo) / (hi - lo || 1)) * (height - pad * 2),
		]);
		let line = `M${pts[0][0].toFixed(2)} ${pts[0][1].toFixed(2)}`;
		for (let i = 1; i < pts.length - 1; i++) {
			const [x, y] = pts[i];
			const [nx, ny] = pts[i + 1];
			line += `Q${x.toFixed(2)} ${y.toFixed(2)} ${((x + nx) / 2).toFixed(2)} ${((y + ny) / 2).toFixed(2)}`;
		}
		const [lx, ly] = pts[pts.length - 1];
		line += `L${lx.toFixed(2)} ${ly.toFixed(2)}`;
		return { line, area: `${line}L100 ${height}L0 ${height}Z` };
	}

	const heart = chart(DEMO_HEART_RATE, 36);
	const elevation = chart(DEMO_ELEVATION, 24);

	// Bar heights spread across the real range rather than starting at
	// zero: eight bars within 40s of each other would otherwise read as a
	// flat block. Floor of 22% keeps the slowest bar visible.
	function barHeight(seconds: number): number {
		const span = slowest - fastest || 1;
		return 22 + ((slowest - seconds) / span) * 78;
	}

	// The phone is mid-run, so its clock runs. Markup carries the starting
	// reading, which is what a visitor without script, or with motion off,
	// sees; the ticker only advances it while the phone is on screen, the tab
	// is visible, and nothing asked for stillness. 302 s/km is the 5:02 pace
	// printed beside it, so the distance agrees with the clock.
	let elapsed = $state('24:17');
	let distanceKm = $state(4.82);
	const PACE_S_PER_KM = 302;

	function liveClock(node: HTMLElement) {
		if (!browser || typeof IntersectionObserver === 'undefined') return;
		let onScreen = false;
		const observer = new IntersectionObserver((entries) => {
			onScreen = entries.some((e) => e.isIntersecting);
		});
		observer.observe(node);
		const timer = setInterval(() => {
			if (!onScreen || motion.still || document.hidden) return;
			elapsed = tickClock(elapsed);
			distanceKm += 1 / PACE_S_PER_KM;
		}, 1000);
		return {
			destroy() {
				observer.disconnect();
				clearInterval(timer);
			},
		};
	}

	/// Kilometre markers along the desktop route, placed from the rendered
	/// path itself so they sit on the line TrackPreview drew. Decoration, not
	/// motion, so it runs whatever the motion setting.
	function kmMarkers(node: HTMLElement) {
		if (!browser) return;
		const route = node.querySelectorAll<SVGPathElement>('svg.track-preview path')[1];
		const svg = route?.ownerSVGElement;
		const length = route?.getTotalLength?.() ?? 0;
		if (!svg || !length) return;
		const NS = 'http://www.w3.org/2000/svg';
		const added: Element[] = [];
		for (const km of [2, 4, 6]) {
			const at = route.getPointAtLength((length * km) / DEMO_DISTANCE_KM);
			const mark = document.createElementNS(NS, 'g');
			mark.setAttribute('class', 'km-mark');
			mark.setAttribute('transform', `translate(${at.x.toFixed(2)} ${at.y.toFixed(2)})`);
			const disc = document.createElementNS(NS, 'circle');
			disc.setAttribute('r', '4.6');
			const label = document.createElementNS(NS, 'text');
			label.setAttribute('text-anchor', 'middle');
			label.setAttribute('dominant-baseline', 'central');
			label.setAttribute('font-size', '5.2');
			label.textContent = String(km);
			mark.append(disc, label);
			svg.append(mark);
			added.push(mark);
		}
		return {
			destroy() {
				for (const el of added) el.remove();
			},
		};
	}

	/// Plays the shot once: the route draws itself, its direction chevrons
	/// and end caps fade in behind it, then the splits rise, the heart-rate
	/// and elevation lines trace across and the zone bar wipes in.
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
				const ring = document.createElementNS(NS, 'circle');
				ring.setAttribute('class', 'pacer-ring');
				ring.setAttribute('r', '8.5');
				const disc = document.createElementNS(NS, 'circle');
				disc.setAttribute('r', '6');
				const figure = document.createElementNS(NS, 'path');
				figure.setAttribute('d', RUNNER_GLYPH);
				figure.setAttribute('transform', 'translate(-4.2 -4.2) scale(0.35)');
				pacer.append(ring, disc, figure);
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

		// The charts wipe in along the inline axis. A clip rather than a dash
		// draw: the lines keep their weight with non-scaling-stroke, and a
		// dash pattern measured in user units breaks under it.
		const fromStart = getComputedStyle(node).direction === 'rtl' ? 'inset(0 0 0 100%)' : 'inset(0 100% 0 0)';
		node.querySelectorAll<SVGSVGElement>('svg.chart').forEach((chartEl, i) => {
			plays.push(
				chartEl.animate([{ clipPath: fromStart }, { clipPath: 'inset(0 0 0 0)' }], {
					duration: 1500,
					delay: 1000 + i * 250,
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
		<!-- One gradient for every route in the shot: the wordmark's ramp, so
		     the product's line and the hero's rendered line are the same line. -->
		<svg class="shot-defs" width="0" height="0">
			<defs>
				<linearGradient id="shot-route" x1="0" y1="0" x2="1" y2="1">
					<stop offset="0" style="stop-color: var(--brand-ember)" />
					<stop offset="1" style="stop-color: var(--brand-magenta)" />
				</linearGradient>
			</defs>
		</svg>

		<div class="chrome">
			<span class="lights"><span></span><span></span><span></span></span>
			<span class="url"><span class="material-symbols">lock</span>{SHOT_ADDRESS}</span>
		</div>

		<div class="app">
			<nav class="rail">
				<img class="rail-logo" src="/logo-mark.svg" alt="" width="28" height="28" />
				{#each RAIL as icon, i (icon)}
					<span class="rail-item" class:rail-item--on={i === 0}><span class="material-symbols">{icon}</span></span>
				{/each}
			</nav>

			<div class="trace" use:kmMarkers>
				<MapBackdrop />
				<TrackPreview points={DEMO_TRACK} aspect={1.25} color="url(#shot-route)" />
				<div class="elev-card">
					<span class="metric-label">{m('landing.previewElevation')}</span>
					<svg class="chart" viewBox="0 0 100 24" preserveAspectRatio="none">
						<path class="chart-area chart-area--elev" d={elevation.area} />
						<path class="chart-line chart-line--elev" d={elevation.line} />
					</svg>
				</div>
			</div>

			<div class="panel">
				<div class="panel-head">
					<span class="run-title">{m('landing.previewRunTitle')}</span>
					<span class="run-avatar"></span>
				</div>

				<div class="stats">
					<div class="stat">
						<span class="stat-label">{m('landing.previewDistance')}</span>
						<span class="stat-value"><span use:countUp={{ delay: 700 }}>{DEMO_DISTANCE_LABEL}</span><small>km</small></span>
					</div>
					<div class="stat">
						<span class="stat-label">{m('landing.previewTime')}</span>
						<span class="stat-value"><span use:countUp={{ delay: 780 }}>{DEMO_TIME_LABEL}</span></span>
					</div>
					<div class="stat">
						<span class="stat-label">{m('landing.previewPace')}</span>
						<span class="stat-value"><span use:countUp={{ delay: 860 }}>{DEMO_PACE_LABEL}</span><small>/km</small></span>
					</div>
				</div>

				<div class="metric-block">
					<div class="metric-row">
						<span class="metric-label">{m('landing.previewSplits')}</span>
						<span class="metric-note">{m('landing.previewFastest')} <strong>{fastestLabel}</strong></span>
					</div>
					<div class="splits">
						{#each DEMO_SPLITS as split (split.km)}
							<div class="split">
								<div
									class="bar"
									class:bar--best={split.seconds === fastest}
									style="height: {barHeight(split.seconds)}%"
								></div>
								<span class="split-km">{split.km}</span>
							</div>
						{/each}
					</div>
				</div>

				<div class="metric-block">
					<div class="metric-row">
						<span class="metric-label">{m('landing.previewHeartRate')}</span>
						<span class="metric-note"><strong>{avgBpm}</strong> bpm</span>
					</div>
					<svg class="chart chart--heart" viewBox="0 0 100 36" preserveAspectRatio="none">
						<path class="chart-area chart-area--heart" d={heart.area} />
						<path class="chart-line chart-line--heart" d={heart.line} />
					</svg>
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

			<div class="handset-app" use:liveClock>
				<span class="rec"><span class="rec-dot"></span>{m('landing.previewRecording')}</span>
				<span class="elapsed">{elapsed}</span>
				<div class="handset-stats">
					<div>
						<span class="stat-label">{m('landing.previewDistance')}</span>
						<span class="handset-value">{distanceKm.toFixed(2)}</span>
					</div>
					<div>
						<span class="stat-label">{m('landing.previewPace')}</span>
						<span class="handset-value">5:02</span>
					</div>
				</div>
				<div class="handset-trace">
					<MapBackdrop />
					<TrackPreview points={DEMO_TRACK} aspect={0.95} color="url(#shot-route)" />
				</div>
				<div class="controls">
					<span class="control control--stop"></span>
					<span class="control control--pause"></span>
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
		/* The hero centres its copy; an app screen does not. */
		text-align: start;
	}

	/* A soft bloom behind the frames, in the wordmark's two ends, so the
	   shot sits IN the hero's light rather than pasted over it. */
	.shot::before {
		content: '';
		position: absolute;
		inset: 8% 6% -4%;
		z-index: -1;
		border-radius: 50%;
		background:
			radial-gradient(closest-side at 30% 60%, rgba(254, 89, 50, 0.35), transparent),
			radial-gradient(closest-side at 72% 40%, rgba(160, 30, 119, 0.4), transparent);
		filter: blur(2.5rem);
		pointer-events: none;
	}

	/* --- desktop frame ------------------------------------------------ */

	.shot-defs {
		position: absolute;
		width: 0;
		height: 0;
	}

	.browser {
		border-radius: 1.1rem;
		overflow: hidden;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		/* Deeper than --shadow-lg: this floats over a dark hero ramp, where the
		   token's near-black at 10% is invisible. The inset line is the lit top
		   edge of a pane of glass. */
		box-shadow:
			inset 0 1px 0 rgba(255, 255, 255, 0.08),
			0 2.5rem 5rem -1rem rgba(0, 0, 0, 0.55),
			0 0 0 1px rgba(255, 255, 255, 0.04);
	}

	.chrome {
		position: relative;
		display: flex;
		align-items: center;
		justify-content: center;
		height: 2.4rem;
		padding: 0 var(--space-md);
		background: color-mix(in srgb, var(--color-bg-secondary) 85%, var(--color-surface));
		border-bottom: 1px solid var(--color-border);
	}

	.lights {
		position: absolute;
		inset-inline-start: var(--space-md);
		display: flex;
		gap: 0.4rem;
	}

	.lights span {
		width: 0.62rem;
		height: 0.62rem;
		border-radius: var(--radius-pill);
		background: var(--color-danger);
	}

	.lights span:nth-child(2) { background: var(--color-warning); }
	.lights span:nth-child(3) { background: var(--color-success); }

	.url {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		min-width: 40%;
		justify-content: center;
		padding: 0.22rem var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		font-size: var(--font-size-section-label);
		font-weight: 500;
		color: var(--color-text-secondary);
	}

	.url .material-symbols {
		font-size: 0.8rem;
		color: var(--color-success-text);
	}

	.app {
		display: grid;
		grid-template-columns: 3.4rem minmax(0, 1.4fr) minmax(0, 1fr);
		height: 25rem;
	}

	.rail {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.35rem;
		padding: var(--space-md) 0;
		background: color-mix(in srgb, var(--color-bg-secondary) 70%, var(--color-surface));
		border-inline-end: 1px solid var(--color-border);
	}

	.rail-logo {
		width: 1.75rem;
		height: 1.75rem;
		border-radius: 0.5rem;
		margin-bottom: var(--space-sm);
	}

	.rail-item {
		display: grid;
		place-items: center;
		width: 2.2rem;
		height: 2.2rem;
		border-radius: 0.65rem;
		color: var(--color-text-tertiary);
	}

	.rail-item .material-symbols {
		font-size: 1.2rem;
	}

	.rail-item--on {
		color: var(--color-primary);
		background: var(--color-primary-light);
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--color-primary) 30%, transparent);
	}

	.trace {
		position: relative;
		overflow: hidden;
		background: var(--color-bg-tertiary);
		padding: var(--space-md) var(--space-md) 4.5rem;
	}

	/* A glass readout over the map, the way the run page overlays its
	   elevation profile. */
	.elev-card {
		position: absolute;
		z-index: 2;
		inset-inline: var(--space-md);
		bottom: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		padding: 0.5rem 0.75rem 0.4rem;
		border-radius: 0.8rem;
		background: color-mix(in srgb, var(--color-surface) 78%, transparent);
		border: 1px solid var(--color-border);
		backdrop-filter: blur(10px);
		box-shadow: 0 0.75rem 1.5rem -0.75rem rgba(0, 0, 0, 0.35);
	}

	.elev-card .chart {
		height: 2rem;
	}

	/* The inline-end padding is the phone's lane: it hangs over this edge,
	   and at a laptop width there is no room beside the frame to push it
	   further out without it leaving the page. */
	.panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		padding: var(--space-md) 3.75rem var(--space-md) var(--space-lg);
		min-width: 0;
	}

	.panel-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		padding-bottom: var(--space-sm);
		border-bottom: 1px solid var(--color-border);
	}

	.run-title {
		font-size: 0.95rem;
		font-weight: 700;
		letter-spacing: -0.01em;
		color: var(--color-text);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.run-avatar {
		flex-shrink: 0;
		width: 1.5rem;
		height: 1.5rem;
		border-radius: var(--radius-pill);
		background: linear-gradient(135deg, var(--brand-ember), var(--brand-magenta));
		box-shadow: 0 0 0 2px var(--color-surface), 0 0 0 3px var(--color-fill-subtle);
	}

	.stats {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-sm);
	}

	.stat {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
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
		font-size: 1.3rem;
		font-weight: 800;
		letter-spacing: -0.02em;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}

	.stat-value small {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		color: var(--color-text-tertiary);
		margin-inline-start: 0.15rem;
	}

	.metric-block {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
	}

	.metric-row {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-sm);
	}

	.metric-note {
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
		white-space: nowrap;
	}

	.metric-note strong {
		font-size: 0.8rem;
		font-weight: 800;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}

	.splits {
		display: flex;
		align-items: flex-end;
		gap: 0.3rem;
		height: 4.25rem;
		padding-bottom: 1rem;
	}

	.split {
		position: relative;
		flex: 1;
		display: flex;
		align-items: flex-end;
		height: 100%;
	}

	.bar {
		width: 100%;
		transform-origin: bottom;
		border-radius: 0.35rem 0.35rem 0.12rem 0.12rem;
		background: linear-gradient(
			180deg,
			color-mix(in srgb, var(--color-primary) 85%, var(--color-surface)),
			color-mix(in srgb, var(--color-primary) 45%, var(--color-surface))
		);
	}

	.bar--best {
		background: linear-gradient(180deg, var(--brand-ember), var(--brand-magenta));
		box-shadow: 0 0 1rem rgba(254, 89, 50, 0.45);
	}

	.split-km {
		position: absolute;
		bottom: -1rem;
		inset-inline: 0;
		text-align: center;
		font-size: var(--font-size-section-label);
		font-weight: 600;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}

	.chart {
		display: block;
		width: 100%;
		overflow: visible;
	}

	.chart--heart {
		height: 2.9rem;
	}

	.chart-line {
		fill: none;
		stroke-width: 2.2;
		stroke-linecap: round;
		stroke-linejoin: round;
		vector-effect: non-scaling-stroke;
	}

	.chart-line--heart {
		stroke: url(#shot-route);
	}

	.chart-line--elev {
		stroke: var(--color-primary);
	}

	.chart-area--heart {
		fill: url(#shot-route);
		opacity: 0.18;
	}

	.chart-area--elev {
		fill: var(--color-primary);
		opacity: 0.16;
	}

	.zones {
		display: flex;
		gap: 3px;
		/* The bar wipes in from the inline START, which is the right edge in
		   RTL. transform-origin has no logical form, so the position is
		   computed: --dir-sign is 1 in LTR (0% = left) and -1 in RTL (100%
		   = right). */
		transform-origin: calc(50% - 50% * var(--dir-sign)) center;
		height: 0.55rem;
	}

	.zone {
		display: block;
		border-radius: var(--radius-pill);
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
	/* Hangs off the frame's bottom corner, clear of the panel's readings. */
	.handset {
		position: absolute;
		inset-block-end: -5rem;
		inset-inline-end: -4rem;
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

	/* Stop and pause, drawn rather than iconised: a square and two bars read
	   at this scale where a glyph would blur. */
	.controls {
		display: flex;
		justify-content: center;
		gap: 0.7rem;
		padding: 0.35rem 0 0.1rem;
	}

	.control {
		position: relative;
		display: block;
		width: 1.55rem;
		height: 1.55rem;
		border-radius: var(--radius-pill);
	}

	.control--stop {
		background: var(--color-bg-tertiary);
		box-shadow: inset 0 0 0 1px var(--color-fill-subtle);
	}

	.control--stop::after {
		content: '';
		position: absolute;
		inset: 33%;
		border-radius: 2px;
		background: var(--color-danger);
	}

	.control--pause {
		background: linear-gradient(135deg, var(--brand-ember), var(--brand-magenta));
		box-shadow: 0 0.3rem 0.8rem -0.2rem rgba(254, 89, 50, 0.6);
	}

	.control--pause::before,
	.control--pause::after {
		content: '';
		position: absolute;
		top: 32%;
		bottom: 32%;
		width: 12%;
		border-radius: 1px;
		background: var(--color-on-primary);
	}

	.control--pause::before { inset-inline-start: 34%; }
	.control--pause::after { inset-inline-end: 34%; }

	.handset-trace {
		position: relative;
		overflow: hidden;
		width: 100%;
		flex: 1;
		min-height: 0;
		border-radius: var(--radius-md);
		background: var(--color-bg-tertiary);
		padding: var(--space-xs);
		margin-block-start: var(--space-2xs);
	}

	/* Below ~60rem the phone would cover the panel, so it steps out, the rail
	   goes (a phone-width app has none), and map and panel stack. */
	@media (max-width: 60rem) {
		.app {
			grid-template-columns: minmax(0, 1fr);
			height: auto;
		}
		.rail { display: none; }
		.panel { padding-inline-end: var(--space-lg); }
		.trace {
			height: 17rem;
			border-block-end: 1px solid var(--color-border);
		}
		.handset { display: none; }
	}

	/* TrackPreview draws a white casing under the line so it survives on top
	   of map tiles. There are no tiles here, so the casing becomes the route's
	   glow: the same gradient, wide and faint. Drawn as geometry rather than a
	   drop-shadow filter, because a filter on the SVG rasterises everything in
	   it, the runner included, and softens its edges. Styled from the outside
	   so the list-card renderer keeps its own casing. */
	/* Child combinators throughout: the runner's glyph is also the first
	   path in its own group, and a descendant selector stroked it with this
	   glow, which read as a blurred runner. */
	.trace :global(svg.track-preview > path:first-of-type),
	.handset-trace :global(svg.track-preview > path:first-of-type) {
		stroke: url(#shot-route);
		stroke-width: 9;
		stroke-opacity: 0.22;
	}

	.trace :global(svg.track-preview > path:nth-of-type(2)),
	.handset-trace :global(svg.track-preview > path:nth-of-type(2)) {
		stroke-width: 2.8;
	}

	/* The direction chevrons are a list-card affordance; beside a moving
	   runner and kilometre markers they are noise. */
	.trace :global(svg.track-preview > g:not(.pacer):not(.km-mark)),
	.handset-trace :global(svg.track-preview > g:not(.pacer)) {
		display: none;
	}

	.trace :global(.km-mark circle) {
		fill: var(--color-surface);
		stroke: url(#shot-route);
		stroke-width: 1.4;
	}

	.trace :global(.km-mark text) {
		fill: var(--color-text);
		font-weight: 800;
	}

	.shot :global(.pacer circle) {
		fill: var(--color-primary);
		stroke: var(--color-surface);
		stroke-width: 1.4;
	}

	.shot :global(.pacer .pacer-ring) {
		fill: none;
		stroke: var(--color-primary);
		stroke-width: 1;
		stroke-opacity: 0.35;
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

	/* The route rides above the drawn basemap. */
	.trace :global(svg.track-preview),
	.handset-trace :global(svg.track-preview) {
		position: relative;
		z-index: 1;
	}
</style>
