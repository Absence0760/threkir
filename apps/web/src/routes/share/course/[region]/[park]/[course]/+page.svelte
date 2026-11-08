<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import { routeSurfaceLabel } from '#lib/i18n/enum_labels.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { distanceInPreferred, formatElevation } from '#lib/format/units.svelte.ts';
	import SharePageShell from '#lib/components/SharePageShell.svelte';
	import RunMap from '#lib/components/RunMap.svelte';
	import { regionName } from '#lib/parks/park_courses.ts';
	import {
		ATTRIBUTION_LABEL,
		DIFFICULTY_LABEL,
		SHAPE_LABEL,
		labelKey,
	} from '#lib/parks/park_labels.ts';
	import {
		buildCourseJsonLd,
		buildCourseShareCanonical,
		buildCourseShareDescription,
		buildCourseShareTitle,
	} from '#lib/share/share_course_meta.ts';
	import type { TrackPoint } from '#lib/types.ts';

	let { data } = $props();

	let title = $derived(buildCourseShareTitle(data.course));
	let description = $derived(buildCourseShareDescription(data.course));
	let canonicalUrl = $derived(buildCourseShareCanonical(data.siteUrl, data.key));
	let jsonLd = $derived(buildCourseJsonLd(data.course, { key: data.key, base: data.siteUrl }));

	let course = $derived(data.course);
	let appHref = $derived(`/parks/${data.key}`);
	let track = $derived<TrackPoint[]>(
		(course?.segment.waypoints ?? []).map((w) => ({ lat: w.lat, lng: w.lng, ele: w.ele ?? undefined })),
	);
	let distanceLabel = $derived.by(() => {
		if (!course) return '';
		const { value, unit } = distanceInPreferred(course.segment.distance_m);
		return `${value.toFixed(2)} ${unit}`;
	});
	const shapeKey = $derived(labelKey(SHAPE_LABEL, course?.course_shape));
	const difficultyKey = $derived(labelKey(DIFFICULTY_LABEL, course?.difficulty));
	const attributionKey = $derived(labelKey(ATTRIBUTION_LABEL, course?.geometry_source));
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="website" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og-default.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content="/og-default.png" />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<SharePageShell {appHref}>
	{#if course}
		<!-- The landmark rides the hero rather than a wrapper: .hero is a flex
		     child of SharePageShell's .share-page, so wrapping it would move
		     the flex child and reflow the page. -->
		<main class="hero" id="main-content">
			<p class="kicker">{m('shareCourse.subtitle')}</p>
			<h1>{course.segment.name}</h1>
			<p class="host">{course.park.name} · {regionName(course.park.region_code)}</p>
			{#if course.status === 'closed'}
				<p class="closed-banner" role="status" data-testid="share-course-closed">
					{m('parks.closedBanner')}
				</p>
			{/if}
			<dl class="stats">
				<div>
					<dt>{m('parks.statDistance')}</dt>
					<dd>{distanceLabel}</dd>
				</div>
				{#if course.segment.elevation_m != null && course.segment.elevation_m > 0}
					<div>
						<dt>{m('parks.statElevation')}</dt>
						<dd>{formatElevation(course.segment.elevation_m)}</dd>
					</div>
				{/if}
				{#if shapeKey}
					<div>
						<dt>{m('parks.statShape')}</dt>
						<dd>{m(shapeKey)}</dd>
					</div>
				{/if}
				{#if course.segment.surface}
					<div>
						<dt>{m('parks.statSurface')}</dt>
						<dd>{routeSurfaceLabel(course.segment.surface)}</dd>
					</div>
				{/if}
				{#if difficultyKey}
					<div>
						<dt>{m('parks.statDifficulty')}</dt>
						<dd>{m(difficultyKey)}</dd>
					</div>
				{/if}
			</dl>
			{#if course.segment.description}
				<p class="desc">{course.segment.description}</p>
			{/if}
			<div class="hero-actions">
				<a class="btn btn-primary" href={appHref} data-testid="share-course-boards">
					{m('shareCourse.seeBoards')}
				</a>
			</div>
		</main>
		<section class="content">
			{#if track.length >= 2}
				<div class="map-container">
					<RunMap {track} requireExplicitConsent />
				</div>
			{/if}
			{#if attributionKey}
				<p class="attribution" data-testid="share-course-attribution">{m(attributionKey)}</p>
			{/if}
			<p class="safety" data-testid="share-course-safety">{m('parks.safetyNotice')}</p>
		</section>
	{:else}
		<main class="content" id="main-content">
			<div class="notfound-card">
				<p class="kicker">{m('shareRun.notFoundKicker')}</p>
				<h1>{m('shareCourse.notFoundTitle')}</h1>
				<p class="notfound-sub">{m('shareCourse.notFoundSub')}</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/parks">{m('shareCourse.browseParks')}</a>
					<a class="btn btn-outline" href="/">{m('shareRun.goToThrekir')}</a>
				</div>
			</div>
		</main>
	{/if}

	{#if !auth.loggedIn && course}
		<section class="signup-cta" aria-labelledby="signup-cta-heading">
			<p class="kicker">{m('shareRun.ctaKicker')}</p>
			<h2 id="signup-cta-heading">{m('shareRun.ctaHeading')}</h2>
			<p class="signup-sub">{m('shareRun.ctaSub')}</p>
			<a class="btn btn-primary" href="/login?signup=1">{m('shareRun.ctaButton')}</a>
		</section>
	{/if}
</SharePageShell>

<style>
	.hero {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-xl) var(--space-md) var(--space-md);
		text-align: center;
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-sm);
	}
	.hero h1 {
		font-size: 2rem;
		font-weight: 800;
		margin: 0 0 var(--space-sm);
		line-height: 1.15;
	}
	.host {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-md);
	}
	.closed-banner {
		max-width: 34rem;
		margin: 0 auto var(--space-md);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-warning-light);
		color: var(--color-warning-text);
	}
	.stats {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(110px, 100%), 1fr));
		gap: 1px;
		max-width: 40rem;
		margin: 0 auto;
		background: var(--color-border);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		overflow: hidden;
	}
	.stats div {
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
	}
	.stats dt {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-tertiary);
	}
	.stats dd {
		margin: 0.15rem 0 0;
		font-size: 1.05rem;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.desc {
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		max-width: 34rem;
		margin: var(--space-md) auto 0;
		line-height: 1.5;
	}
	.hero-actions {
		margin-top: var(--space-md);
	}
	.content {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-md);
	}
	.map-container {
		height: 320px;
		border-radius: var(--radius-md);
		overflow: hidden;
	}
	.attribution {
		margin: 0.3rem 0 0;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}
	.safety {
		margin: var(--space-md) 0 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.notfound-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl) var(--space-lg);
		margin-top: var(--space-xl);
		text-align: center;
	}
	.notfound-card h1 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
	}
	.notfound-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 28rem;
		margin: 0 auto var(--space-lg);
		line-height: 1.5;
	}
	.notfound-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
	}
	.signup-cta {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-lg) var(--space-md) var(--space-xl);
		text-align: center;
	}
	.signup-cta h2 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
	}
	.signup-cta .signup-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 32rem;
		margin: 0 auto var(--space-md);
		line-height: 1.5;
	}
	@media (min-width: 48rem) {
		.hero {
			padding: var(--space-2xl) var(--space-xl) var(--space-lg);
		}
		.hero h1 {
			font-size: 2.5rem;
		}
	}
</style>
