-- A paid order must name a real occurrence of its event (decisions § 1921).
--
-- events-checkout validated the event, its pricing, the cancellation list,
-- the series end and the sales window, but never that `instance_start` was
-- an instant the series actually produces. Pricing resolves to the series
-- default for any instant, the cancellation list holds only real occurrences,
-- and a sales window graded against a fabricated instant is simply open, so a
-- buyer could pay for a seat at 03:17 on a Wednesday of a Saturday class: an
-- order, a Stripe charge and (on the webhook) a `going` row for a session
-- that never happens, which no host roster shows and no occurrence cancel
-- refunds.
--
--   1. `event_occurrence_exists(event, instant)` — a public, service-role-only
--      door onto `private.is_event_occurrence` (20270807000001, the SQL port
--      of `expandInstances` the photo trigger already uses), so the Edge
--      Function can refuse BEFORE it opens a Checkout Session. `private` is
--      not an exposed PostgREST schema, so the private function cannot be
--      called by RPC directly. The wrapper restates nothing: it is one call,
--      so whatever the private body decides an occurrence is, this agrees.
--   2. `enforce_event_order_occurrence` — the same check on every write of an
--      order's (event, instance), so a future insert path, or a bug in the
--      function's ordering, cannot land an order the check would refuse. The
--      function check is the friendly 404; this is the floor.
--
-- Both are STRICT (p_allow_legacy => false): during the § 1918 transition
-- window the photo trigger still admits the UTC-clock instant an old build
-- mints, but no new money path does, so no order is ever opened on an
-- instant the wall-clock expansion does not produce. The remap moves
-- existing orders onto wall-clock instants, which the trigger accepts.
--
-- Lock profile: CREATE FUNCTION takes no table lock; CREATE TRIGGER takes
-- SHARE ROW EXCLUSIVE on event_orders for a catalogue change, no scan.
-- Existing rows are not re-checked (the trigger fires on writes only).

create or replace function public.event_occurrence_exists(p_event_id uuid, p_instance timestamptz)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.is_event_occurrence(p_event_id, p_instance, false);
$$;

comment on function public.event_occurrence_exists(uuid, timestamptz) is
  'Whether p_instance is a wall-clock occurrence of event p_event_id (private.is_event_occurrence, strict: never a UTC-clock-only instant). Service role only: events-checkout asks it before opening a Checkout Session.';

revoke execute on function public.event_occurrence_exists(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.event_occurrence_exists(uuid, timestamptz) to service_role;

create or replace function private.enforce_event_order_occurrence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_event_occurrence(new.event_id, new.instance_start, false) then
    raise exception 'event order instance_start is not an occurrence of its event'
      using errcode = 'check_violation',
            constraint = 'event_orders_instance_is_occurrence';
  end if;
  return new;
end;
$$;

revoke execute on function private.enforce_event_order_occurrence() from public, anon, authenticated;

-- Named to sort after `event_orders_status_lock`: BEFORE triggers fire in
-- name order, and a buyer's refused column write must keep meeting the lock
-- (insufficient_privilege) rather than this check.
create trigger event_orders_validate_occurrence
  before insert or update of event_id, instance_start on public.event_orders
  for each row execute function private.enforce_event_order_occurrence();
