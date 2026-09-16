<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import {
		buildGuideTitle,
		buildLearnCanonical,
		buildLearnCollectionJsonLd,
	} from '$lib/learn/learn_meta';
	import GuideCard from '$lib/components/GuideCard.svelte';
	import LearnCategoryNav from '$lib/components/LearnCategoryNav.svelte';
	import LearnSignupCta from '$lib/components/LearnSignupCta.svelte';
	import LearnPage from '$lib/components/LearnPage.svelte';
	import LearnBreadcrumb from '$lib/components/LearnBreadcrumb.svelte';

	let { data } = $props();

	const categoryLabel = $derived(m(data.category.labelKey));
	const pageTitle = $derived(buildGuideTitle(categoryLabel));
	const pageDesc = $derived(m('learn.hubPageDescription'));
	const canonicalUrl = $derived(
		buildLearnCanonical(data.siteUrl, `/learn/category/${data.category.id}`),
	);
	const jsonLd = $derived(
		buildLearnCollectionJsonLd({
			title: pageTitle,
			description: pageDesc,
			category: { id: data.category.id, label: categoryLabel },
			guides: data.guides.map((g) => ({ slug: g.slug, title: g.title })),
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
	<section class="hero learn-column">
		<LearnBreadcrumb
			crumbs={[
				{ href: '/', label: m('learn.breadcrumbHome') },
				{ href: '/learn', label: m('learn.breadcrumbLearn') },
			]}
		/>
		<p class="kicker">{m('learn.hubKicker')}</p>
		<h1>{categoryLabel}</h1>
	</section>

	<main class="content learn-column" id="main-content">
		<LearnCategoryNav current={data.category.id} />

		<div class="guide-grid">
			{#each data.guides as guide (guide.slug)}
				<GuideCard {guide} />
			{/each}
		</div>
	</main>

	<LearnSignupCta />
</LearnPage>

<style>
	.hero {
		padding: var(--space-xl) var(--space-md) var(--space-sm);
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
		margin: 0;
		color: var(--color-text);
	}

	.content {
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-xl);
	}

	/* auto-fit, matching the hub: with a short row auto-fill keeps the empty
	   tracks and a lone card sits in a 17rem slot beside a void. */
	.guide-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(17rem, 100%), 1fr));
		gap: var(--space-md);
	}

	@media (min-width: 48rem) {
		.hero {
			padding: var(--space-2xl) var(--space-xl) var(--space-md);
		}
		.hero h1 {
			font-size: 2.5rem;
		}
		.content {
			padding: var(--space-md) var(--space-xl);
		}
	}
</style>
