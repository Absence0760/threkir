-- M8: a host cancelling a paid occurrence refunds every registrant
-- (instructor_business.md § M8, club_events.md § Refunds, decisions § 1818).
--
-- Before this, calling off an occurrence was a bare client insert into
-- event_exceptions (20261019_001). On a priced class that cancelled the class
-- and refunded nobody: the buyers' money stayed with the host until someone
-- refunded each charge from the Stripe dashboard -- whose refund dialog
-- reverses neither the destination transfer nor the application fee unless
-- the operator ticks both, so the platform paid for every such refund out of
-- its own balance (decisions § 769).
--
-- The refunds themselves are Stripe calls and live in the events-cancel Edge
-- Function (`scope: 'occurrence'`), built through the same buildRefundParams
-- the buyer path uses. This migration supplies the two database halves:
--
--   * can_cancel_event_occurrence(event_id) -- the organiser predicate the
--     event_exceptions insert policy evaluates, askable by the caller. The EF
--     inserts the exception as the service role (so the guard below lets it
--     through) and must ask this first, or it would be a privilege escalation:
--     anyone signed in could cancel anyone's class.
--
--   * guard_paid_occurrence_cancel -- a BEFORE INSERT trigger on
--     event_exceptions that refuses a client-role insert over an occurrence
--     that still holds an order in a money-bearing status. Without it the web
--     routing was the only thing sending paid cancels through the EF, and any
--     other caller (an older bundle, a direct PostgREST call) could call off a
--     paid class with every buyer's money still held. The set of statuses is
--     the EF's OCCURRENCE_CANCEL_STATUSES; free events have no orders and are
--     untouched. Reinstating (DELETE) is not guarded: putting a cancelled class
--     back moves no money.
--
-- No column is added. The order-level state a retry needs already exists:
-- `status` (the webhook's, the sole writer) says whether money is still held,
-- and `refund_initiated_at` says a refund was created and is in flight. A
-- cancelled occurrence with an order still `paid`/`partially_refunded` and no
-- `refund_initiated_at` is exactly "a refund we still owe", which is what the
-- host's event page reads to offer a retry.
--
-- Lock profile: two CREATE FUNCTIONs and one CREATE TRIGGER on
-- event_exceptions, which takes SHARE ROW EXCLUSIVE on that table for the
-- instant of the catalog write. No scan, no rewrite (migration_locks.md).

create or replace function public.can_cancel_event_occurrence(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from events e
    where e.id = p_event_id
      and private.is_event_organiser(e.club_id)
  );
$$;

comment on function public.can_cancel_event_occurrence(uuid) is
  'Whether the caller may call off an occurrence of this event: the same '
  'organiser predicate as the event_exceptions insert policy. Asked by the '
  'events-cancel EF before it cancels a paid occurrence as the service role.';

revoke execute on function public.can_cancel_event_occurrence(uuid) from public, anon;
grant execute on function public.can_cancel_event_occurrence(uuid) to authenticated, service_role;

create or replace function public.guard_paid_occurrence_cancel()
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
  -- The same trusted-caller test as lock_event_order_status: the REST service
  -- role (the events-cancel EF, which refunds in the same request), or genuine
  -- direct SQL (migrations, seed, an operator) with no role claim and a
  -- privileged session_user. PostgREST authenticates every end-user request as
  -- `authenticator`, so no client can present session_user = postgres.
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;

  if exists (
    select 1 from event_orders o
    where o.event_id = new.event_id
      and o.instance_start = new.instance_start
      and o.status in ('pending', 'paid', 'partially_refunded')
  ) then
    raise exception 'paid_occurrence_requires_refund'
      using errcode = 'P0001',
            hint = 'Call off a paid occurrence through the events-cancel function '
                   '(scope occurrence), which refunds its registrants.';
  end if;
  return new;
end;
$$;

create trigger trg_guard_paid_occurrence_cancel
  before insert on event_exceptions
  for each row execute function public.guard_paid_occurrence_cancel();

-- Trigger firing runs with the function owner's rights; no role needs to call
-- it directly.
revoke execute on function public.guard_paid_occurrence_cancel() from public, anon, authenticated;
