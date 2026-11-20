<script lang="ts">
	// One still of Grisnir, rendered from his Blender model at 1x and 2x
	// (apps/web/src/lib/assets/grisnir/README.md). Decorative: the words beside
	// him carry the moment, so the art is hidden from assistive tech. Nothing
	// moves, so there is nothing for prefers-reduced-motion to stop.
	import proud192Png from '#lib/assets/grisnir/grisnir-proud-192.png?no-inline';
	import proud192Webp from '#lib/assets/grisnir/grisnir-proud-192.webp?no-inline';
	import proud384Png from '#lib/assets/grisnir/grisnir-proud-384.png?no-inline';
	import proud384Webp from '#lib/assets/grisnir/grisnir-proud-384.webp?no-inline';
	import wait192Png from '#lib/assets/grisnir/grisnir-wait-192.png?no-inline';
	import wait192Webp from '#lib/assets/grisnir/grisnir-wait-192.webp?no-inline';
	import wait384Png from '#lib/assets/grisnir/grisnir-wait-384.png?no-inline';
	import wait384Webp from '#lib/assets/grisnir/grisnir-wait-384.webp?no-inline';

	type Pose = 'proud' | 'wait';
	type Art = { w1: number; h1: number; w2: number; png1: string; png2: string; webp1: string; webp2: string };
	const ART: Record<Pose, Art> = {
		proud: { w1: 100, h1: 183, w2: 190, png1: proud192Png, png2: proud384Png, webp1: proud192Webp, webp2: proud384Webp },
		wait: { w1: 184, h1: 150, w2: 362, png1: wait192Png, png2: wait384Png, webp1: wait192Webp, webp2: wait384Webp },
	};

	let { pose, width, testid }: { pose: Pose; width: string; testid?: string } = $props();
	const s = $derived(ART[pose]);
</script>

<picture class="grisnir-art" style:--grisnir-width={width} data-testid={testid} data-mascot="grisnir">
	<source type="image/webp" srcset="{s.webp1} {s.w1}w, {s.webp2} {s.w2}w" sizes={width} />
	<img
		src={s.png1}
		srcset="{s.png1} {s.w1}w, {s.png2} {s.w2}w"
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
