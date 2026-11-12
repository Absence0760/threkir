<script lang="ts">
	// Grisnir lying down on a plan rest day, with his one dry line (Thor's goats
	// are back by morning). A still: nothing here moves, so there is nothing
	// for prefers-reduced-motion to stop. Decorative, so the art is hidden from
	// assistive tech and the line carries the moment. Never shown in an error,
	// sync, payment or lost-GPS state (apps/web/static/brand/grisnir/README.md).
	import { m } from '#lib/i18n/store.svelte.ts';

	const ART = '/brand/grisnir/grisnir-rest';
</script>

<div class="rest-grisnir" data-testid="rest-day-grisnir">
	<picture>
		<source type="image/webp" srcset="{ART}-192.webp 184w, {ART}-384.webp 362w" sizes="7.5rem" />
		<img
			src="{ART}-192.png"
			srcset="{ART}-192.png 184w, {ART}-384.png 362w"
			sizes="7.5rem"
			width="184"
			height="162"
			alt=""
			aria-hidden="true"
			loading="lazy"
			decoding="async"
		/>
	</picture>
	<p>{m('dash.restDayGrisnir')}</p>
</div>

<style>
	.rest-grisnir {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-xs) var(--space-sm) 0;
	}
	img {
		display: block;
		width: 7.5rem;
		height: auto;
		flex: none;
	}
	p {
		margin: 0;
		font-size: 0.9rem;
		font-style: italic;
		color: var(--color-text-secondary);
	}
</style>
