<!--
	"Official" mark on content published by a verified organiser: a route,
	plan, gym routine, challenge or session plan whose club is verified and
	whose author is an owner/admin of it. The flag is derived server-side
	(`is_official`, migration 20271021000030) and never stored per row.

	Reuses the verified-club ribbon so a runner learns one mark, with a
	visible word beside it: on content the icon alone reads as "verified
	account", and the word says what it is. Twin of the Flutter
	`OfficialBadge` widget.
-->
<script lang="ts">
	import VerifiedBadge from '#lib/components/VerifiedBadge.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';

	interface Props {
		size?: number;
	}
	let { size = 14 }: Props = $props();
</script>

<span class="official-badge" data-testid="official-badge" title={m('officialBadge.tooltip')}>
	<VerifiedBadge {size} title={m('officialBadge.tooltip')} />
	<span class="official-label">{m('officialBadge.label')}</span>
</span>

<style>
	.official-badge {
		display: inline-flex;
		align-items: center;
		gap: 2px;
		font-size: 0.75rem;
		font-weight: 600;
		line-height: 1;
		vertical-align: middle;
		white-space: nowrap;
	}
	.official-badge :global(.verified-badge) {
		margin-inline-start: 0;
	}
</style>
