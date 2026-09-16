<script lang="ts">
	import { m, currentLocale } from '$lib/i18n/store.svelte';
	import { formatDate } from '$lib/format/time';
	import {
		buildGuideDescription,
		buildGuideJsonLd,
		buildGuideTitle,
		buildLearnCanonical,
	} from '$lib/learn/learn_meta';
	import {
		getGuide,
		isEnglishFallback,
		listGuides,
		readingMinutes,
	} from '$lib/learn/guides';
	import { getCategory } from '$lib/learn/categories';
	import GuideCard from '$lib/components/GuideCard.svelte';
	import LearnCta from '$lib/components/LearnCta.svelte';
	import LearnPage from '$lib/components/LearnPage.svelte';
	import LearnBreadcrumb from '$lib/components/LearnBreadcrumb.svelte';

	let { data } = $props();

	// Resolve the category in-component (its labelKey is a typed
	// MessageKey) rather than threading the key through load, where
	// SvelteKit's serialised PageData widens it back to string.
	const category = $derived(getCategory(data.categoryId));

	// Re-resolve client-side for the active locale so a non-English
	// visitor gets the localized guide when one exists (and the
	// "in English" notice when it falls back). The build-time prerender
	// bakes the English guide; the head meta is stable across locales.
	const guide = $derived(getGuide(data.guide.slug, currentLocale()) ?? data.guide);
	const showFallbackNotice = $derived(isEnglishFallback(data.guide.slug, currentLocale()));

	const minutes = $derived(readingMinutes(data.guide.slug));

	/// Three more guides to read next, nearest first: same category before
	/// anything else, and never this one. A guide that ends in a single CTA
	/// is a dead end — the hub is the only way onward, and a reader who got
	/// to the bottom has already shown they want more than one.
	const related = $derived(
		listGuides()
			.filter((g) => g.slug !== data.guide.slug)
			.sort((a, b) => {
				const rank = (g: { category: string }) => (g.category === data.categoryId ? 0 : 1);
				return rank(a) - rank(b);
			})
			.slice(0, 3),
	);

	const pageTitle = $derived(buildGuideTitle(data.guide.title));
	const pageDesc = $derived(buildGuideDescription(data.guide.description));
	const canonicalUrl = $derived(buildLearnCanonical(data.siteUrl, `/learn/${data.guide.slug}`));
	const ogImage = $derived(data.guide.heroImage || '/og-default.png');
	const jsonLd = $derived(
		buildGuideJsonLd({
			title: data.guide.title,
			description: data.guide.description,
			slug: data.guide.slug,
			updated: data.guide.updated,
			categoryId: data.categoryId,
			categoryLabel: category ? m(category.labelKey) : '',
			base: data.siteUrl,
		}),
	);

	const GuideBody = $derived(guide.component);
</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta name="description" content={pageDesc} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={pageTitle} />
	<meta property="og:description" content={pageDesc} />
	<meta property="og:type" content="article" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content={ogImage} />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={pageTitle} />
	<meta name="twitter:description" content={pageDesc} />
	<meta name="twitter:image" content={ogImage} />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<LearnPage width="prose" banner>
	<!-- Wraps rather than replaces the <article>: a guide is genuinely an
	     article (its JSON-LD says so), and .learn-article centres itself inside
	     whatever full-width flex child holds it, so the wrapper costs no layout. -->
	<main id="main-content">
	<article class="learn-article">
		<!-- The band is the article's own <header>, so the h1 stays inside the
		     <article> its JSON-LD describes. .learn-article no longer carries
		     the column; the band and the body each carry one, which keeps
		     their left edges shared (layout.spec.ts) while the band itself
		     runs full-bleed. -->
		<div class="learn-band">
			<header class="article-head learn-column">
				<LearnBreadcrumb
					crumbs={[
						{ href: '/', label: m('learn.breadcrumbHome') },
						{ href: '/learn', label: m('learn.breadcrumbLearn') },
						...(category
							? [{ href: `/learn/category/${category.id}`, label: m(category.labelKey) }]
							: []),
					]}
				/>

				<h1>{guide.title}</h1>
				<p class="updated">
					{m('learn.lastUpdated', { date: formatDate(data.guide.updated) })}
					{#if minutes !== null}
						<span class="dot" aria-hidden="true">·</span>{m('learn.readingTime', { minutes })}
					{/if}
				</p>
			</header>
		</div>

	<div class="article-body learn-column">
		{#if showFallbackNotice}
			<p class="fallback-notice">{m('learn.englishFallbackNotice')}</p>
		{/if}

		<div class="prose">
			<GuideBody />
		</div>

		<LearnCta feature={data.guide.cta?.feature} />

		{#if related.length}
			<section class="related" aria-labelledby="related-heading">
				<h2 id="related-heading">{m('learn.keepReading')}</h2>
				<div class="related-grid">
					{#each related as next (next.slug)}
						<GuideCard guide={next} />
					{/each}
				</div>
			</section>
		{/if}
	</div>
	</article>
	</main>
</LearnPage>

<style>
	.article-head {
		padding: var(--space-xl) var(--space-md) var(--space-lg);
	}

	.article-body {
		padding: var(--space-xl) var(--space-md);
	}

	.learn-article h1 {
		font-size: 2rem;
		font-weight: 800;
		line-height: 1.15;
		margin: 0 0 var(--space-sm);
		color: var(--color-text);
	}

	.updated {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-md);
	}

	.fallback-notice {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-sm) var(--space-md);
		margin: 0 0 var(--space-lg);
	}

	.prose {
		font-size: 1.02rem;
		line-height: 1.7;
		color: var(--color-text);
	}

	.prose :global(h2) {
		font-size: 1.4rem;
		font-weight: 700;
		margin: var(--space-xl) 0 var(--space-sm);
		color: var(--color-text);
	}

	.prose :global(h3) {
		font-size: 1.15rem;
		font-weight: 700;
		margin: var(--space-lg) 0 var(--space-xs);
		color: var(--color-text);
	}

	.prose :global(p) {
		margin: 0 0 var(--space-md);
	}

	.prose :global(ul),
	.prose :global(ol) {
		margin: 0 0 var(--space-md);
		padding-inline-start: 1.4rem;
	}

	.prose :global(li) {
		margin-bottom: var(--space-xs);
	}

	.prose :global(a) {
		color: var(--color-primary);
	}

	.prose :global(strong) {
		font-weight: 700;
	}

	@media (min-width: 48rem) {
		/* The padding lives on the two bands now, not on the <article>: the
		   band must reach the viewport edge or the overlay header's white ink
		   sits on the page background instead of on the ramp. */
		.article-head {
			padding-block: var(--space-2xl) var(--space-lg);
		}
		.article-body {
			padding-block: var(--space-2xl);
		}
		.learn-article h1 {
			font-size: 2.4rem;
		}
	}

	.dot {
		margin-inline: 0.4rem;
	}

	.related {
		margin-block-start: var(--space-2xl);
		padding-block-start: var(--space-xl);
		border-block-start: 1px solid var(--color-border);
	}

	.related h2 {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-md);
	}

	/* The article column is a reading measure, so three cards across it would
	   be unreadably narrow; they stack until there is room for two. */
	.related-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(15rem, 100%), 1fr));
		gap: var(--space-md);
	}
</style>
