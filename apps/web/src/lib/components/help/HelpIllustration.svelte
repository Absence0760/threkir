<script lang="ts">
	/// One help-guide illustration (docs/features/help.md § Illustrations). The
	/// markup is the committed `lib/help/illustrations/<id>.svg`, imported at
	/// build time: a guide names a file by id and nothing else, so no guide or
	/// fetched-translation text ever reaches {@html}, and every file passed the
	/// allow-list in `illustrationProblems` (no text, script, link or image).
	/// The placeholders become CSS variables mapped below to the app theme, so
	/// one file follows light and dark.
	import { themeIllustration } from '#lib/help/illustration.ts';

	interface Props {
		id: string;
		alt: string;
	}

	let { id, alt }: Props = $props();

	const SOURCES = import.meta.glob<string>('../../help/illustrations/*.svg', {
		eager: true,
		query: '?raw',
		import: 'default',
	});
	const BY_ID = new Map(
		Object.entries(SOURCES).map(([path, raw]) => [path.replace(/^.*\/([^/]+)\.svg$/, '$1'), themeIllustration(raw)]),
	);

	const svg = $derived(BY_ID.get(id));
</script>

{#if svg}
	<figure class="help-illustration" data-testid="help-illustration" data-illustration={id}>
		<div class="art" role="img" aria-label={alt}>
			<!-- eslint-disable-next-line svelte/no-at-html-tags -- a vetted, build-time static file -->
			{@html svg}
		</div>
	</figure>
{/if}

<style>
	.help-illustration {
		--illus-accent: var(--color-primary);
		--illus-accent-soft: var(--color-primary-light);
		--illus-muted: var(--color-text-tertiary);
		--illus-surface: var(--color-surface);
		--illus-tint: var(--color-bg-tertiary);
		--illus-positive: var(--color-success);
		--illus-caution: var(--color-warning);
		margin: var(--space-md) 0;
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
	}
	.art {
		max-width: 28rem;
		margin: 0 auto;
	}
	.art :global(svg) {
		display: block;
		width: 100%;
		height: auto;
	}
</style>
