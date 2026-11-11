<script lang="ts">
	import { DM_LINK_REL, dmTextSegments } from '#lib/social/dm_link.ts';

	let { body }: { body: string } = $props();
	const segments = $derived(dmTextSegments(body));
</script>

<span class="text"
	>{#each segments as seg, i (i)}{#if seg.kind === 'link'}<a
				href={seg.href}
				target="_blank"
				rel={DM_LINK_REL}
				data-testid="dm-link">{seg.text}</a
			><span class="link-domain" data-testid="dm-link-domain"
				><span class="material-symbols" aria-hidden="true">link</span>{seg.domain}</span
			>{:else}{seg.text}{/if}{/each}</span
>

<style>
	.text {
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
	a {
		color: inherit;
		text-decoration: underline;
	}
	.link-domain {
		display: inline-flex;
		align-items: center;
		gap: 0.15rem;
		margin-inline-start: 0.3rem;
		padding: 0 0.4rem;
		border-radius: 999px;
		font-size: 0.75rem;
		background: color-mix(in srgb, currentColor 12%, transparent);
		vertical-align: middle;
	}
	.link-domain .material-symbols {
		font-size: 0.85rem;
	}
</style>
