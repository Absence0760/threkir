<!--
	Where a piece of content came from (issue #1190, decisions § 2406): the
	verified organiser, a data partner or provider sync, a trace from the
	race's published map, or the community. The kind comes from the
	`provenance` helper over server-derived fields; this only renders it.

	Never colour alone: every kind carries its own icon and a visible word,
	and a screen reader hears one sentence saying what the mark means rather
	than an icon name followed by the word. Official reuses the verified-club
	ribbon so a runner learns one mark. Twin of the Flutter `ProvenanceBadge`.
-->
<script lang="ts">
	import VerifiedBadge from '#lib/components/VerifiedBadge.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { Provenance } from '#lib/social/provenance.ts';

	interface Props {
		kind: Provenance;
		size?: number;
	}
	let { kind, size = 14 }: Props = $props();

	const label = $derived(
		kind === 'official'
			? m('officialBadge.label')
			: kind === 'verified_source'
				? m('provenance.verifiedSource')
				: kind === 'traced'
					? m('provenance.traced')
					: m('provenance.community')
	);
	const description = $derived(
		kind === 'official'
			? m('officialBadge.tooltip')
			: kind === 'verified_source'
				? m('provenance.verifiedSourceTooltip')
				: kind === 'traced'
					? m('provenance.tracedTooltip')
					: m('provenance.communityTooltip')
	);
	const icon = $derived(kind === 'verified_source' ? 'database' : kind === 'traced' ? 'map' : 'people');
</script>

<span
	class="provenance-badge provenance-{kind}"
	data-testid={kind === 'official' ? 'official-badge' : 'provenance-badge'}
	data-provenance={kind}
	title={description}
>
	<span class="provenance-icon" aria-hidden="true">
		{#if kind === 'official'}
			<VerifiedBadge {size} title={description} />
		{:else}
			<span class="material-symbols" aria-hidden="true" style="font-size: {size}px">{icon}</span>
		{/if}
	</span>
	<span class="provenance-label" aria-hidden="true">{label}</span>
	<span class="visually-hidden">{description}</span>
</span>

<style>
	.provenance-badge {
		display: inline-flex;
		align-items: center;
		gap: 2px;
		font-size: 0.75rem;
		font-weight: 600;
		line-height: 1;
		vertical-align: middle;
		white-space: nowrap;
		color: var(--color-text-secondary);
	}
	.provenance-official {
		color: inherit;
	}
	.provenance-icon {
		display: inline-flex;
		line-height: 0;
	}
	.provenance-badge :global(.verified-badge) {
		margin-inline-start: 0;
	}
</style>
