<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		amIAdmin,
		fetchPlatformFeeMonths,
		fetchPlatformFeesByHost,
		type PlatformFeeHostRow,
	} from '$lib/core/data';
	import {
		feeTotalsByCurrency,
		formatFeeMonth,
		summarizeFeeMonths,
		type PlatformFeeCurrencyTotal,
		type PlatformFeeMonthSummary,
	} from '$lib/billing/platform_fee_summary';
	import { formatPrice } from '$lib/format/format_price';
	import { fromMinorUnits } from '$lib/format/minor_units';
	import { m as t, currentLocale } from '$lib/i18n/store.svelte';

	let isAdmin = $state<boolean | null>(null);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let months = $state<PlatformFeeMonthSummary[]>([]);
	let totals = $state<PlatformFeeCurrencyTotal[]>([]);

	let selectedMonth = $state<string | null>(null);
	let hosts = $state<PlatformFeeHostRow[]>([]);
	let hostsLoading = $state(false);
	let hostsError = $state<string | null>(null);
	let hostsHeading = $state<HTMLHeadingElement | null>(null);

	const hasPartial = $derived(months.some((r) => r.partially_refunded_count > 0));

	function money(cents: number, currency: string): string {
		const code = currency.toUpperCase();
		return formatPrice(fromMinorUnits(cents, code), { currency: code });
	}

	function monthLabel(month: string): string {
		return formatFeeMonth(month, currentLocale());
	}

	function refundNotes(r: PlatformFeeMonthSummary): string[] {
		const notes: string[] = [];
		if (r.refunded_count > 0) notes.push(t('admin.earnings.refundedCount', { n: r.refunded_count }));
		if (r.partially_refunded_count > 0)
			notes.push(t('admin.earnings.partialCount', { n: r.partially_refunded_count }));
		if (r.refund_failed_count > 0) notes.push(t('admin.earnings.failedCount', { n: r.refund_failed_count }));
		return notes;
	}

	async function load() {
		loadError = null;
		try {
			const rows = await fetchPlatformFeeMonths();
			months = summarizeFeeMonths(rows);
			totals = feeTotalsByCurrency(rows);
		} catch (e) {
			loadError = t('admin.earnings.loadFailed', { error: String((e as Error)?.message ?? e) });
		}
	}

	async function openMonth(month: string) {
		selectedMonth = month;
		hosts = [];
		hostsError = null;
		hostsLoading = true;
		try {
			hosts = await fetchPlatformFeesByHost(month);
		} catch (e) {
			hostsError = t('admin.earnings.hostsFailed', { error: String((e as Error)?.message ?? e) });
		} finally {
			hostsLoading = false;
		}
		await tick();
		hostsHeading?.focus();
	}

	onMount(async () => {
		await auth.ready();
		isAdmin = await amIAdmin();
		if (isAdmin) await load();
		loading = false;
	});
</script>

<svelte:head><title>{t('admin.earnings.title')}</title></svelte:head>

<div class="page">
	{#if loading}
		<p class="muted">…</p>
	{:else if !isAdmin}
		<div class="card-elevated not-authorized" data-testid="earnings-not-authorized">
			<h1>{t('admin.earnings.notAuthorized')}</h1>
			<p class="muted">{t('admin.earnings.notAuthorizedHint')}</p>
		</div>
	{:else}
		<header>
			<h1>{t('admin.earnings.title')}</h1>
			<p class="muted">{t('admin.earnings.subtitle')}</p>
		</header>

		{#if loadError}
			<div class="card-elevated empty" role="alert" data-testid="earnings-load-error">
				<p>{loadError}</p>
			</div>
		{:else if months.length === 0}
			<div class="card-elevated empty" data-testid="earnings-empty">
				<p class="muted">{t('admin.earnings.empty')}</p>
			</div>
		{:else}
			<section class="card-elevated" aria-labelledby="earnings-totals-heading">
				<h2 id="earnings-totals-heading">{t('admin.earnings.totalsHeading')}</h2>
				<ul class="totals" data-testid="earnings-totals">
					{#each totals as total (total.currency)}
						<li data-testid="earnings-total" data-currency={total.currency}>
							<span class="total-net">{money(total.net_fee_cents, total.currency)}</span>
							<span class="muted">
								{t('admin.earnings.colGross')}: {money(total.gross_fee_cents, total.currency)} ·
								{t('admin.earnings.colReversed')}: {money(total.reversed_fee_cents, total.currency)}
							</span>
						</li>
					{/each}
				</ul>
			</section>

			<section class="card-elevated" aria-labelledby="earnings-months-heading">
				<h2 id="earnings-months-heading">{t('admin.earnings.monthsHeading')}</h2>
				<div class="table-scroll">
					<table data-testid="earnings-months">
						<thead>
							<tr>
								<th scope="col">{t('admin.earnings.colMonth')}</th>
								<th scope="col">{t('admin.earnings.colCurrency')}</th>
								<th scope="col" class="num">{t('admin.earnings.colCharges')}</th>
								<th scope="col" class="num">{t('admin.earnings.colGross')}</th>
								<th scope="col" class="num">{t('admin.earnings.colReversed')}</th>
								<th scope="col" class="num">{t('admin.earnings.colNet')}</th>
								<th scope="col">{t('admin.earnings.colRefunds')}</th>
								<th scope="col"><span class="visually-hidden">{t('admin.earnings.viewHosts')}</span></th>
							</tr>
						</thead>
						<tbody>
							{#each months as r (r.month + r.currency)}
								<tr data-testid="earnings-month-row" data-month={r.month} data-currency={r.currency}>
									<th scope="row">{monthLabel(r.month)}</th>
									<td>{r.currency.toUpperCase()}</td>
									<td class="num">{r.charge_count}</td>
									<td class="num">{money(r.gross_fee_cents, r.currency)}</td>
									<td class="num">{money(r.reversed_fee_cents, r.currency)}</td>
									<td class="num net" data-testid="earnings-month-net">{money(r.net_fee_cents, r.currency)}</td>
									<td>
										<div class="notes">
											{#each refundNotes(r) as note (note)}
												<span class="chip">{note}</span>
											{:else}
												<span class="muted">{t('admin.earnings.noRefunds')}</span>
											{/each}
										</div>
									</td>
									<td>
										<button
											type="button"
											class="btn btn-outline btn-sm"
											data-testid="earnings-view-hosts"
											aria-pressed={selectedMonth === r.month}
											onclick={() => openMonth(r.month)}
										>{t('admin.earnings.viewHosts')}</button>
									</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
				{#if hasPartial}
					<p class="muted caveat" data-testid="earnings-partial-caveat">{t('admin.earnings.partialCaveat')}</p>
				{/if}
			</section>

			{#if selectedMonth}
				<section class="card-elevated" aria-labelledby="earnings-hosts-heading" data-testid="earnings-hosts">
					<h2 id="earnings-hosts-heading" tabindex="-1" bind:this={hostsHeading}>
						{t('admin.earnings.hostsTitle', { month: monthLabel(selectedMonth) })}
					</h2>
					{#if hostsLoading}
						<p class="muted">…</p>
					{:else if hostsError}
						<p role="alert">{hostsError}</p>
					{:else if hosts.length === 0}
						<p class="muted">{t('admin.earnings.hostsEmpty')}</p>
					{:else}
						<div class="table-scroll">
							<table>
								<thead>
									<tr>
										<th scope="col">{t('admin.earnings.colHost')}</th>
										<th scope="col">{t('admin.earnings.colClub')}</th>
										<th scope="col">{t('admin.earnings.colCurrency')}</th>
										<th scope="col" class="num">{t('admin.earnings.colCharges')}</th>
										<th scope="col" class="num">{t('admin.earnings.colGross')}</th>
										<th scope="col" class="num">{t('admin.earnings.colReversed')}</th>
										<th scope="col" class="num">{t('admin.earnings.colNet')}</th>
									</tr>
								</thead>
								<tbody>
									{#each hosts as h (h.host_user_id + (h.club_id ?? '') + h.currency)}
										<tr data-testid="earnings-host-row">
											<th scope="row">
												<a href={`/u/${h.host_user_id}`}>{h.host_display_name ?? t('admin.earnings.unnamedHost')}</a>
											</th>
											<td>
												{#if h.club_slug}
													<a href={`/clubs/${h.club_slug}`}>{h.club_name ?? h.club_slug}</a>
												{:else}
													<span class="muted">{t('admin.earnings.noClub')}</span>
												{/if}
											</td>
											<td>{h.currency.toUpperCase()}</td>
											<td class="num">{h.charge_count}</td>
											<td class="num">{money(h.gross_fee_cents, h.currency)}</td>
											<td class="num">{money(h.reversed_fee_cents, h.currency)}</td>
											<td class="num net">{money(h.net_fee_cents, h.currency)}</td>
										</tr>
									{/each}
								</tbody>
							</table>
						</div>
					{/if}
				</section>
			{/if}
		{/if}
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	header h1,
	.not-authorized h1 {
		margin: 0 0 0.25rem;
		font-size: 1.4rem;
	}
	h2 {
		margin: 0 0 var(--space-sm);
		font-size: 1.05rem;
	}
	section {
		padding: var(--space-lg);
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.not-authorized,
	.empty {
		padding: var(--space-xl);
		text-align: center;
	}
	.totals {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-lg);
	}
	.totals li {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.total-net {
		font-size: 1.4rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.table-scroll {
		overflow-x: auto;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.9rem;
	}
	th,
	td {
		padding: var(--space-sm);
		border-bottom: 1px solid var(--color-border);
		text-align: start;
		vertical-align: top;
	}
	thead th {
		color: var(--color-text-secondary);
		font-weight: 600;
	}
	tbody th {
		font-weight: 500;
		white-space: nowrap;
	}
	.num {
		text-align: end;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.net {
		font-weight: 600;
	}
	.notes {
		display: flex;
		flex-wrap: wrap;
		gap: 0.3rem;
	}
	.chip {
		display: inline-block;
		padding: 0.1rem 0.45rem;
		border-radius: var(--radius-sm);
		background: var(--chip-bg);
		color: var(--chip-fg);
		font-size: 0.78rem;
	}
	.caveat {
		margin: var(--space-sm) 0 0;
		font-size: 0.85rem;
	}
	a {
		color: var(--color-primary);
	}
</style>
