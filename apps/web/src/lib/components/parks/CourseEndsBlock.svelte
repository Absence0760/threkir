<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import { formatLatLng, type CourseEnds } from '#lib/parks/park_courses.ts';
	import { mapsStartUrl } from '#lib/routes/course_drive.ts';

	// A course's start and finish as coordinates to copy, and a directions link
	// for each. `ends` comes from `courseEnds`, over the line this page already
	// draws, so it shows nothing the page does not.
	let {
		ends,
		testidPrefix,
		headingLevel = 2,
		instruction = null,
	}: {
		ends: CourseEnds;
		testidPrefix: string;
		headingLevel?: 2 | 3;
		/**
		 * The course page's one sentence about its start and finish boxes. Set,
		 * the block leads with it and a button to the start, and folds the
		 * coordinates away under it (decisions § 2582).
		 */
		instruction?: string | null;
	} = $props();

	type Which = 'start' | 'finish' | 'startFinish';
	const KEYS: Record<Which, { label: MessageKey; copy: MessageKey; directions: MessageKey }> = {
		start: { label: 'parks.legendStart', copy: 'parks.endsCopyStart', directions: 'parks.endsDirectionsStart' },
		finish: { label: 'parks.legendFinish', copy: 'parks.endsCopyFinish', directions: 'parks.endsDirectionsFinish' },
		startFinish: {
			label: 'parks.legendStartFinish',
			copy: 'parks.endsCopyStartFinish',
			directions: 'parks.endsDirectionsStartFinish',
		},
	};

	const rows = $derived<{ which: Which; point: { lat: number; lng: number } }[]>(
		ends.finish
			? [
					{ which: 'start', point: ends.start },
					{ which: 'finish', point: ends.finish },
				]
			: [{ which: 'startFinish', point: ends.start }],
	);

	let copied = $state<Which | null>(null);
	let failed = $state<Which | null>(null);

	async function copy(which: Which, text: string) {
		copied = null;
		failed = null;
		try {
			await navigator.clipboard.writeText(text);
			copied = which;
		} catch (e) {
			console.error('course ends: copy failed', e);
			failed = which;
		}
	}
</script>

{#snippet points()}
	<ul>
		{#each rows as { which, point } (which)}
			{@const text = formatLatLng(point)}
			<li data-testid="{testidPrefix}-ends-{which}">
				<span class="label">{m(KEYS[which].label)}</span>
				<code class="coords" data-testid="{testidPrefix}-ends-{which}-coords">{text}</code>
				<span class="actions">
					<button
						type="button"
						class="btn btn-outline btn-sm"
						aria-label={m(KEYS[which].copy)}
						onclick={() => copy(which, text)}
						data-testid="{testidPrefix}-ends-{which}-copy"
					>
						<span class="material-symbols" aria-hidden="true">content_copy</span>
						{m('parks.endsCopy')}
					</button>
					<a
						class="btn btn-outline btn-sm"
						href={mapsStartUrl('google', point)}
						target="_blank"
						rel="noopener noreferrer"
						aria-label={m(KEYS[which].directions)}
						data-testid="{testidPrefix}-ends-{which}-directions"
					>
						<span class="material-symbols" aria-hidden="true">directions</span>
						{m('parks.endsDirections')}
					</a>
				</span>
				<span class="status" role="status" data-testid="{testidPrefix}-ends-{which}-status">
					{#if copied === which}
						{m('parks.endsCopied')}
					{:else if failed === which}
						<span class="failed">{m('parks.endsCopyFailed')}</span>
					{/if}
				</span>
			</li>
		{/each}
	</ul>
{/snippet}

<section class="course-ends" aria-labelledby="{testidPrefix}-ends-title" data-testid="{testidPrefix}-ends">
	<svelte:element this={`h${headingLevel}`} id="{testidPrefix}-ends-title" class="title">{m('parks.endsTitle')}</svelte:element>
	{#if instruction}
		<p class="instruction" data-testid="{testidPrefix}-ends-instruction">{instruction}</p>
		<a
			class="btn btn-primary get-directions"
			href={mapsStartUrl('google', ends.start)}
			target="_blank"
			rel="noopener noreferrer"
			data-testid="{testidPrefix}-ends-get-directions"
		>
			<span class="material-symbols" aria-hidden="true">directions</span>
			{m('parks.endsGetDirections')}
		</a>
		<details class="coordinates" data-testid="{testidPrefix}-ends-coordinates">
			<summary>{m('parks.endsCoordinates')}</summary>
			{@render points()}
		</details>
	{:else}
		{@render points()}
	{/if}
</section>

<style>
	.title {
		margin: 0 0 var(--space-sm);
		font-size: 1rem;
	}
	.instruction {
		margin: 0 0 var(--space-sm);
		font-size: 1.05rem;
		font-weight: 600;
	}
	.get-directions {
		margin-bottom: var(--space-sm);
	}
	.coordinates summary {
		cursor: pointer;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xs);
	}
	ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	li {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-xs) var(--space-sm);
	}
	.label {
		font-weight: 600;
		min-width: 4.5rem;
	}
	.coords {
		font-family: var(--font-mono);
		user-select: all;
	}
	.actions {
		display: inline-flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
	}
	.status {
		flex-basis: 100%;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.failed {
		color: var(--color-danger-text);
	}
</style>
