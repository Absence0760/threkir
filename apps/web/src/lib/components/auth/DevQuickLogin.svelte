<script lang="ts">
	// One-click sign-in as a seed account, for `vite dev` against the local
	// stack only. The login page imports this component dynamically inside an
	// `import.meta.env.DEV` branch; see lib/auth/dev_accounts.ts for why no
	// production build carries it.
	import { PUBLIC_SUPABASE_URL } from '$app/env/public';
	import { DEV_ACCOUNTS, DEV_SIGN_IN_HEADING, isLoopbackUrl, type DevAccount } from '#lib/auth/dev_accounts.ts';

	let { onpick, disabled = false }: { onpick: (account: DevAccount) => void; disabled?: boolean } = $props();

	const local = isLoopbackUrl(PUBLIC_SUPABASE_URL);
</script>

{#if local}
	<section class="dev-login" data-testid="dev-quick-login" aria-label={DEV_SIGN_IN_HEADING}>
		<p class="dev-login-heading">{DEV_SIGN_IN_HEADING}</p>
		<div class="dev-login-buttons">
			{#each DEV_ACCOUNTS as account (account.email)}
				<button
					type="button"
					class="btn btn-outline btn-sm"
					data-testid="dev-quick-login-{account.email}"
					{disabled}
					onclick={() => onpick(account)}
				>
					{account.label}
				</button>
			{/each}
		</div>
	</section>
{/if}

<style>
	.dev-login {
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.75rem;
		margin-bottom: 1rem;
		display: grid;
		gap: 0.5rem;
	}
	.dev-login-heading {
		margin: 0;
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}
	.dev-login-buttons {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
	}
</style>
