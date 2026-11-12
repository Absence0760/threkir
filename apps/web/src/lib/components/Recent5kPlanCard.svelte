<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { fmtHms } from '#lib/training/training.ts';
	import type { Recent5kSuggestion } from '#lib/training/recent_5k_suggestion.ts';

	interface Props {
		suggestion: Recent5kSuggestion;
		ondismiss: () => void;
	}
	let { suggestion, ondismiss }: Props = $props();

	const date = $derived(
		new Date(suggestion.startedAt).toLocaleDateString(activeFormatLocale(), {
			day: 'numeric',
			month: 'short',
		}),
	);
	// The wizard pre-fills its recent-5K field from this and leaves the
	// "reflects my fitness today" box unticked: the time sets no paces until
	// the runner confirms it there.
	const href = $derived(`/plans/new?type=training&recent5k=${suggestion.seconds}`);
</script>

<section class="recent-5k" data-testid="dash-recent-5k">
	<div class="recent-5k-text">
		<span class="recent-5k-kicker">{m('dash.trainingPlansKicker')}</span>
		<h3>{m('dash.recent5kTitle', { time: fmtHms(suggestion.seconds), date })}</h3>
		<p>{m('dash.recent5kBody')}</p>
	</div>
	<div class="recent-5k-actions">
		<a class="btn btn-primary btn-sm" {href} data-testid="dash-recent-5k-build">{m('dash.recent5kCta')}</a>
		<button type="button" class="btn btn-outline btn-sm" onclick={ondismiss} data-testid="dash-recent-5k-dismiss">
			{m('dash.recent5kDismiss')}
		</button>
	</div>
</section>

<style>
	.recent-5k {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-lg) var(--space-xl);
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-accent-orange) 12%, var(--color-surface)) 0%,
			var(--color-surface) 70%
		);
		border: 1px solid color-mix(in srgb, var(--color-primary) 35%, var(--color-border));
		border-radius: var(--radius-xl);
	}
	.recent-5k-text {
		flex: 1 1 18rem;
		min-width: 0;
	}
	.recent-5k-kicker {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.1em;
		color: var(--color-primary);
		font-weight: 700;
		text-transform: uppercase;
	}
	.recent-5k h3 {
		font-size: 1.15rem;
		font-weight: 700;
		margin: var(--space-xs) 0 var(--space-2xs);
		color: var(--color-text);
	}
	.recent-5k p {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0;
	}
	.recent-5k-actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
	}

	@media (max-width: 480px) {
		.recent-5k {
			padding: var(--space-md);
		}
	}
</style>
