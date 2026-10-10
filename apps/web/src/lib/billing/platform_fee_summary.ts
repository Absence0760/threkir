/// Shaping for the operator's platform-fee earnings page (/admin/earnings).
/// The money rules live in SQL (`private.platform_fee_lines`, decisions
/// § 1817); this only folds the two sources into one row per month and
/// currency, and never adds one currency to another.

export type PlatformFeeSource = 'event' | 'donation';

export interface PlatformFeeMonthRow {
	/** First day of the UTC calendar month, `YYYY-MM-DD`. */
	month: string;
	currency: string;
	source: PlatformFeeSource;
	charge_count: number;
	gross_fee_cents: number;
	reversed_fee_cents: number;
	net_fee_cents: number;
	refunded_count: number;
	partially_refunded_count: number;
	refund_failed_count: number;
}

export interface PlatformFeeMonthSummary {
	month: string;
	currency: string;
	charge_count: number;
	gross_fee_cents: number;
	reversed_fee_cents: number;
	net_fee_cents: number;
	refunded_count: number;
	partially_refunded_count: number;
	refund_failed_count: number;
}

export interface PlatformFeeCurrencyTotal {
	currency: string;
	gross_fee_cents: number;
	reversed_fee_cents: number;
	net_fee_cents: number;
}

/** One row per month + currency, newest month first, currencies A–Z. */
export function summarizeFeeMonths(rows: readonly PlatformFeeMonthRow[]): PlatformFeeMonthSummary[] {
	const byKey = new Map<string, PlatformFeeMonthSummary>();
	for (const r of rows) {
		const key = `${r.month}|${r.currency}`;
		const acc = byKey.get(key) ?? {
			month: r.month,
			currency: r.currency,
			charge_count: 0,
			gross_fee_cents: 0,
			reversed_fee_cents: 0,
			net_fee_cents: 0,
			refunded_count: 0,
			partially_refunded_count: 0,
			refund_failed_count: 0,
		};
		acc.charge_count += r.charge_count;
		acc.gross_fee_cents += r.gross_fee_cents;
		acc.reversed_fee_cents += r.reversed_fee_cents;
		acc.net_fee_cents += r.net_fee_cents;
		acc.refunded_count += r.refunded_count;
		acc.partially_refunded_count += r.partially_refunded_count;
		acc.refund_failed_count += r.refund_failed_count;
		byKey.set(key, acc);
	}
	return [...byKey.values()].sort(
		(a, b) => (a.month === b.month ? a.currency.localeCompare(b.currency) : a.month < b.month ? 1 : -1),
	);
}

/** All-time totals, one per currency, A–Z. */
export function feeTotalsByCurrency(rows: readonly PlatformFeeMonthRow[]): PlatformFeeCurrencyTotal[] {
	const byCurrency = new Map<string, PlatformFeeCurrencyTotal>();
	for (const r of rows) {
		const acc = byCurrency.get(r.currency) ?? {
			currency: r.currency,
			gross_fee_cents: 0,
			reversed_fee_cents: 0,
			net_fee_cents: 0,
		};
		acc.gross_fee_cents += r.gross_fee_cents;
		acc.reversed_fee_cents += r.reversed_fee_cents;
		acc.net_fee_cents += r.net_fee_cents;
		byCurrency.set(r.currency, acc);
	}
	return [...byCurrency.values()].sort((a, b) => a.currency.localeCompare(b.currency));
}

/** "September 2026" for `2026-09-01`, in the reader's locale but always the
 *  UTC month: formatting the midnight-UTC instant in a zone west of UTC would
 *  otherwise name the month before. */
export function formatFeeMonth(month: string, locale: string): string {
	const instant = new Date(`${month}T00:00:00Z`);
	if (Number.isNaN(instant.getTime())) return month;
	return new Intl.DateTimeFormat(locale, { year: 'numeric', month: 'long', timeZone: 'UTC' }).format(instant);
}
