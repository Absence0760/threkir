<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';

	interface Props {
		/// Onboarding's closing CTA creates a training plan before any run
		/// exists, so a brand-new account can already have one. When it does,
		/// the plan hero renders above this card and the copy points at it
		/// instead of repeating "you have nothing yet".
		hasPlan?: boolean;
	}
	let { hasPlan = false }: Props = $props();
</script>

<section class="first-run" data-testid="dash-first-run">
	<span class="first-run-icon material-symbols" aria-hidden="true">directions_run</span>
	<h2>{m('dash.firstRunTitle')}</h2>
	<p class="first-run-body">
		{hasPlan ? m('dash.firstRunBodyWithPlan') : m('dash.firstRunBody')}
	</p>

	<div class="first-run-actions">
		<a class="btn btn-primary" href="/runs/new" data-testid="dash-first-run-log">
			{m('dash.addARun')}
		</a>
		<a class="btn btn-outline" href="/settings/integrations" data-testid="dash-first-run-import">
			{m('dash.importFromStravaGarmin')}
		</a>
	</div>

	<ul class="first-run-alts">
		<li>
			<span class="material-symbols" aria-hidden="true">phone_iphone</span>
			<span>{m('dash.firstRunPhoneHint')}</span>
		</li>
		<li>
			<span class="material-symbols" aria-hidden="true">fitness_center</span>
			<span>
				{m('dash.firstRunGymHintPrefix')}<a href="/gym">{m('dash.firstRunGymHintLink')}</a
				>{m('dash.firstRunGymHintSuffix')}
			</span>
		</li>
	</ul>
</section>

<style>
	.first-run {
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}
	.first-run-icon {
		font-size: 2.5rem;
		color: var(--color-primary);
	}
	.first-run h2 {
		margin: 0;
		font-size: 1.35rem;
		font-weight: 650;
		color: var(--color-text);
	}
	.first-run-body {
		margin: 0;
		max-width: 34rem;
		color: var(--color-text-secondary);
		line-height: 1.55;
	}
	.first-run-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-xs);
	}
	.first-run-alts {
		list-style: none;
		margin: var(--space-md) 0 0;
		padding: var(--space-md) 0 0;
		border-top: 1px solid var(--color-border);
		width: 100%;
		max-width: 34rem;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.first-run-alts li {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-xs);
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.first-run-alts .material-symbols {
		font-size: 1.1rem;
	}
	.first-run-alts a {
		color: var(--color-primary);
	}

	@media (max-width: 480px) {
		.first-run {
			padding: var(--space-xl) var(--space-md);
		}
		.first-run-actions {
			flex-direction: column;
			align-self: stretch;
		}
		.first-run-alts li {
			justify-content: flex-start;
			text-align: start;
		}
	}
</style>
