/// The occurrence gate `events-checkout` runs before anything is reserved or
/// charged (decisions § 1921). Its own module so a deno test can drive it
/// against a fake client.
///
/// `instance_start` arrives from the client. Pricing resolves to the series
/// default for any instant and the sales window of a fabricated instant is
/// simply open, so without this a buyer could pay for a session the series
/// never produces. Whether it does is answered by the database
/// (`event_occurrence_exists` -> `private.is_event_occurrence`, the same port
/// of `expandInstances` the event-photo trigger asks), never re-derived here,
/// and `event_orders_validate_occurrence` refuses the order row regardless.
/// Both ask strictly: an instant only the pre-§ 1918 UTC clock produces is a
/// 404 here even while the transition window lets a photo land on it.

import type { DbClient } from '../_shared/database.ts';
import { isPastSeriesEnd } from './lib.ts';

export type OccurrenceRefusal =
  | { status: 404; error: 'instance_not_found' }
  | { status: 409; error: 'instance_cancelled' }
  | { status: 500; error: 'checkout_failed' };

/// null when the instant is a live occurrence that may be sold. A failed read
/// refuses (500) rather than selling: a seat must not be sold on a session
/// nobody could confirm exists, or on one that might have been called off.
export async function gateOccurrence(
  service: DbClient,
  eventId: string,
  instanceStart: string,
  recurrenceUntil: string | null,
): Promise<OccurrenceRefusal | null> {
  const { data: exists, error: existsErr } = await service.rpc('event_occurrence_exists', {
    p_event_id: eventId,
    p_instance: instanceStart,
  });
  if (existsErr) {
    console.error('occurrence check failed (code):', existsErr?.code ?? 'unknown');
    return { status: 500, error: 'checkout_failed' };
  }
  if (exists !== true) {
    return { status: 404, error: 'instance_not_found' };
  }

  const { data: exception, error: exceptionErr } = await service
    .from('event_exceptions')
    .select('event_id')
    .eq('event_id', eventId)
    .eq('instance_start', instanceStart)
    .maybeSingle();
  if (exceptionErr) {
    console.error('occurrence cancel read failed (code):', exceptionErr?.code ?? 'unknown');
    return { status: 500, error: 'checkout_failed' };
  }
  if (exception) {
    return { status: 409, error: 'instance_cancelled' };
  }
  if (isPastSeriesEnd(recurrenceUntil, Date.parse(instanceStart))) {
    return { status: 409, error: 'instance_cancelled' };
  }
  return null;
}
