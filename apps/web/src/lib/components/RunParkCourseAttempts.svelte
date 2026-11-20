<script lang="ts">
	import { currentLocale, m } from '#lib/i18n/store.svelte.ts';
	import { getUnit } from '#lib/format/units.svelte.ts';
	import { attemptCard } from '#lib/parks/park_course_attempts.ts';
	import type { ParkCourseAttempt } from '#lib/types.ts';

	interface Props {
		attempts: ParkCourseAttempt[];
	}
	let { attempts }: Props = $props();

	const cards = $derived(
		attempts.map((a) => ({ id: a.parkCourseId, ...attemptCard(a, getUnit(), currentLocale(), m) })),
	);
</script>

{#if cards.length > 0}
	<section class="attempts" aria-labelledby="park-course-attempts-heading" data-testid="run-park-course-attempts">
		<h3 id="park-course-attempts-heading">{m('runDetail.parkCourseAttempts')}</h3>
		<ul>
			{#each cards as c (c.id)}
				<li>
					<a class="attempt" href={c.href} data-testid="run-park-course-attempt">
						<span class="reason">{c.reason}</span>
						<span
							class="bar"
							role="progressbar"
							aria-label={c.barLabel}
							aria-valuemin={0}
							aria-valuemax={100}
							aria-valuenow={Math.round(c.fraction * 100)}
							aria-valuetext={c.progress}
						>
							<span class="fill" style:width="{c.fraction * 100}%"></span>
						</span>
						<span class="progress">{c.progress}</span>
					</a>
				</li>
			{/each}
		</ul>
	</section>
{/if}

<style>
	.attempts {
		padding: var(--space-sm) 0;
	}
	h3 {
		margin: 0 0 var(--space-sm);
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.attempt {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		padding: 0.75rem 1rem;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-lg);
		color: var(--color-text);
		text-decoration: none;
	}
	.attempt:hover,
	.attempt:focus-visible {
		background: var(--color-primary-light);
	}
	.reason {
		font-size: 1rem;
		font-weight: 600;
		line-height: 1.4;
	}
	.bar {
		display: block;
		height: 0.5rem;
		border-radius: 999px;
		background: var(--color-fill-subtle);
		overflow: hidden;
	}
	.fill {
		display: block;
		height: 100%;
		background: var(--color-primary);
	}
	.progress {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
</style>
