/// The platform's application-fee rate, read from `platform_fees` at charge
/// time. Only the service role can read that table, so the rate is never a
/// value the paying host or fundraiser owner supplies (decisions § 1768).

import type { DbClient } from './database.ts';

export type PlatformFeeKind = 'event' | 'donation';

/// The rate in basis points, or null when it cannot be read or is out of
/// range. Callers refuse the checkout on null rather than charge a fee of 0:
/// a sale with no fee still costs the platform Stripe's processing fee.
export function parsePlatformFeeBps(
  row: { event_fee_bps: unknown; donation_fee_bps: unknown } | null,
  kind: PlatformFeeKind,
): number | null {
  if (!row) return null;
  const bps = kind === 'event' ? row.event_fee_bps : row.donation_fee_bps;
  if (typeof bps !== 'number' || !Number.isInteger(bps)) return null;
  return bps >= 0 && bps <= 10000 ? bps : null;
}

export async function readPlatformFeeBps(
  service: DbClient,
  kind: PlatformFeeKind,
): Promise<number | null> {
  const { data, error } = await service
    .from('platform_fees')
    .select('event_fee_bps, donation_fee_bps')
    .eq('id', true)
    .maybeSingle();
  if (error) {
    console.error('platform_fees read failed (code):', error.code ?? 'unknown');
    return null;
  }
  return parsePlatformFeeBps(data, kind);
}
