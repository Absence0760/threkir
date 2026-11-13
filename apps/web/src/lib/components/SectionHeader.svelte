<script lang="ts">
	import type { Snippet } from 'svelte';

	// The heading over a group of content, the web twin of ui_kit's
	// `SectionHeader` (conventions.md § Web section headers; issue #1374). Same
	// two forms as mobile: the eyebrow (the default — small, uppercase, muted,
	// naming a group of rows, a card or a list) and `title` (the in-body
	// heading of a block on a detail page, sentence case at body-title size).
	//
	// Both are real headings at the `level` the page outline needs, so a
	// screen reader's heading list finds every section; the mobile eyebrow is
	// not announced as a header, but a web page has a heading outline that a
	// keyboard user moves through, and a group with no heading drops out of it.
	//
	// `trailing` is the section's action (a link, a button, a pill). It shares
	// the heading's line while both fit and wraps under the heading when they
	// do not — a long translation or a large text size — rather than squeezing
	// the heading or running off the card. `badge` sits inside the heading, so
	// it is part of the heading's name (a count, a rating); an `InfoTip` goes
	// in `trailing`, outside the name (info_tip_placement_guard.test.ts).
	//
	// Spacing under the header is the component's (`flush` drops it for a
	// parent that lays its children out with a gap); a page's own class goes
	// on the header for any other layout, styled from the page with
	// `:global(.page-class)`, which wins because the component's spacing
	// rules are zero-specificity `:where()`.
	let {
		label,
		title = false,
		level = 2,
		icon,
		id,
		badge,
		trailing,
		flush = false,
		tone = 'default',
		class: extra = '',
		testid,
		headingTestid,
	}: {
		label: string;
		/// The in-body title form rather than the eyebrow.
		title?: boolean;
		level?: 2 | 3 | 4 | 5 | 6;
		/// A Material Symbols ligature identifying the group, decorative.
		icon?: string;
		/// The heading's id, for an `aria-labelledby` on the section it names.
		id?: string;
		badge?: Snippet;
		trailing?: Snippet;
		flush?: boolean;
		/// `muted`: a title for a lesser group, in the secondary text colour.
		/// `danger`: a section of destructive actions, in the danger text
		/// colour (the twin of mobile's `iconColor` carrying a group's own
		/// semantic colour). `inherit`: the surrounding text colour, for a
		/// header on a fixed brand canvas whose own colours are calibrated to
		/// it (the race-day panel's white on its gradient).
		tone?: 'default' | 'muted' | 'danger' | 'inherit';
		class?: string;
		testid?: string;
		headingTestid?: string;
	} = $props();
</script>

{#snippet heading(cls: string, tid: string | undefined)}
	<svelte:element this={`h${level}`} {id} class={cls} data-testid={tid}>
		{#if icon}<span class="material-symbols sh-icon" aria-hidden="true">{icon}</span>{/if}
		<span class="section-header-label">{label}</span>
		{#if badge}{@render badge()}{/if}
	</svelte:element>
{/snippet}

{#if trailing}
	<div
		class="section-header {extra}"
		class:sh-title={title}
		class:sh-eyebrow={!title}
		class:sh-flush={flush}
		class:sh-muted={tone === 'muted'}
		class:sh-danger={tone === 'danger'}
		class:sh-inherit={tone === 'inherit'}
		data-testid={testid}
	>
		{@render heading('section-header-heading', headingTestid)}
		<div class="sh-trailing">{@render trailing()}</div>
	</div>
{:else}
	<!-- No wrapper without an action: the heading alone is valid wherever a
	     heading is, a <summary> included. -->
	{@render heading(
		`section-header section-header-heading ${extra} ${title ? 'sh-title' : 'sh-eyebrow'}${flush ? ' sh-flush' : ''}${tone === 'default' ? '' : ` sh-${tone}`}`,
		headingTestid ?? testid,
	)}
{/if}

<style>
	.section-header-heading {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-xs);
		min-width: 0;
		overflow-wrap: anywhere;
	}
	/* The spacing rules carry no specificity, so a page's
	   `:global(.its-class)` margin wins over them without a fight. */
	:where(.section-header-heading) {
		margin: 0;
	}
	div.section-header {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		column-gap: var(--space-md);
		row-gap: var(--space-xs);
	}
	:where(.section-header) {
		margin: 0 0 var(--space-sm);
	}
	:where(.section-header.sh-title) {
		margin-bottom: var(--space-md);
	}
	:where(.section-header.sh-flush) {
		margin: 0;
	}
	.sh-eyebrow.section-header-heading,
	.sh-eyebrow .section-header-heading {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: var(--section-label-tracking);
		line-height: 1.4;
		color: var(--color-text-tertiary);
	}
	.sh-title.section-header-heading,
	.sh-title .section-header-heading {
		font-size: var(--font-size-section-title);
		font-weight: 700;
		line-height: 1.35;
		color: var(--color-text);
	}
	.sh-title.sh-muted.section-header-heading,
	.sh-title.sh-muted .section-header-heading {
		color: var(--color-text-secondary);
	}
	.sh-danger.section-header-heading,
	.sh-danger .section-header-heading {
		color: var(--color-danger-text);
	}
	.sh-inherit.section-header-heading,
	.sh-inherit .section-header-heading {
		color: inherit;
	}
	.sh-icon {
		font-size: 1rem;
		line-height: 1;
	}
	.sh-title .sh-icon,
	.sh-title.section-header-heading .sh-icon {
		font-size: 1.25rem;
	}
	.sh-trailing {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		flex-wrap: wrap;
	}
</style>
