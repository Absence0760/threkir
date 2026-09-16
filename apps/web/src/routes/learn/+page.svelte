<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { buildLearnCanonical, buildLearnCollectionJsonLd } from '$lib/learn/learn_meta';
	import { guidesByCategory } from '$lib/learn/guides';
	import GuideCard from '$lib/components/GuideCard.svelte';
	import LearnCategoryNav from '$lib/components/LearnCategoryNav.svelte';
	import LearnSignupCta from '$lib/components/LearnSignupCta.svelte';
	import LearnPage from '$lib/components/LearnPage.svelte';
	import LearnBreadcrumb from '$lib/components/LearnBreadcrumb.svelte';

	let { data } = $props();

	const pageTitle = $derived(m('learn.hubPageTitle'));
	const pageDesc = $derived(m('learn.hubPageDescription'));
	const canonicalUrl = $derived(buildLearnCanonical(data.siteUrl, '/learn'));

	// Category order first, guide order within it — the same sequence the
	// grid renders, so the ItemList describes the page a reader sees rather
	// than a second ordering.
	const ordered = $derived(data.categories.flatMap((c) => guidesByCategory(c.id)));
	const listedGuides = $derived(ordered.map((g) => ({ slug: g.slug, title: g.title })));

	// The hub used to render one section per category, and five of the seven
	// hold a single guide — a heading, one card, and an `auto-fill` grid whose
	// remaining tracks stayed empty, so the page was mostly dead space. One
	// grid of everything, with the category chips carrying the per-category
	// browse that the section headings used to, and the first guide promoted
	// as the obvious place to start.
	const featured = $derived(ordered[0]);
	const rest = $derived(ordered.slice(1));
	const jsonLd = $derived(
		buildLearnCollectionJsonLd({
			title: pageTitle,
			description: pageDesc,
			category: null,
			guides: listedGuides,
			base: data.siteUrl,
		}),
	);
</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta name="description" content={pageDesc} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={pageTitle} />
	<meta property="og:description" content={pageDesc} />
	<meta property="og:type" content="website" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og-default.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={pageTitle} />
	<meta name="twitter:description" content={pageDesc} />
	<meta name="twitter:image" content="/og-default.png" />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<LearnPage>
	<div class="learn-band">
		<section class="hero learn-column">
		<LearnBreadcrumb crumbs={[{ href: '/', label: m('learn.breadcrumbHome') }]} />
		<p class="kicker">{m('learn.hubKicker')}</p>
		<h1>{m('learn.hubTitle')}</h1>
		<p class="hero-sub">{m('learn.hubSub')}</p>
		</section>
	</div>

	<main class="content learn-column" id="main-content">
		<LearnCategoryNav />

		{#if featured}
			<section class="featured-section" aria-labelledby="learn-featured">
				<h2 id="learn-featured" class="section-label">{m('learn.startHere')}</h2>
				<GuideCard guide={featured} featured />
			</section>
		{/if}

		{#if rest.length}
			<section class="all-section" aria-labelledby="learn-all">
				<h2 id="learn-all" class="section-label">{m('learn.allGuides')}</h2>
				<div class="guide-grid">
					{#each rest as guide (guide.slug)}
						<GuideCard {guide} />
					{/each}
				</div>
			</section>
		{/if}
	</main>

	<LearnSignupCta />
</LearnPage>

<style>
	.hero {
		padding: var(--space-xl) var(--space-md) var(--space-md);
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
		color: var(--color-text);
	}

	.hero-sub {
		font-size: 1rem;
		color: var(--color-text-secondary);
		max-width: 40rem;
		margin: 0;
		line-height: 1.5;
	}

	.content {
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-xl);
	}




	.section-label {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-md);
	}

	/* `auto-fit`, not `auto-fill`: with a short final row auto-fill keeps the
	   empty tracks and the last card sits in a 17rem slot beside a void. */
	.guide-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(17rem, 100%), 1fr));
		gap: var(--space-md);
	}




	@media (min-width: 48rem) {
		.hero {
			padding: var(--space-2xl) var(--space-xl) var(--space-lg);
		}
		.hero h1 {
			font-size: 2.5rem;
		}
		.content {
			padding: var(--space-md) var(--space-xl);
		}
	}
</style>
