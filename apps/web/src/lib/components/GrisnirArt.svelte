<script lang="ts">
	// One still of Grisnir, rendered from his Blender model at 1x and 2x
	// (apps/web/src/lib/assets/grisnir/README.md). Decorative: the words beside
	// him carry the moment, so the art is hidden from assistive tech. Nothing
	// moves, so there is nothing for prefers-reduced-motion to stop.
	// WebP only: every browser in the package.json baseline decodes it, so a
	// PNG fallback would be URLs no reader ever fetches. The PNGs stay in the
	// asset folder for the phones.
	import proud192 from '#lib/assets/grisnir/grisnir-proud-192.webp?no-inline';
	import proud384 from '#lib/assets/grisnir/grisnir-proud-384.webp?no-inline';
	import wait192 from '#lib/assets/grisnir/grisnir-wait-192.webp?no-inline';
	import wait384 from '#lib/assets/grisnir/grisnir-wait-384.webp?no-inline';

	type Pose = 'proud' | 'wait';
	type Art = { w1: number; h1: number; w2: number; src1: string; src2: string };
	const ART: Record<Pose, Art> = {
		proud: { w1: 100, h1: 183, w2: 190, src1: proud192, src2: proud384 },
		wait: { w1: 184, h1: 150, w2: 362, src1: wait192, src2: wait384 },
	};

	let { pose, width, testid }: { pose: Pose; width: string; testid?: string } = $props();
	const s = $derived(ART[pose]);
</script>

<picture class="grisnir-art" style:--grisnir-width={width} data-testid={testid} data-mascot="grisnir">
	<img
		src={s.src1}
		srcset="{s.src1} {s.w1}w, {s.src2} {s.w2}w"
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
