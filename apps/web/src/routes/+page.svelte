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
	import { DEMO_SPLITS, DEMO_TRACK } from '$lib/marketing/demo_preview';
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

	// Every card here is a surface that ships on the web today. The watch
	// and phone clients are real but unreleased, so they are described in
	// the platforms strip below rather than sold as a feature — a card a
	// visitor cannot go and use is the thing that made the old grid read
	// as vapour.
	const integrations = ['Strava', 'Garmin', 'HealthKit', 'parkrun'];

	// A fortnight of a generated plan: the shape of the week grid on
	// /plans, not real prescribed sessions.
	const planWeek = ['easy', 'rest', 'tempo', 'easy', 'rest', 'long', 'rest'];

	const platforms = $derived([
		{ name: 'Web', live: true },
		{ name: 'Android', live: false },
		{ name: 'iOS', live: false },
		{ name: 'Wear OS', live: false },
		{ name: 'Apple Watch', live: false },
	]);

	const splitPeak = Math.max(...DEMO_SPLITS.map((s) => s.seconds));
	const splitFloor = Math.min(...DEMO_SPLITS.map((s) => s.seconds));

	/// Fade each section up as it comes into view. An action rather than a
	/// CSS-only effect because the resting state has to be the VISIBLE one:
	/// a stylesheet that hides sections until a class arrives leaves the
	/// whole page blank if the script never runs, which is the state a
	/// crawler and a no-JS visitor see. Here the element only ever gets
	/// hidden by code that is also able to reveal it.
	function reveal(node: HTMLElement) {
		if (!browser) return;
		const motionOk = window.matchMedia?.('(prefers-reduced-motion: reduce)');
		if (motionOk?.matches || typeof IntersectionObserver === 'undefined') return;

		node.classList.add('pre-reveal');
		const observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (!entry.isIntersecting) continue;
					entry.target.classList.remove('pre-reveal');
					observer.unobserve(entry.target);
				}
			},
			{ rootMargin: '0px 0px -8% 0px' },
		);
		observer.observe(node);
		return { destroy: () => observer.disconnect() };
	}
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
<PublicHeader overlay />

<main class="hero" id="main-content">
	<div class="hero-glow" aria-hidden="true"></div>

	<div class="hero-copy">
		<span class="hero-eyebrow">{m('landing.heroEyebrow')}</span>
		<h1>{m('landing.heroHeadline')}</h1>
		<p class="hero-sub">{m('landing.heroSub')}</p>
		<div class="hero-actions">
			<a href="/login" class="btn btn-primary btn-lg">{m('landing.getStarted')}</a>
			<a href="#features" class="btn btn-outline btn-lg">{m('landing.seeItWorking')}</a>
		</div>
	</div>

	<div class="hero-preview">
		<ProductPreview />
	</div>
</main>

<section id="features" class="features" use:reveal>
	<article class="feature">
		<div class="feature-visual feature-visual--map">
			<TrackPreview points={DEMO_TRACK} aspect={2.1} />
		</div>
		<span class="feature-eyebrow">{m('landing.featureRouteBuilderTitle')}</span>
		<h3>{m('landing.featureRouteBuilderHeadline')}</h3>
		<p>{m('landing.featureRouteBuilderBody')}</p>
	</article>

	<article class="feature">
		<div class="feature-visual feature-visual--chart" aria-hidden="true">
			{#each DEMO_SPLITS as split (split.km)}
				<span
					class="chart-bar"
					style="height: {20 +
						((splitPeak - split.seconds) / (splitPeak - splitFloor || 1)) * 80}%"
				></span>
			{/each}
		</div>
		<span class="feature-eyebrow">{m('landing.featureAnalysisTitle')}</span>
		<h3>{m('landing.featureAnalysisHeadline')}</h3>
		<p>{m('landing.featureAnalysisBody')}</p>
	</article>

	<article class="feature">
		<div class="feature-visual feature-visual--chips" aria-hidden="true">
			{#each integrations as name (name)}
				<span class="chip">{name}</span>
			{/each}
		</div>
		<span class="feature-eyebrow">{m('landing.featureSyncTitle')}</span>
		<h3>{m('landing.featureSyncHeadline')}</h3>
		<p>{m('landing.featureSyncBody')}</p>
	</article>

	<article class="feature">
		<div class="feature-visual feature-visual--week" aria-hidden="true">
			{#each planWeek as kind, i (i)}
				<span class="day day--{kind}"></span>
			{/each}
		</div>
		<span class="feature-eyebrow">{m('landing.featurePlansTitle')}</span>
		<h3>{m('landing.featurePlansHeadline')}</h3>
		<p>{m('landing.featurePlansBody')}</p>
	</article>
</section>

<section id="apps" class="apps-section" use:reveal>
	<div class="section-head">
		<h2>{m('landing.appsSectionTitle')}</h2>
		<p>{m('landing.appsSectionSub')}</p>
	</div>

	<ul class="platforms">
		{#each platforms as platform (platform.name)}
			<li class="platform" class:pending={!platform.live}>
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

<section class="closing-cta" use:reveal>
	<h2>{m('landing.closingTitle')}</h2>
	<p>{m('landing.closingBody')}</p>
	<a href="/login" class="btn btn-primary btn-lg">{m('landing.createFreeAccount')}</a>
</section>

<PublicFooter />
{/if}

<style>
	/* Resting state is visible; `reveal` adds .pre-reveal only when it is
	   also able to take it off again. */
	.features,
	.apps-section,
	.closing-cta {
		transition:
			opacity 420ms ease,
			transform 420ms ease;
	}

	:global(.pre-reveal) {
		opacity: 0;
		transform: translateY(1.25rem);
	}

	@media (prefers-reduced-motion: reduce) {
		:global(.pre-reveal) {
			opacity: 1;
			transform: none;
		}
		.features,
		.apps-section,
		.closing-cta {
			transition: none;
		}
	}

	.landing-loading {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		color: var(--color-text-tertiary);
		background: var(--color-bg);
	}

	/* The hero ramp is the WORDMARK's gradient taken to a legible depth.
	   It used to be #0F172A -> #7C3AED, a stock indigo/violet that appears
	   nowhere else in the product: the wordmark is #FE5932 -> #A01E77 and
	   the app chrome is teal + terracotta, so the first screen a visitor
	   saw belonged to a different brand than the one behind the sign-in.
	   The orange end cannot carry body copy (3.139:1 under white), so the
	   ramp runs dark-plum -> the wordmark's magenta terminus and the
	   orange returns as a glow in .hero-glow, where no text sits on it.
	   Every stop and both veils are measured in
	   gradient_foreground_guard.test.ts. */
	.hero {
		display: grid;
		justify-items: center;
		padding: 9rem var(--space-2xl) 0;
		text-align: center;
		background: linear-gradient(150deg, #140A18 0%, #3A0F33 32%, #6E1450 66%, #A01E77 100%);
		position: relative;
	}

	/* The two blooms live on their own clipped layer rather than on .hero
	   itself, because .hero can no longer be overflow:hidden — the product
	   preview has to hang out of its bottom edge into the features band. */
	.hero-glow {
		position: absolute;
		inset: 0;
		overflow: hidden;
		pointer-events: none;
	}

	.hero-glow::before {
		content: '';
		position: absolute;
		top: -50%;
		inset-inline-end: -20%;
		width: 60%;
		height: 200%;
		background: radial-gradient(ellipse, rgba(254, 89, 50, 0.18) 0%, transparent 70%);
	}

	.hero-glow::after {
		content: '';
		position: absolute;
		bottom: -40%;
		inset-inline-start: -10%;
		width: 55%;
		height: 160%;
		background: radial-gradient(ellipse, rgba(44, 95, 110, 0.18) 0%, transparent 70%);
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
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: #FFFFFF;
		background: rgba(255, 255, 255, 0.12);
		border: 1px solid rgba(255, 255, 255, 0.28);
		border-radius: var(--radius-pill);
		padding: 0.3rem 0.85rem;
		margin-bottom: var(--space-lg);
	}

	h1 {
		/* No hardcoded <br>s. They forced three lines at every width and
		   still wrapped to four on a phone, which is the worst of both. */
		font-size: clamp(2.25rem, 6.2vw, 4.25rem);
		font-weight: 800;
		line-height: 1.06;
		letter-spacing: -0.03em;
		margin-bottom: var(--space-lg);
		color: #FFFFFF;
		text-wrap: balance;
	}

	.hero-sub {
		font-size: clamp(1.05rem, 1.6vw, 1.25rem);
		/* 20px normal weight is not WCAG large text, so this owes 4.5:1.
		   0.85 clears it at every stop of the ramp and under both glows. */
		color: rgba(255, 255, 255, 0.85);
		max-width: 36rem;
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
		position: relative;
		z-index: 1;
		width: 100%;
		max-width: 62rem;
		margin-block-start: 4rem;
		/* Hangs into the features band. The band pays for it with matching
		   top padding, so nothing overlaps the first card. */
		margin-block-end: -7rem;
	}

	.btn {
		padding: 0.75rem 1.75rem;
		border-radius: var(--radius-lg);
		font-weight: 600;
		font-size: 1rem;
		transition: all var(--transition-base);
		display: inline-block;
		/* Without this the two hero CTAs broke to two lines each at 390px. */
		white-space: nowrap;
	}

	.btn-lg {
		padding: 0.875rem 2.25rem;
		font-size: 1.05rem;
	}

	.btn-primary {
		background: #FFFFFF;
		color: #8A1A62;
		border: none;
		box-shadow: 0 4px 14px rgba(0, 0, 0, 0.18);
	}

	.btn-primary:hover {
		background: #FDEFF7;
		transform: translateY(-1px);
		box-shadow: 0 6px 20px rgba(0, 0, 0, 0.24);
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
		transform: translateY(-1px);
	}

	/* --- features ------------------------------------------------------ */

	.features {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-lg);
		padding: 11rem var(--space-2xl) 5rem;
		max-width: 78rem;
		margin: 0 auto;
	}

	.feature {
		display: flex;
		flex-direction: column;
		padding: var(--space-lg);
		border-radius: var(--radius-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		box-shadow: var(--shadow-sm);
		transition: all var(--transition-base);
	}

	.feature:hover {
		transform: translateY(-4px);
		box-shadow: var(--shadow-lg);
	}

	/* Each card leads with the thing it is describing rather than an icon
	   standing in for it. The map is the product's own TrackPreview; the
	   rest are the real shapes of the surfaces they name. */
	.feature-visual {
		height: 6.5rem;
		border-radius: var(--radius-lg);
		background: var(--color-bg-tertiary);
		border: 1px solid var(--color-border);
		margin-bottom: var(--space-md);
		padding: var(--space-sm);
		overflow: hidden;
	}

	.feature-visual--chart {
		display: flex;
		align-items: flex-end;
		gap: 0.25rem;
	}

	.chart-bar {
		flex: 1;
		border-radius: var(--radius-sm) var(--radius-sm) 0 0;
		background: var(--color-primary);
	}

	.feature-visual--chips {
		display: flex;
		flex-wrap: wrap;
		align-content: center;
		justify-content: center;
		gap: var(--space-xs);
	}

	.chip {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		padding: 0.25rem 0.6rem;
		border-radius: var(--radius-pill);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		color: var(--color-text-secondary);
	}

	.feature-visual--week {
		display: grid;
		grid-template-columns: repeat(7, minmax(0, 1fr));
		gap: 0.3rem;
		align-items: end;
		height: 100%;
	}

	.day {
		border-radius: var(--radius-sm);
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
	}

	/* Height is the session, not decoration: a rest day is a stub, a long run
	   is the tallest bar of the week. */
	.day--rest { height: 18%; }
	.day--easy { height: 48%; background: var(--zone-2); border-color: transparent; }
	.day--tempo { height: 74%; background: var(--zone-4); border-color: transparent; }
	.day--long { height: 100%; background: var(--zone-3); border-color: transparent; }

	/* Four accents, one per card, each a theme-aware ink on the card's own
	   surface so both halves flip with the theme. Colour carries nothing
	   here — the eyebrow, heading and body each say what the card is — so
	   the four are picked for spread, not for meaning. Measured in
	   contrast_guard.test.ts against --color-surface in both themes. */
	.feature-eyebrow {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		margin-bottom: var(--space-2xs);
	}

	.feature:nth-child(1) .feature-eyebrow { color: var(--color-primary); }
	.feature:nth-child(2) .feature-eyebrow { color: var(--color-secondary-text); }
	.feature:nth-child(3) .feature-eyebrow { color: var(--color-success-text); }
	.feature:nth-child(4) .feature-eyebrow { color: var(--color-accent-cyan-text); }

	.feature h3 {
		font-size: 1.25rem;
		font-weight: 700;
		line-height: 1.25;
		letter-spacing: -0.01em;
		margin-bottom: var(--space-sm);
		text-wrap: balance;
	}

	.feature p {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.6;
		margin-top: auto;
	}

	/* --- platforms ------------------------------------------------------ */

	.apps-section {
		padding: 5rem var(--space-2xl) 6rem;
		background: var(--color-bg-secondary);
		border-top: 1px solid var(--color-border);
		border-bottom: 1px solid var(--color-border);
	}

	.section-head {
		max-width: 44rem;
		margin: 0 auto var(--space-xl);
		text-align: center;
	}

	.section-head h2 {
		font-size: clamp(1.75rem, 3vw, 2.25rem);
		font-weight: 800;
		letter-spacing: -0.02em;
		margin-bottom: var(--space-md);
		text-wrap: balance;
	}

	.section-head p {
		color: var(--color-text-secondary);
		font-size: 1.05rem;
	}

	/* Five equal cards, four of them stamped COMING SOON, made "mostly
	   unreleased" the loudest thing on the page. A pill strip states the
	   same fact in one line without giving it four cards of weight. */
	.platforms {
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
		align-items: baseline;
		gap: var(--space-sm);
		padding: 0.5rem var(--space-md);
		border-radius: var(--radius-pill);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
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
		max-width: 40rem;
		margin: 0 auto;
		text-align: center;
		font-size: 0.9rem;
		line-height: 1.6;
		color: var(--color-text-secondary);
	}

	/* --- closing -------------------------------------------------------- */

	/* Deliberately NOT the hero ramp. Two identical gradient slabs read as
	   two heroes; this one is the product's own primary teal, which is what
	   the visitor meets on the other side of the sign-in. */
	.closing-cta {
		padding: 5rem var(--space-2xl);
		text-align: center;
		background: linear-gradient(135deg, #102A32 0%, #2C5F6E 100%);
		color: #FFFFFF;
	}

	.closing-cta h2 {
		font-size: clamp(1.75rem, 3vw, 2rem);
		font-weight: 800;
		letter-spacing: -0.02em;
		margin-bottom: var(--space-sm);
		text-wrap: balance;
	}

	.closing-cta p {
		color: rgba(255, 255, 255, 0.85);
		margin-bottom: var(--space-xl);
		font-size: 1.05rem;
	}

	.closing-cta .btn-primary {
		color: #1F4854;
	}

	.closing-cta .btn-primary:hover {
		background: #EAF3F5;
	}

	@media (max-width: 1100px) {
		.features { grid-template-columns: repeat(2, minmax(0, 1fr)); }
	}

	@media (max-width: 60rem) {
		.hero { padding-top: 7rem; }
		.hero-preview { margin-block-end: -4rem; }
		.features { padding-top: 8rem; }
	}

	@media (max-width: 768px) {
		.hero { padding-inline: var(--space-md); }
		.features {
			grid-template-columns: minmax(0, 1fr);
			padding-inline: var(--space-md);
		}
		.apps-section { padding-inline: var(--space-md); }
	}
</style>
