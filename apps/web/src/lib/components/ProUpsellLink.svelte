<script lang="ts" module>
	export const PRO_PAGE_HREF = '/settings/upgrade';
</script>

<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';

	// Every upsell (issue #1374): why Pro would help here, then a link that
	// opens the Pro page. The message gives no directions, because the link is
	// the directions; prompts that said "upgrade" and stopped left the reader
	// to find the page. Inline, so it sits inside an error line or a note.
	// `upsell_link_guard.test.ts` fails an upsell string drawn without it.
	// Twin of mobile's `ProUpsellLink`.
	let { message, testid }: { message: string; testid?: string } = $props();
</script>

<span class="pro-upsell" data-testid={testid}
	>{message}
	<a href={PRO_PAGE_HREF} data-testid="pro-upsell-link">{m('proUpsell.seePro')}</a></span
>

<style>
	.pro-upsell a {
		font-weight: 600;
		text-decoration: underline;
		color: inherit;
	}
</style>
