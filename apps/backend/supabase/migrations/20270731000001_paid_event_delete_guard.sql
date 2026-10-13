-- An event that has moved money cannot be deleted by a client; it is cancelled
-- (decisions § R7PAID-1, club_events.md § Refunds & cancellation coupling).
--
-- `event_orders.event_id` and `fundraisers.event_id` cascade on `events`
-- delete (20261229_001, 20270213_001), and `payment_refunds` / `donations`
-- cascade from those. So an organiser pressing Delete on a paid class refunded
-- nobody and erased the ledger: every order, every refund row, and any
-- donation raised against the event, including the buyers whose money the
-- host was still holding.
--
-- guard_paid_event_delete is a BEFORE DELETE trigger on events that refuses a
-- client-role delete while the event carries any order or donation that moved
-- money -- every status but `failed` and `canceled`, which are checkouts that
-- never charged. That is deliberately wider than "money still held":
--
--   * `paid` stays `paid` after a class is delivered, so a held-money rule
--     would refuse the same events this one does; and
--   * a `refunded` / `refund_failed` order is still the platform's record of a
--     charge it was merchant of record for (disputes arrive weeks later, the
--     host's earnings and the buyer's export read it), so letting the delete
--     through once the refunds land would only move the erasure later.
--
-- The host's path is the cancel: events-cancel refunds every registrant of an
-- occurrence, a one-off event or a whole series, and a cancelled event drops
-- out of every upcoming list on its own. The ledger stays attached to the
-- event it describes.
--
-- The FKs keep ON DELETE CASCADE. Trusted callers pass the guard exactly as
-- they pass guard_paid_occurrence_cancel (20270723000003): the REST service
-- role, and direct SQL with no role claim from a privileged session user --
-- which here includes `supabase_auth_admin`, the role GoTrue's
-- admin.deleteUser runs the auth.users delete as. Account erasure therefore
-- still cascades clubs -> events -> orders exactly as before; whether a
-- payment ledger should outlive an erased account is the retention register's
-- question (docs/compliance/retention.md), not this trigger's. Changing the FK
-- to RESTRICT would have blocked that erasure outright, and SET NULL would make
-- `event_id` nullable on a table every money path keys on.
--
-- A club delete cascades to its events inside the caller's request, so a club
-- owner deleting a club that sold a class is refused by the same trigger.
--
-- Lock profile: one CREATE FUNCTION and one CREATE TRIGGER on events, which
-- takes SHARE ROW EXCLUSIVE on that table for the instant of the catalog
-- write. No scan, no rewrite (migration_locks.md).

create or replace function public.guard_paid_event_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin', 'supabase_auth_admin')) then
    return old;
  end if;

  if exists (
    select 1 from event_orders o
    where o.event_id = old.id
      and o.status not in ('failed', 'canceled')
  ) or exists (
    select 1 from donations d
    join fundraisers f on f.id = d.fundraiser_id
    where f.event_id = old.id
      and d.status not in ('failed', 'canceled')
  ) then
    raise exception 'paid_event_has_orders'
      using errcode = 'P0001',
            hint = 'An event that has taken payments keeps its records. Cancel it '
                   'through the events-cancel function instead, which refunds '
                   'its registrants.';
  end if;
  return old;
end;
$$;

create trigger trg_guard_paid_event_delete
  before delete on events
  for each row execute function public.guard_paid_event_delete();

revoke execute on function public.guard_paid_event_delete() from public, anon, authenticated;
