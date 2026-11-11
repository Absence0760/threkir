<script lang="ts">
	// One still of Grisnir, rendered from his Blender model at 1x and 2x
	// (apps/web/static/brand/grisnir/README.md). Decorative: the words beside
	// him carry the moment, so the art is hidden from assistive tech. Nothing
	// moves, so there is nothing for prefers-reduced-motion to stop.
	type Pose = 'proud' | 'wait';
	const SIZES: Record<Pose, { w1: number; h1: number; w2: number }> = {
		proud: { w1: 100, h1: 183, w2: 190 },
		wait: { w1: 184, h1: 150, w2: 362 },
	};

	let { pose, width, testid }: { pose: Pose; width: string; testid?: string } = $props();
	const art = $derived(`/brand/grisnir/grisnir-${pose}`);
	const s = $derived(SIZES[pose]);
</script>

<picture class="grisnir-art" style:--grisnir-width={width} data-testid={testid} data-mascot="grisnir">
	<source type="image/webp" srcset="{art}-192.webp {s.w1}w, {art}-384.webp {s.w2}w" sizes={width} />
	<img
		src="{art}-192.png"
		srcset="{art}-192.png {s.w1}w, {art}-384.png {s.w2}w"
		sizes={width}
		width={s.w1}
		height={s.h1}
		alt=""
		aria-hidden="true"
		loading="lazy"
		decoding="async"
	/>
</picture>

<style>
	.grisnir-art {
		display: block;
		flex: none;
	}
	img {
		display: block;
		width: var(--grisnir-width);
		height: auto;
	}
</style>
