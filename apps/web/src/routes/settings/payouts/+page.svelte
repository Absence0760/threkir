<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import {
		fetchHostEarnings,
		fetchPayoutAccount,
		startConnectOnboarding,
		type PayoutAccountStatus
	} from '$lib/core/data';
	import { currentLocale, m } from '$lib/i18n/store.svelte';
	import { formatPrice } from '$lib/format/format_price';
	import { fromMinorUnits } from '$lib/format/minor_units';
	import {
		formatClassStart,
		formatEarningsMonth,
		rollupEarningsByMonth,
		type HostEarningsMonth
	} from '$lib/social/host_earnings';

	let account = $state<PayoutAccountStatus | null>(null);
	let loaded = $state(false);
	let redirecting = $state(false);
	let earnings = $state<HostEarningsMonth[]>([]);
	let earningsState = $state<'idle' | 'loading' | 'ready' | 'failed'>('idle');

	// Onboarding started but not yet charges-enabled — Stripe still needs
	// more info. Restricted = onboarding submitted but charges disabled.
	let status = $derived.by<'none' | 'ready' | 'incomplete' | 'restricted'>(() => {
		if (!account) return 'none';
		if (account.charges_enabled) return 'ready';
		if (account.details_submitted) return 'restricted';
		return 'incomplete';
	});

	onMount(async () => {
		// Wait for the auth store to hydrate before reading auth.user —
		// there's a window where auth.loading has flipped false but `user`
		// is still null (fetchUser in flight), and gating the fetch on that
		// stale null would render the no-account state to a signed-in host.
		await auth.ready();
		if (auth.user) {
			account = await fetchPayoutAccount();
		}
		loaded = true;
		if (account) await loadEarnings();
	});

	// Only a host with a payout account can have been paid, so the summary
	// is read only then. A failed read is its own state with a retry: an
	// empty list would tell a paid instructor they earned nothing.
	async function loadEarnings() {
		earningsState = 'loading';
		try {
			earnings = rollupEarningsByMonth(await fetchHostEarnings());
			earningsState = 'ready';
		} catch {
			earningsState = 'failed';
		}
	}

	function money(cents: number, currency: string): string {
		return formatPrice(fromMinorUnits(cents, currency), {
			currency: currency.toUpperCase(),
			locale: currentLocale()
		});
	}

	async function startSetup() {
		if (redirecting) return;
		redirecting = true;
		try {
			const { url } = await startConnectOnboarding();
			window.location.href = url;
		} catch (err) {
			// A build without Stripe Connect keys returns a 503
			// (events-connect-onboard fails closed). Treat that like the
			// upgrade page's not-configured fallback: an info toast, no
			// red error, page stays usable.
			const msg = err instanceof Error ? err.message : String(err);
			// `startConnectOnboarding` unwraps the function's own
			// `{ error: '<code>' }` envelope, so the machine code arrives
			// here. The pattern stays as tolerance for a refusal whose body
			// could not be read at all.
			if (msg === 'stripe_not_configured' || /not[_ ]configured|503/i.test(msg)) {
				showToast(m('payouts.notConfigured'), 'info');
			} else {
				showToast(m('payouts.setupFailed', { error: msg }), 'error');
			}
			redirecting = false;
		}
	}
</script>

<svelte:head>
	<title>{m('payouts.pageTitle')}</title>
</svelte:head>

<div class="page">
	<header class="hero">
		<p class="kicker">{m('shell.settings')}</p>
		<h1>{m('payouts.heroTitle')}</h1>
		<p class="tagline">{m('payouts.heroTagline')}</p>
	</header>

	<section class="card" aria-busy={!loaded}>
		{#if !loaded}
			<p class="muted">{m('payouts.redirecting')}</p>
		{:else if status === 'ready'}
			<div class="status status-ready" role="status">
				<span class="material-symbols" aria-hidden="true">check_circle</span>
				<span>{m('payouts.statusReady')}</span>
			</div>
			<p class="merchant-note">{m('payouts.merchantNote')}</p>
			<button class="btn btn-outline" onclick={startSetup} disabled={redirecting}>
				{redirecting ? m('payouts.redirecting') : m('payouts.manageDashboard')}
			</button>
		{:else if status === 'incomplete' || status === 'restricted'}
			<div class="status status-warn" role="status">
				<span class="material-symbols" aria-hidden="true">error</span>
				<span>
					{status === 'restricted'
						? m('payouts.statusRestricted')
						: m('payouts.statusIncomplete')}
				</span>
			</div>
			<button class="btn btn-primary" onclick={startSetup} disabled={redirecting}>
				{redirecting ? m('payouts.redirecting') : m('payouts.continueSetup')}
			</button>
		{:else}
			<p class="merchant-note">{m('payouts.merchantNote')}</p>
			<button class="btn btn-primary" onclick={startSetup} disabled={redirecting}>
				{redirecting ? m('payouts.redirecting') : m('payouts.setupCta')}
			</button>
		{/if}
	</section>

	{#if loaded && account}
		<section class="earnings" aria-labelledby="earnings-title" aria-busy={earningsState === 'loading'}>
			<h2 id="earnings-title">{m('payouts.earningsTitle')}</h2>
			<p class="earnings-intro">{m('payouts.earningsIntro')}</p>
			{#if earningsState === 'loading' || earningsState === 'idle'}
				<p class="muted">{m('payouts.earningsLoading')}</p>
			{:else if earningsState === 'failed'}
				<div class="earnings-failed" role="alert">
					<span>{m('payouts.earningsFailed')}</span>
					<button class="btn btn-outline btn-sm" onclick={loadEarnings}>
						{m('payouts.earningsRetry')}
					</button>
				</div>
			{:else if earnings.length === 0}
				<p class="muted">{m('payouts.earningsEmpty')}</p>
			{:else}
				<ul class="months">
					{#each earnings as month (month.month + month.currency)}
						<li class="month card">
							<div class="month-head">
								<h3>
									{m('payouts.earningsMonthHeading', {
										month: formatEarningsMonth(month.month, currentLocale()),
										currency: month.currency.toUpperCase()
									})}
								</h3>
								<p class="net">
									<span class="net-label">{m('payouts.earningsNet')}</span>
									<span class="net-value" data-testid="earnings-net">
										{money(month.net_cents, month.currency)}
									</span>
								</p>
							</div>
							<dl class="figures">
								<div>
									<dt>{m('payouts.earningsRegistrations')}</dt>
									<dd>{month.registrations}</dd>
								</div>
								<div>
									<dt>{m('payouts.earningsGross')}</dt>
									<dd>{money(month.gross_cents, month.currency)}</dd>
								</div>
								<div>
									<dt>{m('payouts.earningsRefunded')}</dt>
									<dd>{money(month.refunded_cents, month.currency)}</dd>
								</div>
								<div>
									<dt>{m('payouts.earningsFee')}</dt>
									<dd>{money(month.platform_fee_cents, month.currency)}</dd>
								</div>
							</dl>
							{#if month.partial_refunds_unrecorded > 0}
								<p class="note">
									{m('payouts.earningsUnrecorded', { n: month.partial_refunds_unrecorded })}
								</p>
							{/if}
							{#if month.refund_failed_orders > 0}
								<p class="note note-warn">
									{m('payouts.earningsRefundFailed', {
										n: month.refund_failed_orders,
										amount: money(month.unsettled_cents, month.currency)
									})}
								</p>
							{/if}
							<details>
								<summary>{m('payouts.earningsByClass', { n: month.instances.length })}</summary>
								<div class="table-wrap">
									<table>
										<thead>
											<tr>
												<th scope="col">{m('payouts.earningsClassCol')}</th>
												<th scope="col">{m('payouts.earningsWhenCol')}</th>
												<th scope="col" class="num">{m('payouts.earningsRegistrations')}</th>
												<th scope="col" class="num">{m('payouts.earningsNet')}</th>
											</tr>
										</thead>
										<tbody>
											{#each month.instances as row (row.event_id + row.instance_start)}
												<tr>
													<td>{row.event_title}</td>
													<td>{formatClassStart(row.instance_start, row.timezone, currentLocale())}</td>
													<td class="num">{row.registrations}</td>
													<td class="num">{money(row.net_cents, row.currency)}</td>
												</tr>
											{/each}
										</tbody>
									</table>
								</div>
							</details>
						</li>
					{/each}
				</ul>
				<p class="footnote">{m('payouts.earningsFootnote')}</p>
			{/if}
		</section>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 48rem;
	}
	.hero {
		margin-bottom: var(--space-xl);
		max-width: 40rem;
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-2xs);
	}
	.hero h1 {
		font-size: 1.7rem;
		font-weight: 800;
		margin: 0 0 var(--space-sm);
		line-height: 1.15;
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.55;
		margin: 0;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		align-items: flex-start;
	}
	.status {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		font-weight: 600;
		font-size: 0.95rem;
	}
	.status .material-symbols {
		font-family: 'Material Symbols Outlined';
	}
	.status-ready {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
	}
	.status-warn {
		color: var(--color-warning-text);
	}
	.merchant-note {
		margin: 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.muted {
		color: var(--color-text-tertiary);
		margin: 0;
	}
	.earnings {
		margin-top: var(--space-xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.earnings h2 {
		font-size: 1.25rem;
		font-weight: 700;
		margin: 0;
	}
	.earnings-intro,
	.footnote {
		margin: 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.earnings-failed {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-sm);
		color: var(--color-text-secondary);
	}
	.months {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.month {
		align-items: stretch;
		gap: var(--space-sm);
	}
	.month-head {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: baseline;
		gap: var(--space-sm);
	}
	.month-head h3 {
		margin: 0;
		font-size: 1rem;
		font-weight: 700;
	}
	.net {
		margin: 0;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
	}
	.net-label {
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}
	.net-value {
		font-size: 1.3rem;
		font-weight: 800;
		font-variant-numeric: tabular-nums;
	}
	.figures {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
		gap: var(--space-sm);
		margin: 0;
	}
	.figures dt {
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}
	.figures dd {
		margin: 0;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.note {
		margin: 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.note-warn {
		color: var(--color-warning-text);
	}
	details summary {
		cursor: pointer;
		font-size: 0.9rem;
		font-weight: 600;
	}
	.table-wrap {
		overflow-x: auto;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		margin-top: var(--space-sm);
		font-size: 0.85rem;
	}
	th,
	td {
		text-align: start;
		padding: var(--space-2xs) var(--space-xs);
		border-bottom: 1px solid var(--color-border);
	}
	th {
		font-weight: 600;
		color: var(--color-text-tertiary);
	}
	.num {
		text-align: end;
		font-variant-numeric: tabular-nums;
	}
	@media (max-width: 480px) {
		.card {
			padding: var(--space-lg);
		}
	}
</style>
