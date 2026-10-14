<script lang="ts">
	/// One help-guide string with its markup rendered: bold on-screen labels,
	/// emphasis, links to other guides and to app screens. Tokens come from
	/// `parseMarkup`, never {@html}. A route link whose route takes params has
	/// no single address, so it renders as its label.
	import { parseMarkup, routeHref } from '#lib/help/markup.ts';

	let { text }: { text: string } = $props();
	const tokens = $derived(parseMarkup(text));
</script>

{#each tokens as token, i (i)}{#if token.kind === 'strong'}<strong class="help-ui-label">{token.text}</strong>{:else if token.kind === 'em'}<em>{token.text}</em>{:else if token.kind === 'guide'}<a href="/help/{token.id}">{token.text}</a>{:else if token.kind === 'route'}{@const href = routeHref(token.routeId)}{#if href}<a {href}>{token.text}</a>{:else}{token.text}{/if}{:else}{token.text}{/if}{/each}

<style>
	.help-ui-label {
		font-weight: 600;
		color: var(--color-text);
	}
</style>
