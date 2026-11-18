<script lang="ts">
	import type { TrackPoint } from '#lib/types.ts';
	import { projectTrack } from '#lib/routes/track_projection.ts';
	import { sketchAspect, startMeetsFinish } from '#lib/routes/course_sketch.ts';
	import { m } from '#lib/i18n/store.svelte.ts';

	// The course drawn from its own polyline with no basemap, so a public page
	// can show the shape before the visitor agrees to load map tiles (MapTiler
	// sees the requester IP). Nothing here leaves the page.

	let { points }: { points: TrackPoint[] } = $props();

	const PAD = 9;
	const MARKER_R = 3.6;

	let aspect = $derived(sketchAspect(points));
	let vbW = $derived(100 * aspect);
	const vbH = 100;
	let projected = $derived(projectTrack(points, vbW, vbH, PAD));
	let pathD = $derived(
		projected.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x.toFixed(2)} ${p.y.toFixed(2)}`).join(' '),
	);
	let start = $derived(projected[0]);
	let finish = $derived(projected[projected.length - 1]);
	let loop = $derived(startMeetsFinish(projected, MARKER_R * 2));
</script>

{#if projected.length >= 2}
	<figure class="course-sketch" style:aspect-ratio={aspect} data-testid="course-sketch">
		<svg
			viewBox="0 0 {vbW} {vbH}"
			xmlns="http://www.w3.org/2000/svg"
			preserveAspectRatio="xMidYMid meet"
			role="img"
			aria-label={m('courseSketch.label')}
		>
			<path class="casing" d={pathD} vector-effect="non-scaling-stroke" />
			<path class="line" d={pathD} vector-effect="non-scaling-stroke" />
			{#if !loop}
				<circle class="finish" cx={finish.x} cy={finish.y} r={MARKER_R} vector-effect="non-scaling-stroke" />
				<circle class="finish-dot" cx={finish.x} cy={finish.y} r={MARKER_R * 0.4} />
			{/if}
			<circle class="start" cx={start.x} cy={start.y} r={MARKER_R} vector-effect="non-scaling-stroke" />
		</svg>
		<figcaption class="legend">
			{#if loop}
				<span class="key"><span class="swatch swatch-start" aria-hidden="true"></span>{m('courseSketch.startFinish')}</span>
			{:else}
				<span class="key"><span class="swatch swatch-start" aria-hidden="true"></span>{m('courseSketch.start')}</span>
				<span class="key"><span class="swatch swatch-finish" aria-hidden="true"></span>{m('courseSketch.finish')}</span>
			{/if}
		</figcaption>
	</figure>
{/if}

<style>
	.course-sketch {
		position: relative;
		margin: 0;
		width: 100%;
		max-height: 100%;
		/* A faint dot grid so the drawing reads as a plan, not a stray line. */
		background-color: var(--color-bg-secondary);
		background-image: radial-gradient(
			var(--color-fill-subtle) 1px,
			transparent 1.2px
		);
		background-size: 1.25rem 1.25rem;
	}

	svg {
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
		stroke-width: 8;
	}

	.line {
		stroke: var(--color-primary);
		stroke-width: 4;
	}

	.start {
		fill: var(--color-primary);
		stroke: var(--color-surface);
		stroke-width: 2.5;
	}

	.finish {
		fill: var(--color-surface);
		stroke: var(--color-text);
		stroke-width: 2.5;
	}

	.finish-dot {
		fill: var(--color-text);
	}

	.legend {
		position: absolute;
		top: var(--space-sm);
		inset-inline-start: var(--space-sm);
		display: flex;
		gap: var(--space-sm);
		padding: 0.2rem 0.55rem;
		border-radius: var(--radius-pill);
		background: color-mix(in srgb, var(--color-surface) 88%, transparent);
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}

	.key {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}

	.swatch {
		width: 0.6rem;
		height: 0.6rem;
		border-radius: 50%;
		box-sizing: border-box;
	}

	.swatch-start {
		background: var(--color-primary);
	}

	.swatch-finish {
		background: var(--color-surface);
		border: 2px solid var(--color-text);
	}
</style>
