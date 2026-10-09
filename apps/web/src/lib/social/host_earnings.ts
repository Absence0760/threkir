// The host's earnings summary (instructor_business.md M7), shaped for the
// /settings/payouts surface.
//
// `host_earnings_summary()` returns one row per (class instance, currency).
// This module rolls those rows up into calendar months without ever adding
// two currencies together: a month that sold in USD and EUR is two month
// totals, because there is no honest single figure for it.
//
// The month on each row was decided by the server in the event's own
// timezone (migration 20270723000001). It is read here as a plain
// `YYYY-MM-DD` label and never re-derived from `instance_start` in the
// browser's zone, which would move a 19:00 Los Angeles class on the 31st into
// the next month for every reader east of it.

export interface HostEarningsInstance {
  event_id: string;
  event_title: string;
  club_id: string;
  instance_start: string;
  local_month: string;
  timezone: string;
  currency: string;
  registrations: number;
  refunded_orders: number;
  partially_refunded_orders: number;
  partial_refunds_unrecorded: number;
  refund_failed_orders: number;
  gross_cents: number;
  refunded_cents: number;
  platform_fee_cents: number;
  net_cents: number;
  unsettled_cents: number;
}

export interface HostEarningsMonth {
  month: string;
  currency: string;
  registrations: number;
  refunded_orders: number;
  partial_refunds_unrecorded: number;
  refund_failed_orders: number;
  gross_cents: number;
  refunded_cents: number;
  platform_fee_cents: number;
  net_cents: number;
  unsettled_cents: number;
  instances: HostEarningsInstance[];
}

const MONTH_RE = /^(\d{4})-(\d{2})-\d{2}$/;

function count(value: unknown): number {
  const n = typeof value === "string" ? Number(value) : value;
  return typeof n === "number" && Number.isFinite(n) ? n : 0;
}

/// Narrow one RPC row. A row missing an identity or a month cannot be filed
/// anywhere and is dropped rather than shown under a made-up month; numeric
/// fields arrive as numbers from PostgREST, but a bigint can be serialised as
/// a string, so both are accepted.
export function parseHostEarningsRow(
  raw: unknown,
): HostEarningsInstance | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.event_id !== "string" || typeof r.instance_start !== "string")
    return null;
  if (typeof r.local_month !== "string" || !MONTH_RE.test(r.local_month))
    return null;
  if (typeof r.currency !== "string" || r.currency.length === 0) return null;
  return {
    event_id: r.event_id,
    event_title: typeof r.event_title === "string" ? r.event_title : "",
    club_id: typeof r.club_id === "string" ? r.club_id : "",
    instance_start: r.instance_start,
    local_month: r.local_month,
    timezone: typeof r.timezone === "string" && r.timezone ? r.timezone : "UTC",
    currency: r.currency.toLowerCase(),
    registrations: count(r.registrations),
    refunded_orders: count(r.refunded_orders),
    partially_refunded_orders: count(r.partially_refunded_orders),
    partial_refunds_unrecorded: count(r.partial_refunds_unrecorded),
    refund_failed_orders: count(r.refund_failed_orders),
    gross_cents: count(r.gross_cents),
    refunded_cents: count(r.refunded_cents),
    platform_fee_cents: count(r.platform_fee_cents),
    net_cents: count(r.net_cents),
    unsettled_cents: count(r.unsettled_cents),
  };
}

/// Group instances into (month, currency) totals, newest month first, and
/// within a month the currencies alphabetically. Each month's instances keep
/// the newest-first order they arrived in.
export function rollupEarningsByMonth(
  rows: readonly HostEarningsInstance[],
): HostEarningsMonth[] {
  const byKey = new Map<string, HostEarningsMonth>();
  for (const row of rows) {
    const key = `${row.local_month}|${row.currency}`;
    let month = byKey.get(key);
    if (!month) {
      month = {
        month: row.local_month,
        currency: row.currency,
        registrations: 0,
        refunded_orders: 0,
        partial_refunds_unrecorded: 0,
        refund_failed_orders: 0,
        gross_cents: 0,
        refunded_cents: 0,
        platform_fee_cents: 0,
        net_cents: 0,
        unsettled_cents: 0,
        instances: [],
      };
      byKey.set(key, month);
    }
    month.registrations += row.registrations;
    month.refunded_orders += row.refunded_orders;
    month.partial_refunds_unrecorded += row.partial_refunds_unrecorded;
    month.refund_failed_orders += row.refund_failed_orders;
    month.gross_cents += row.gross_cents;
    month.refunded_cents += row.refunded_cents;
    month.platform_fee_cents += row.platform_fee_cents;
    month.net_cents += row.net_cents;
    month.unsettled_cents += row.unsettled_cents;
    month.instances.push(row);
  }
  return [...byKey.values()].sort((a, b) =>
    a.month === b.month
      ? a.currency.localeCompare(b.currency)
      : b.month.localeCompare(a.month),
  );
}

/// "October 2026" for a `2026-10-01` label, in the reader's language. Built
/// from the label's own year and month at UTC noon so no reader's zone can
/// tip it into a neighbouring month.
export function formatEarningsMonth(month: string, locale?: string): string {
  const m = MONTH_RE.exec(month);
  if (!m) return month;
  const date = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, 1, 12));
  return new Intl.DateTimeFormat(locale, {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(date);
}

/// The class's start as its attendees saw it on the wall clock — in the
/// event's own timezone, the one its month was filed under.
export function formatClassStart(
  iso: string,
  timeZone: string,
  locale?: string,
): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  const opts: Intl.DateTimeFormatOptions = {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
  };
  try {
    return new Intl.DateTimeFormat(locale, { ...opts, timeZone }).format(date);
  } catch {
    return new Intl.DateTimeFormat(locale, { ...opts, timeZone: "UTC" }).format(
      date,
    );
  }
}
