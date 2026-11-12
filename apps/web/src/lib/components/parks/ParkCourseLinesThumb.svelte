<script lang="ts">
	import { projectTrack } from '#lib/routes/track_projection.ts';
	import type { TrackPoint } from '#lib/types.ts';

	// Every course line of a park in one SVG thumbnail, projected into one
	// shared frame so the courses sit where they do relative to each other.
	// Decoration beside a card that names the park in text, so it is hidden
	// from assistive tech; static SVG, so it costs no tile request.

	let { lines, aspect = 2 }: { lines: TrackPoint[][]; aspect?: number } = $props();

	const PAD = 6;
	let vbW = $derived(100 * aspect);
	const vbH = 100;

	let paths = $derived.by(() => {
		const drawn = lines.filter((l) => l.length >= 2);
		const all = drawn.flat();
		const projected = projectTrack(all, vbW, vbH, PAD);
		if (projected.length === 0) return [];
		const out: string[] = [];
		let at = 0;
		for (const line of drawn) {
			const pts = projected.slice(at, at + line.length);
			at += line.length;
			out.push(pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' '));
		}
		return out;
	});
</script>

<svg
	viewBox="0 0 {vbW} {vbH}"
	xmlns="http://www.w3.org/2000/svg"
	class="park-lines-thumb"
	preserveAspectRatio="xMidYMid meet"
	aria-hidden="true"
	focusable="false"
>
	{#each paths as d, i (i)}
		<path {d} class="casing" />
	{/each}
	{#each paths as d, i (i)}
		<path {d} class="course-line" />
	{/each}
</svg>

<style>
	.park-lines-thumb {
		display: block;
		width: 100%;
		height: 100%;
	}
	path {
		fill: none;
		stroke-linecap: round;
		stroke-linejoin: round;
	}
	.casing {
		stroke: var(--color-surface);
		stroke-width: 4.5;
	}
	.course-line {
		stroke: var(--color-primary);
		stroke-width: 2.2;
		stroke-opacity: 0.85;
	}
</style>
