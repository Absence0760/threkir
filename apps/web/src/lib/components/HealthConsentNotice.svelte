<script lang="ts">
	// Says why something health-related was not stored, and where consent is
	// given (decisions § 2514). Heart rate and the food log are kept only with
	// health-data consent; the consent itself is the checkbox on the Account
	// page, so this links there rather than asking again in place.
	import { m } from '#lib/i18n/store.svelte.ts';

	interface Props {
		message: string;
		testid?: string;
	}
	let { message, testid = 'health-consent-notice' }: Props = $props();
</script>

<p class="health-consent-notice" role="status" data-testid={testid}>
	<span class="material-symbols" aria-hidden="true">favorite</span>
	<span>
		{message}
		<a href="/settings/account#health-data-consent">{m('healthConsent.giveConsent')}</a>
	</span>
</p>

<style>
	.health-consent-notice {
		display: flex;
		gap: var(--space-sm);
		align-items: flex-start;
		margin: 0;
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md, 0.5rem);
		background: var(--color-warning-light);
		color: var(--color-text);
		overflow-wrap: anywhere;
	}
	.health-consent-notice a {
		color: var(--color-warning-text);
		font-weight: 600;
	}
</style>
