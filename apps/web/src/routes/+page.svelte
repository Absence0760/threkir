<script lang="ts">
	import { browser } from '$app/environment';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import SeoHead from '$lib/components/SeoHead.svelte';
	import PublicHeader from '$lib/components/PublicHeader.svelte';
	import PublicFooter from '$lib/components/PublicFooter.svelte';
	import ProductPreview from '$lib/components/marketing/ProductPreview.svelte';
	import TrackPreview from '$lib/components/TrackPreview.svelte';
	import MapBackdrop from '$lib/components/marketing/MapBackdrop.svelte';
	import { DEMO_HR_ZONES, DEMO_SPLITS, DEMO_TRACK } from '$lib/marketing/demo_preview';
	import { reveal, spotlight, tilt } from '$lib/motion/actions';
	import { buildOrganizationJsonLd, buildWebSiteJsonLd } from '$lib/share/site_meta';
	import { normaliseSiteUrl } from '$lib/share/share_meta';

	let { data } = $props();

	// The apex root is the single canonical home for the brand — set it
	// so the www/apex duplicate (both served by CloudFront) can't split
	// ranking signal, and so localized client-side variants of the
	// landing copy all fold onto one URL.
	const canonical = $derived(`${normaliseSiteUrl(data.siteUrl)}/`);
	const jsonLd = $derived([
		buildOrganizationJsonLd(data.siteUrl),
		buildWebSiteJsonLd(data.siteUrl),
	]);

	$effect(() => {
		if (browser && !auth.loading && auth.loggedIn) {
			goto('/dashboard', { replaceState: true });
		}
	});

	const showLanding = $derived(!browser || (!auth.loading && !auth.loggedIn));

	// Split on spaces so each word can rise on its own delay. A language
	// written without spaces comes through as one word and rises whole, which
	// is the right fallback: no mid-word break is invented.
	const headlineWords = $derived(m('landing.heroHeadline').split(' '));

	// Every step here is a surface that ships on the web today. The watch
	// and phone clients are real but unreleased, so they are described in
	// the platforms strip below rather than sold as a feature.
	const integrations = ['Strava', 'Garmin', 'HealthKit', 'parkrun'];

	// Two weeks of a generated plan: the shape of the week grid on /plans,
	// not real prescribed sessions. Height is the session, not decoration.
	const planWeeks = [
		['easy', 'rest', 'tempo', 'easy', 'rest', 'long', 'rest'],
		['easy', 'easy', 'rest', 'intervals', 'rest', 'long', 'easy'],
	];
	const TODAY = { week: 1, day: 3 };

	const splitPeak = Math.max(...DEMO_SPLITS.map((s) => s.seconds));
	const splitFloor = Math.min(...DEMO_SPLITS.map((s) => s.seconds));
	const splitMean = DEMO_SPLITS.reduce((sum, s) => sum + s.seconds, 0) / DEMO_SPLITS.length;

	function splitHeight(seconds: number): number {
		return 20 + ((splitPeak - seconds) / (splitPeak - splitFloor || 1)) * 80;
	}

	const platforms = $derived([
		{ name: 'Web', live: true },
		{ name: 'Android', live: false },
		{ name: 'iOS', live: false },
		{ name: 'Wear OS', live: false },
		{ name: 'Apple Watch', live: false },
	]);
</script>

<SeoHead
	title={m('landing.pageTitle')}
	description={m('landing.pageDescription')}
	{canonical}
	{jsonLd}
/>

{#if !showLanding}
	<main class="landing-loading" id="main-content">
		<span>{m('landing.loading')}</span>
	</main>
{:else}
<div class="landing motion-scope">
<PublicHeader motionToggle />

<main class="hero" id="main-content">
	<!-- Decoration only, on its own clipped layer: .hero cannot be
	     overflow:hidden because the product shot hangs out of its bottom edge
	     into the features band. -->
	<div class="hero-glow" aria-hidden="true">
		<div class="topo topo--hero"></div>
	</div>

	<div class="hero-copy">
		<span class="hero-eyebrow enter" style="--enter-at: 0ms">
			<span class="eyebrow-dot" aria-hidden="true"></span>
			{m('landing.heroEyebrow')}
		</span>
		<h1>
			{#each headlineWords as word, i (i)}<span class="word enter" style="--enter-at: {90 + i * 70}ms">{word}</span>{' '}{/each}
		</h1>
		<p class="hero-sub enter" style="--enter-at: 420ms">{m('landing.heroSub')}</p>
		<div class="hero-actions enter" style="--enter-at: 540ms">
			<a href="/login?signup=1" class="btn btn-primary btn-lg">{m('landing.getStarted')}</a>
			<a href="#features" class="btn btn-outline btn-lg">{m('landing.seeItWorking')}</a>
		</div>
	</div>

	<div class="hero-preview enter enter--lift" style="--enter-at: 680ms" use:tilt>
		<!-- A night landscape rendered in Blender from assets/marketing/ (the
		     route glowing across it is the wordmark's own ramp). Anchored to the
		     shot rather than to the hero, so it starts below the buttons at every
		     width: no copy is ever set on the picture, and every ink stays
		     measured against the ramp alone. -->
		<picture class="terrain" aria-hidden="true">
			<source
				type="image/webp"
				srcset="/marketing/terrain-hero-960.webp 960w, /marketing/terrain-hero-1600.webp 1600w, /marketing/terrain-hero-2400.webp 2400w"
				sizes="100vw"
			/>
			<img
				src="/marketing/terrain-hero-1600.webp"
				alt=""
				width="2400"
				height="860"
				decoding="async"
				fetchpriority="low"
			/>
		</picture>
		<div class="tilt">
			<ProductPreview />
		</div>
	</div>
</main>

<section id="features" class="features">
	<div class="section-head" use:reveal>
		<h2>{m('landing.featuresTitle')}</h2>
		<p>{m('landing.featuresSub')}</p>
	</div>

	<!-- Only the four steps are children here: contrast_guard reads the
	     eyebrow inks by :nth-child. The rail between them is ::before. -->
	<div class="journey">
		<article class="feature" use:reveal>
			<span class="step-node" aria-hidden="true">01</span>
			<div class="feature-copy">
				<span class="feature-eyebrow">{m('landing.featureRouteBuilderTitle')}</span>
				<h3>{m('landing.featureRouteBuilderHeadline')}</h3>
				<p>{m('landing.featureRouteBuilderBody')}</p>
			</div>
			<div class="feature-visual feature-visual--map" use:spotlight>
				<MapBackdrop />
				<div class="map-route" data-draw>
					<TrackPreview points={DEMO_TRACK} aspect={1.7} />
				</div>
				<div class="map-chip" aria-hidden="true" data-pop>
					<span class="map-chip-label">{m('landing.previewDistance')}</span>
					<span class="map-chip-value">8.04<small>km</small></span>
				</div>
			</div>
		</article>

		<article class="feature" use:reveal>
			<span class="step-node" aria-hidden="true">02</span>
			<div class="feature-copy">
				<span class="feature-eyebrow">{m('landing.featureSyncTitle')}</span>
				<h3>{m('landing.featureSyncHeadline')}</h3>
				<p>{m('landing.featureSyncBody')}</p>
			</div>
			<div class="feature-visual feature-visual--sync" aria-hidden="true" use:spotlight>
				<svg class="sync-links" viewBox="0 0 100 100" preserveAspectRatio="none">
					<path d="M18 22 C 34 22, 38 50, 50 50" />
					<path d="M82 22 C 66 22, 62 50, 50 50" />
					<path d="M18 78 C 34 78, 38 50, 50 50" />
					<path d="M82 78 C 66 78, 62 50, 50 50" />
				</svg>
				{#each integrations as name, i (name)}
					<span class="source source--{i + 1}" data-pop>{name}</span>
				{/each}
				<span class="sync-core" data-pop>
					<img src="/logo-mark.svg" alt="" width="44" height="44" />
				</span>
			</div>
		</article>

		<article class="feature" use:reveal>
			<span class="step-node" aria-hidden="true">03</span>
			<div class="feature-copy">
				<span class="feature-eyebrow">{m('landing.featureAnalysisTitle')}</span>
				<h3>{m('landing.featureAnalysisHeadline')}</h3>
				<p>{m('landing.featureAnalysisBody')}</p>
			</div>
			<div class="feature-visual feature-visual--chart" aria-hidden="true" use:spotlight>
				<div class="chart">
					<span class="chart-mean" style="bottom: {splitHeight(splitMean)}%"></span>
					{#each DEMO_SPLITS as split (split.km)}
						<div class="chart-col">
							<span
								class="chart-bar"
								class:chart-bar--best={split.seconds === splitFloor}
								style="height: {splitHeight(split.seconds)}%"
								data-grow="y"
							></span>
							<span class="chart-km">{split.km}</span>
						</div>
					{/each}
				</div>
				<div class="zones" data-grow="x">
					{#each DEMO_HR_ZONES as share, i (i)}
						<span class="zone zone-{i + 1}" style="flex: {share}"></span>
					{/each}
				</div>
			</div>
		</article>

		<article class="feature" use:reveal>
			<span class="step-node" aria-hidden="true">04</span>
			<div class="feature-copy">
				<span class="feature-eyebrow">{m('landing.featurePlansTitle')}</span>
				<h3>{m('landing.featurePlansHeadline')}</h3>
				<p>{m('landing.featurePlansBody')}</p>
			</div>
			<div class="feature-visual feature-visual--week" aria-hidden="true" use:spotlight>
				{#each planWeeks as week, w (w)}
					<div class="week">
						{#each week as kind, d (d)}
							<span class="day-slot" class:today={w === TODAY.week && d === TODAY.day}>
								<span class="day day--{kind}" data-grow="y"></span>
							</span>
						{/each}
					</div>
				{/each}
			</div>
		</article>
	</div>
</section>

<section id="apps" class="apps-section">
	<div class="topo topo--apps" aria-hidden="true"></div>
	<div class="section-head" use:reveal>
		<h2>{m('landing.appsSectionTitle')}</h2>
		<p>{m('landing.appsSectionSub')}</p>
	</div>

	<ul class="platforms" use:reveal={{ items: '.platform' }}>
		{#each platforms as platform (platform.name)}
			<li class="platform" class:pending={!platform.live}>
				{#if platform.live}<span class="live-dot" aria-hidden="true"></span>{/if}
				<span class="platform-name">{platform.name}</span>
				<span class="platform-status">
					{platform.live
						? m('landing.platformLive')
						: m('landing.platformInTesting')}
				</span>
			</li>
		{/each}
	</ul>

	<p class="platforms-note">{m('landing.platformsNote')}</p>
</section>

<section class="closing-cta">
	<div class="closing-glow" aria-hidden="true">
		<div class="topo topo--closing"></div>
	</div>
	<div class="closing-copy" use:reveal>
		<h2>{m('landing.closingTitle')}</h2>
		<p>{m('landing.closingBody')}</p>
		<a href="/login?signup=1" class="btn btn-primary btn-lg">{m('landing.createFreeAccount')}</a>
	</div>
</section>

<PublicFooter />
</div>
{/if}

<style>
	.landing {
		--ease-out: cubic-bezier(0.22, 1, 0.36, 1);
		overflow-x: clip;
	}

	.landing-loading {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		color: var(--color-text-tertiary);
		background: var(--color-bg);
	}

	/* --- entrance ------------------------------------------------------- */

	/* CSS rather than script, because the hero is in the first paint: a script
	   would have to hide it at hydration to animate it, flashing the painted
	   page blank. `backwards` fills only the delay, so the resting state is the
	   element's own style.

	   Declared only for visitors who accept motion. The global reduced-motion
	   rule shrinks a duration to 0.01ms, but an entrance still paints its
	   `from` keyframe on the first frame before the timeline ticks, which is a
	   frame of invisible headline for exactly the visitor who asked for
	   nothing to move. */
	@media (prefers-reduced-motion: no-preference) {
		.enter {
			animation: enter-rise 900ms var(--ease-out) var(--enter-at, 0ms) backwards;
		}

		.enter--lift {
			animation-name: enter-lift;
			animation-duration: 1200ms;
		}
	}

	.word.enter {
		display: inline-block;
	}

	@keyframes enter-rise {
		from {
			opacity: 0;
			transform: translateY(0.9rem);
			filter: blur(6px);
		}
	}

	@keyframes enter-lift {
		from {
			opacity: 0;
			transform: translateY(3rem) scale(0.97);
		}
	}

	/* --- hero ----------------------------------------------------------- */

	/* The hero ramp is the WORDMARK's gradient taken to a legible depth.
	   It used to be #0F172A -> #7C3AED, a stock indigo/violet that appears
	   nowhere else in the product: the wordmark is #FE5932 -> #A01E77 and
	   the app chrome is teal + terracotta, so the first screen a visitor
	   saw belonged to a different brand than the one behind the sign-in.
	   The orange end cannot carry body copy (3.139:1 under white), so the
	   ramp runs dark-plum -> the wordmark's magenta terminus and the
	   orange returns as a glow in .hero-glow, where no text sits on it.
	   Every stop and every veil is measured in
	   gradient_foreground_guard.test.ts. */
	.hero {
		display: grid;
		justify-items: center;
		padding: 9rem var(--space-2xl) 0;
		text-align: center;
		background: linear-gradient(150deg, #140A18 0%, #3A0F33 32%, #6E1450 66%, #A01E77 100%);
		position: relative;
	}

	.hero-glow {
		position: absolute;
		inset: 0;
		overflow: hidden;
		pointer-events: none;
	}

	/* Two slow auroras. Same colours and peak alphas the contrast guard
	   measures; only their position moves. */
	.hero-glow::before {
		content: '';
		position: absolute;
		top: -50%;
		inset-inline-end: -20%;
		width: 60%;
		height: 200%;
		background: radial-gradient(ellipse, rgba(254, 89, 50, 0.18) 0%, transparent 70%);
		animation: aurora-a 22s ease-in-out infinite alternate;
	}

	.hero-glow::after {
		content: '';
		position: absolute;
		bottom: -40%;
		inset-inline-start: -10%;
		width: 55%;
		height: 160%;
		background: radial-gradient(ellipse, rgba(44, 95, 110, 0.18) 0%, transparent 70%);
		animation: aurora-b 28s ease-in-out infinite alternate;
	}

	@keyframes aurora-a {
		to { transform: translate(calc(-14% * var(--dir-sign)), 10%) scale(1.15); }
	}

	@keyframes aurora-b {
		to { transform: translate(calc(18% * var(--dir-sign)), -12%) scale(1.2); }
	}

	/* Contour lines traced from the same heightfield as the render
	   (assets/marketing/contours.py). A mask, so the colour is the page's:
	   a faint white veil, measured by the gradient guard like the glows. */
	.topo {
		position: absolute;
		inset: -10%;
		mask-image: url('/marketing/topo.svg');
		mask-size: 75rem 50rem;
		mask-repeat: repeat;
		pointer-events: none;
	}

	.topo--hero {
		background: rgba(255, 255, 255, 0.07);
		animation: topo-drift 120s linear infinite alternate;
	}

	@keyframes topo-drift {
		to { mask-position: -30rem 12rem; }
	}

	/* Full-bleed from inside the shot's wrapper, ending exactly on the hero's
	   bottom edge: the wrapper hangs --hang below it. */
	.terrain {
		position: absolute;
		z-index: -1;
		top: -5rem;
		bottom: var(--hang);
		inset-inline-start: 50%;
		width: 100vw;
		translate: calc(-50% * var(--dir-sign)) 0;
		mask-image: linear-gradient(to bottom, transparent 0%, black 38%);
		pointer-events: none;
	}

	.terrain img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: 50% 35%;
		display: block;
	}

	/* Scroll-linked, not autoplaying: the landscape sinks a little slower
	   than the page, which is what reads as depth. Resting state (no support,
	   or reduced motion) is the picture where it sits. */
	@supports (animation-timeline: scroll()) {
		@media (prefers-reduced-motion: no-preference) {
			.terrain {
				animation: sink linear both;
				animation-timeline: scroll(root);
				animation-range: 0 100vh;
			}
		}
	}

	@keyframes sink {
		to { transform: translateY(10%) scale(1.05); }
	}

	.hero-copy {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		max-width: 48rem;
	}

	.hero-eyebrow {
		display: inline-flex;
		align-items: center;
		gap: 0.55rem;
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: #FFFFFF;
		background: rgba(255, 255, 255, 0.12);
		border: 1px solid rgba(255, 255, 255, 0.28);
		border-radius: var(--radius-pill);
		padding: 0.35rem 0.95rem 0.35rem 0.75rem;
		margin-bottom: var(--space-lg);
		backdrop-filter: blur(8px);
	}

	.eyebrow-dot {
		width: 0.45rem;
		height: 0.45rem;
		border-radius: var(--radius-pill);
		background: var(--brand-ember);
		box-shadow: 0 0 0 0 rgba(254, 89, 50, 0.6);
		animation: beacon 2.4s ease-out infinite;
	}

	@keyframes beacon {
		70% { box-shadow: 0 0 0 0.55rem rgba(254, 89, 50, 0); }
		100% { box-shadow: 0 0 0 0 rgba(254, 89, 50, 0); }
	}

	h1 {
		/* No hardcoded <br>s. They forced three lines at every width and
		   still wrapped to four on a phone, which is the worst of both. */
		font-size: clamp(2.3rem, 6.2vw, 4.25rem);
		font-weight: 800;
		line-height: 1.05;
		letter-spacing: -0.035em;
		margin-bottom: var(--space-lg);
		color: #FFFFFF;
		text-wrap: balance;
		text-shadow: 0 0.5rem 2.5rem rgba(20, 10, 24, 0.45);
	}

	.hero-sub {
		font-size: clamp(1.05rem, 1.6vw, 1.25rem);
		/* 20px normal weight is not WCAG large text, so this owes 4.5:1.
		   0.85 clears it at every stop of the ramp and under every veil. */
		color: rgba(255, 255, 255, 0.85);
		max-width: 38rem;
		margin-bottom: var(--space-xl);
		line-height: 1.55;
		text-wrap: pretty;
	}

	.hero-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-md);
	}

	.hero-preview {
		/* Set by the tilt action as the pointer crosses the hero. */
		--tilt-x: 0deg;
		--tilt-y: 0deg;
		/* Hangs into the features band. The band pays for it with matching
		   top padding, so nothing overlaps the heading. */
		--hang: 7rem;
		position: relative;
		z-index: 1;
		width: 100%;
		max-width: 62rem;
		margin-block-start: 5rem;
		margin-block-end: calc(-1 * var(--hang));
		perspective: 1800px;
	}

	.tilt {
		transform: rotateX(var(--tilt-x)) rotateY(var(--tilt-y));
		transform-style: preserve-3d;
		transition: transform 700ms var(--ease-out);
	}

	.btn {
		position: relative;
		overflow: hidden;
		padding: 0.75rem 1.75rem;
		border-radius: var(--radius-lg);
		font-weight: 600;
		font-size: 1rem;
		transition:
			transform var(--transition-base),
			box-shadow var(--transition-base),
			background var(--transition-base),
			border-color var(--transition-base);
		display: inline-block;
		/* Without this the two hero CTAs broke to two lines each at 390px. */
		white-space: nowrap;
	}

	.btn-lg {
		padding: 0.9rem 2.25rem;
		font-size: 1.05rem;
	}

	.btn-primary {
		background: #FFFFFF;
		color: #8A1A62;
		border: none;
		box-shadow:
			0 0.25rem 0.9rem rgba(0, 0, 0, 0.18),
			0 0 2.5rem rgba(254, 89, 50, 0.25);
	}

	/* A light sweep across the face on hover. A transition, so it runs once
	   per hover and is never continuous motion. */
	.btn-primary::after {
		content: '';
		position: absolute;
		inset: 0;
		background: linear-gradient(105deg, transparent 35%, rgba(255, 255, 255, 0.75) 50%, transparent 65%);
		transform: translateX(calc(-110% * var(--dir-sign)));
		transition: transform 700ms var(--ease-out);
		pointer-events: none;
	}

	.btn-primary:hover {
		background: #FDEFF7;
		transform: translateY(-2px);
		box-shadow:
			0 0.5rem 1.4rem rgba(0, 0, 0, 0.24),
			0 0 3.5rem rgba(254, 89, 50, 0.35);
	}

	.btn-primary:hover::after {
		transform: translateX(calc(110% * var(--dir-sign)));
	}

	.btn-outline {
		border: 1.5px solid rgba(255, 255, 255, 0.35);
		color: #FFFFFF;
		background: rgba(255, 255, 255, 0.08);
		backdrop-filter: blur(8px);
	}

	.btn-outline:hover {
		border-color: rgba(255, 255, 255, 0.6);
		background: rgba(255, 255, 255, 0.15);
		transform: translateY(-2px);
	}

	/* --- features: the journey ---------------------------------------- */

	.features {
		position: relative;
		padding: 12rem var(--space-2xl) 7rem;
		max-width: 76rem;
		margin: 0 auto;
	}

	.section-head {
		position: relative;
		max-width: 44rem;
		margin: 0 auto var(--space-2xl);
		text-align: center;
	}

	.section-head h2 {
		font-size: clamp(1.9rem, 3.6vw, 2.75rem);
		font-weight: 800;
		line-height: 1.1;
		letter-spacing: -0.03em;
		margin-bottom: var(--space-md);
		text-wrap: balance;
	}

	.section-head p {
		color: var(--color-text-secondary);
		font-size: 1.1rem;
		line-height: 1.55;
		text-wrap: pretty;
	}

	.journey {
		--rail: 5rem;
		position: relative;
		display: grid;
		grid-template-columns: minmax(0, 1fr) var(--rail) minmax(0, 1fr);
		row-gap: 6rem;
		padding-block: var(--space-xl);
	}

	/* The rail: a route line down the middle of the steps, in the wordmark
	   ramp handing over to the product teal. Where scroll timelines exist it
	   draws itself as the reader moves down the section; elsewhere it is
	   simply drawn. */
	.journey::before {
		content: '';
		position: absolute;
		top: 0;
		bottom: 0;
		inset-inline-start: calc(50% - 1.5px);
		width: 3px;
		border-radius: var(--radius-pill);
		background: linear-gradient(180deg, var(--brand-ember), var(--brand-magenta) 70%, var(--color-primary));
		transform-origin: top;
		opacity: 0.85;
	}

	@supports (animation-timeline: view()) {
		@media (prefers-reduced-motion: no-preference) {
			.journey {
				view-timeline-name: --journey;
			}
			.journey::before {
				animation: rail-draw linear both;
				animation-timeline: --journey;
				animation-range: entry 35% exit 45%;
			}
			.step-node {
				animation: node-lit linear both;
				animation-timeline: view();
				animation-range: entry 70% cover 45%;
			}
		}
	}

	@keyframes rail-draw {
		from { transform: scaleY(0); }
	}

	@keyframes node-lit {
		from {
			background: var(--color-surface);
			color: var(--color-text-secondary);
			box-shadow: 0 0 0 0.35rem var(--color-bg);
		}
	}

	.feature {
		grid-column: 1 / -1;
		display: grid;
		grid-template-columns: subgrid;
		align-items: center;
	}

	.step-node {
		grid-column: 2;
		grid-row: 1;
		justify-self: center;
		display: grid;
		place-items: center;
		width: 3.25rem;
		height: 3.25rem;
		border-radius: var(--radius-pill);
		font-size: 0.95rem;
		font-weight: 800;
		letter-spacing: -0.01em;
		font-variant-numeric: tabular-nums;
		/* Lit state is the resting state. White on these two stops reads
		   6.513 / 9.713:1. */
		background: linear-gradient(140deg, #A01E77, #6E1450);
		color: #FFFFFF;
		box-shadow:
			0 0 0 0.35rem var(--color-bg),
			0 0 1.75rem rgba(254, 89, 50, 0.45);
		z-index: 1;
	}

	.feature-copy {
		grid-column: 1;
		grid-row: 1;
		max-width: 28rem;
		justify-self: end;
	}

	.feature-visual {
		grid-column: 3;
		grid-row: 1;
	}

	.feature:nth-child(even) .feature-copy {
		grid-column: 3;
		justify-self: start;
		text-align: start;
	}

	.feature:nth-child(even) .feature-visual {
		grid-column: 1;
	}

	/* Four accents, one per step, each a theme-aware ink on the page's own
	   surface so both halves flip with the theme. Colour carries nothing
	   here — the eyebrow, heading and body each say what the step is — so
	   the four are picked for spread, not for meaning. Measured in
	   contrast_guard.test.ts against --color-surface in both themes. */
	.feature-eyebrow {
		display: block;
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.12em;
		text-transform: uppercase;
		margin-bottom: var(--space-sm);
	}

	.feature:nth-child(1) .feature-eyebrow { color: var(--color-primary); }
	.feature:nth-child(2) .feature-eyebrow { color: var(--color-success-text); }
	.feature:nth-child(3) .feature-eyebrow { color: var(--color-secondary-text); }
	.feature:nth-child(4) .feature-eyebrow { color: var(--color-accent-cyan-text); }

	.feature h3 {
		font-size: clamp(1.5rem, 2.4vw, 2rem);
		font-weight: 800;
		line-height: 1.15;
		letter-spacing: -0.025em;
		margin-bottom: var(--space-md);
		text-wrap: balance;
	}

	.feature p {
		font-size: 1.02rem;
		color: var(--color-text-secondary);
		line-height: 1.65;
		text-wrap: pretty;
	}

	/* Each step leads with the thing it describes rather than an icon
	   standing in for it. The map is the product's own TrackPreview; the rest
	   are the real shapes of the surfaces they name. */
	.feature-visual {
		/* Set by the spotlight action; parked above the card until then. */
		--spot-x: 50%;
		--spot-y: -30%;
		position: relative;
		isolation: isolate;
		height: 18rem;
		padding: var(--space-lg);
		border-radius: 1.5rem;
		overflow: hidden;
		border: 1px solid transparent;
		background:
			linear-gradient(var(--color-surface), var(--color-surface)) padding-box,
			linear-gradient(
				140deg,
				color-mix(in srgb, var(--color-primary) 45%, var(--color-border)),
				var(--color-border) 45%,
				color-mix(in srgb, var(--color-secondary) 45%, var(--color-border))
			) border-box;
		box-shadow:
			0 1px 2px color-mix(in srgb, var(--color-text) 6%, transparent),
			0 2.5rem 4rem -2rem color-mix(in srgb, var(--color-primary) 30%, transparent);
		transition:
			transform 500ms var(--ease-out),
			box-shadow 500ms var(--ease-out);
	}

	.feature-visual:hover {
		transform: translateY(-4px);
		box-shadow:
			0 1px 2px color-mix(in srgb, var(--color-text) 6%, transparent),
			0 3rem 5rem -2rem color-mix(in srgb, var(--color-primary) 42%, transparent);
	}

	/* Pointer-following highlight, positioned by the spotlight action. */
	.feature-visual::after {
		content: '';
		position: absolute;
		inset: 0;
		z-index: 3;
		pointer-events: none;
		background: radial-gradient(
			20rem circle at var(--spot-x) var(--spot-y),
			color-mix(in srgb, var(--color-secondary) 16%, transparent),
			transparent 70%
		);
		opacity: 0;
		transition: opacity 400ms ease;
	}

	.feature-visual:hover::after {
		opacity: 1;
	}

	/* 1 · the map */
	.feature-visual--map {
		padding: var(--space-md);
		background:
			linear-gradient(var(--color-bg-tertiary), var(--color-bg-tertiary)) padding-box,
			linear-gradient(
				140deg,
				color-mix(in srgb, var(--color-primary) 45%, var(--color-border)),
				var(--color-border) 45%,
				color-mix(in srgb, var(--color-secondary) 45%, var(--color-border))
			) border-box;
	}

	.map-route {
		position: relative;
		z-index: 1;
		height: 100%;
		display: grid;
		place-items: center;
	}

	.map-route :global(svg.track-preview) {
		max-height: 100%;
	}

	.map-chip {
		position: absolute;
		z-index: 2;
		inset-block-end: var(--space-md);
		inset-inline-start: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
		padding: 0.55rem 0.85rem;
		border-radius: var(--radius-lg);
		background: color-mix(in srgb, var(--color-surface) 82%, transparent);
		border: 1px solid var(--color-border);
		backdrop-filter: blur(10px);
		box-shadow: var(--shadow-md);
		text-align: start;
	}

	.map-chip-label {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.07em;
		text-transform: uppercase;
		color: var(--color-text-secondary);
	}

	.map-chip-value {
		font-size: 1.2rem;
		font-weight: 800;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}

	.map-chip-value small {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		color: var(--color-text-secondary);
		margin-inline-start: 0.15rem;
	}

	/* 2 · sources flowing into one account */
	.feature-visual--sync {
		padding: 0;
	}

	.sync-links {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		fill: none;
	}

	.sync-links path {
		stroke: var(--color-primary);
		stroke-width: 2;
		stroke-linecap: round;
		stroke-dasharray: 2 7;
		vector-effect: non-scaling-stroke;
		opacity: 0.55;
		animation: flow 1.4s linear infinite;
	}

	@keyframes flow {
		to { stroke-dashoffset: -9; }
	}

	.source {
		position: absolute;
		translate: -50% -50%;
		padding: 0.45rem 0.95rem;
		border-radius: var(--radius-pill);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		box-shadow: var(--shadow-md);
		font-size: 0.9rem;
		font-weight: 700;
		color: var(--color-text);
		white-space: nowrap;
	}

	/* Physical left/top on purpose: these points are the ends of the SVG
	   connectors above, which are drawn in physical viewBox coordinates. */
	.source--1 { left: 18%; top: 22%; }
	.source--2 { left: 82%; top: 22%; }
	.source--3 { left: 18%; top: 78%; }
	.source--4 { left: 82%; top: 78%; }

	.sync-core {
		position: absolute;
		left: 50%;
		top: 50%;
		translate: -50% -50%;
		display: grid;
		place-items: center;
		width: 5rem;
		height: 5rem;
		border-radius: 1.4rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		box-shadow:
			var(--shadow-lg),
			0 0 0 0.5rem color-mix(in srgb, var(--color-primary) 10%, transparent);
	}

	.sync-core::before {
		content: '';
		position: absolute;
		inset: -0.5rem;
		border-radius: 1.8rem;
		border: 2px solid color-mix(in srgb, var(--color-secondary) 55%, transparent);
		animation: core-ring 2.8s ease-out infinite;
	}

	@keyframes core-ring {
		from { transform: scale(0.9); opacity: 1; }
		to { transform: scale(1.35); opacity: 0; }
	}

	.sync-core img {
		width: 2.75rem;
		height: 2.75rem;
		border-radius: 0.8rem;
	}

	/* 3 · splits */
	.feature-visual--chart {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.chart {
		position: relative;
		flex: 1;
		display: flex;
		align-items: stretch;
		gap: 0.5rem;
		padding-bottom: 1.4rem;
	}

	.chart-col {
		flex: 1;
		display: flex;
		flex-direction: column;
		justify-content: flex-end;
		align-items: center;
		position: relative;
	}

	.chart-bar {
		width: 100%;
		border-radius: 0.45rem 0.45rem 0.15rem 0.15rem;
		background: color-mix(in srgb, var(--color-primary) 78%, var(--color-surface));
		transform-origin: bottom;
	}

	.chart-bar--best {
		background: linear-gradient(180deg, var(--brand-ember), var(--brand-magenta));
		box-shadow: 0 0 1.5rem rgba(254, 89, 50, 0.4);
	}

	.chart-km {
		position: absolute;
		bottom: -1.4rem;
		font-size: var(--font-size-section-label);
		font-weight: 600;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}

	.chart-mean {
		position: absolute;
		inset-inline: -0.25rem;
		margin-bottom: 1.4rem;
		border-top: 2px dashed color-mix(in srgb, var(--color-text) 35%, transparent);
		z-index: 1;
	}

	.zones {
		display: flex;
		height: 0.7rem;
		border-radius: var(--radius-pill);
		overflow: hidden;
		gap: 2px;
		background: var(--color-surface);
		/* scaleX has no logical form; --dir-sign puts the origin on the
		   inline start in either direction. */
		transform-origin: calc(50% - 50% * var(--dir-sign)) center;
	}

	/* One class per band rather than an interpolated `var(--zone-{i})`:
	   css_token_guard can only verify a token name it can read literally. */
	.zone-1 { background: var(--zone-1); }
	.zone-2 { background: var(--zone-2); }
	.zone-3 { background: var(--zone-3); }
	.zone-4 { background: var(--zone-4); }
	.zone-5 { background: var(--zone-5); }

	/* 4 · two weeks of a plan */
	.feature-visual--week {
		display: grid;
		grid-template-rows: 1fr 1fr;
		gap: var(--space-md);
	}

	.week {
		display: grid;
		grid-template-columns: repeat(7, minmax(0, 1fr));
		gap: 0.45rem;
	}

	.day-slot {
		display: flex;
		align-items: flex-end;
		padding: 0.3rem;
		border-radius: 0.7rem;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
	}

	.day-slot.today {
		border-color: var(--color-primary);
		box-shadow: 0 0 0 0.2rem color-mix(in srgb, var(--color-primary) 22%, transparent);
		animation: today-glow 2.6s ease-in-out infinite;
	}

	@keyframes today-glow {
		50% { box-shadow: 0 0 0 0.45rem color-mix(in srgb, var(--color-primary) 6%, transparent); }
	}

	.day {
		width: 100%;
		border-radius: 0.45rem;
		transform-origin: bottom;
	}

	.day--rest { height: 12%; background: var(--color-border); }
	.day--easy { height: 46%; background: var(--zone-2); }
	.day--tempo { height: 72%; background: var(--zone-4); }
	.day--intervals { height: 84%; background: var(--zone-5); }
	.day--long { height: 100%; background: var(--zone-3); }

	/* --- platforms ------------------------------------------------------ */

	.apps-section {
		position: relative;
		overflow: hidden;
		padding: 6rem var(--space-2xl) 6.5rem;
		background: var(--color-bg-secondary);
		border-top: 1px solid var(--color-border);
		border-bottom: 1px solid var(--color-border);
	}

	.topo--apps {
		background: color-mix(in srgb, var(--color-text) 6%, transparent);
		mask-size: 70rem 46.7rem;
		animation: topo-drift 150s linear infinite alternate-reverse;
	}

	/* Five equal cards, four of them stamped COMING SOON, made "mostly
	   unreleased" the loudest thing on the page. A pill strip states the
	   same fact in one line without giving it four cards of weight. */
	.platforms {
		position: relative;
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-sm);
		max-width: 52rem;
		margin: 0 auto var(--space-lg);
		padding: 0;
		list-style: none;
	}

	.platform {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: 0.6rem 1.1rem;
		border-radius: var(--radius-pill);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		box-shadow: var(--shadow-sm);
	}

	.platform:not(.pending) {
		border-color: color-mix(in srgb, var(--color-success) 55%, var(--color-border));
		box-shadow:
			var(--shadow-sm),
			0 0 0 0.25rem color-mix(in srgb, var(--color-success) 12%, transparent);
	}

	.live-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--color-success);
		animation: live 2s ease-in-out infinite;
	}

	@keyframes live {
		50% { box-shadow: 0 0 0 0.35rem color-mix(in srgb, var(--color-success) 0%, transparent); }
		0%, 100% { box-shadow: 0 0 0 0 color-mix(in srgb, var(--color-success) 45%, transparent); }
	}

	.platform-name {
		font-weight: 700;
		font-size: 0.95rem;
	}

	.platform-status {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--color-success-text);
	}

	.platform.pending .platform-status {
		color: var(--color-text-tertiary);
	}

	.platforms-note {
		position: relative;
		max-width: 40rem;
		margin: 0 auto;
		text-align: center;
		font-size: 0.92rem;
		line-height: 1.6;
		color: var(--color-text-secondary);
	}

	/* --- closing -------------------------------------------------------- */

	/* Deliberately NOT the hero ramp. Two identical gradient slabs read as
	   two heroes; this one is the product's own primary teal, which is what
	   the visitor meets on the other side of the sign-in. */
	.closing-cta {
		position: relative;
		overflow: hidden;
		padding: 7rem var(--space-2xl);
		text-align: center;
		background: linear-gradient(135deg, #102A32 0%, #2C5F6E 100%);
		color: #FFFFFF;
	}

	.closing-glow {
		position: absolute;
		inset: 0;
		pointer-events: none;
	}

	.closing-glow::before,
	.closing-glow::after {
		content: '';
		position: absolute;
		width: 38rem;
		height: 38rem;
		border-radius: 50%;
	}

	.closing-glow::before {
		top: -22rem;
		inset-inline-start: -10rem;
		background: radial-gradient(circle, rgba(254, 89, 50, 0.2) 0%, transparent 65%);
		animation: aurora-b 24s ease-in-out infinite alternate;
	}

	.closing-glow::after {
		bottom: -24rem;
		inset-inline-end: -8rem;
		background: radial-gradient(circle, rgba(160, 30, 119, 0.22) 0%, transparent 65%);
		animation: aurora-a 30s ease-in-out infinite alternate;
	}

	.topo--closing {
		background: rgba(255, 255, 255, 0.06);
		animation: topo-drift 140s linear infinite alternate;
	}

	.closing-copy {
		position: relative;
		max-width: 40rem;
		margin: 0 auto;
	}

	.closing-cta h2 {
		font-size: clamp(2rem, 4vw, 3rem);
		font-weight: 800;
		line-height: 1.1;
		letter-spacing: -0.03em;
		margin-bottom: var(--space-md);
		text-wrap: balance;
	}

	.closing-cta p {
		color: rgba(255, 255, 255, 0.85);
		margin-bottom: var(--space-xl);
		font-size: 1.1rem;
	}

	.closing-cta .btn-primary {
		color: #1F4854;
	}

	.closing-cta .btn-primary:hover {
		background: #EAF3F5;
	}

	/* --- responsive ----------------------------------------------------- */

	@media (max-width: 60rem) {
		.hero { padding-top: 7rem; }
		.hero-preview { --hang: 4rem; }
		.features { padding-top: 8rem; }

		/* The rail moves to the inline start and every step stacks beside it. */
		.journey {
			--rail: 3.25rem;
			grid-template-columns: var(--rail) minmax(0, 1fr);
			row-gap: 4rem;
		}
		.journey::before {
			inset-inline-start: calc(var(--rail) / 2 - 1.5px);
		}
		.feature {
			grid-template-columns: subgrid;
			row-gap: var(--space-lg);
		}
		.step-node,
		.feature:nth-child(even) .step-node {
			grid-column: 1;
			grid-row: 1;
			align-self: start;
			width: 2.6rem;
			height: 2.6rem;
			font-size: 0.8rem;
		}
		.feature-copy,
		.feature:nth-child(even) .feature-copy {
			grid-column: 2;
			grid-row: 1;
			justify-self: stretch;
			max-width: none;
			text-align: start;
		}
		.feature-visual,
		.feature:nth-child(even) .feature-visual {
			grid-column: 2;
			grid-row: 2;
		}
	}

	@media (max-width: 768px) {
		.hero { padding-inline: var(--space-md); }
		.features { padding-inline: var(--space-md); }
		.feature-visual { height: 15rem; }
		.apps-section,
		.closing-cta { padding-inline: var(--space-md); }
	}
</style>
