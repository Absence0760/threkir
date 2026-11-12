-- The AI Coach daily cap can be refunded only by the server, through a ticket.
--
-- `decrement_coach_usage` (20261001_001, rolling body 20261002_001) was the
-- refund half of `increment_coach_usage`: the Coach handler, the plan
-- assistant and AI plan edits call it when the billed model call yields
-- nothing. Its only guard was caller-is-self, and it is granted to
-- `authenticated`, because those handlers hold the caller's JWT and never a
-- service-role key. So a signed-in runner could call it straight through
-- PostgREST after every SUCCESSFUL message and keep their counter at zero:
-- the daily cap is the bound on Anthropic spend per account, and it did not
-- bind. Decisions § 1990 closed the same hole for the per-user route buckets
-- with a server-held ticket; this is that design for the Coach counter.
--
-- `spend_coach_usage_slot` is `increment_coach_usage` plus a fresh random
-- ticket, returned only to the caller of that spend. `refund_coach_usage_slot`
-- gives back one message only for a ticket that is still held, consumes it,
-- and decrements the day bucket the spend landed in (so a spend at 23:59 UTC
-- refunded at 00:01 gives back the right day). The ticket travels Lambda <->
-- PostgREST and never reaches the browser. What a runner CAN do is spend
-- directly and refund their own ticket, which is net zero.
--
-- ── Where the tickets live ──
-- Not on the `user_coach_usage` row. The owner reads that row under its own
-- SELECT policy, and both Art 20 export rails select it with `*`
-- (export-data/backup_spec.ts, job_worker dataexport), so a ticket column
-- there would be handed to the runner twice — and a ticket read off the row
-- is a refund of a call that succeeded. Instead a sidecar in `private`, one
-- row per usage row: PostgREST never exposes the schema, no client role holds
-- a grant, and the composite FK cascades it away with its usage row, so the
-- hourly `cleanup-stale-user-coach-usage` sweep and account deletion retire
-- the tickets with nothing new to schedule.
--
-- The list is held to the newest 32 per usage row inside the function, as
-- `rate_limits.refundable_spends` is: a runner calling the spend RPC in a loop
-- grows only their own row, to that bound, and every such call is a message
-- off their own allowance. A handler ticket evicted by such a flood is simply
-- not refunded, which costs only the flooder.
--
-- ── `increment_coach_usage` stays ──
-- It is the meter `spend_coach_usage_slot` calls, so the guard, the bump and
-- the rolling-24h sum stay in one body, and it keeps the Lambda that is live
-- when this migration applies enforcing the cap until the web release that
-- calls the spend RPC replaces it. Calling it directly only spends the
-- caller's own allowance.
--
-- ── `decrement_coach_usage` is dropped ──
-- A bare per-user decrement is the hole; there is no caller it is safe to
-- leave it for. The Lambda live while this applies refunds through it, fails
-- with "function not found", logs and keeps its original answer (the refund
-- is fail-soft), so the cost in the window before the web release is a slot
-- not given back on a failed call, never an extra one granted.
--
-- Locks: CREATE TABLE and the functions are catalogue-only; the FK takes SHARE
-- ROW EXCLUSIVE on user_coach_usage for the instant of the CREATE and scans
-- nothing (the new table is empty). DROP FUNCTION is catalogue-only.

create table private.coach_usage_refund_tickets (
  user_id    uuid not null,
  usage_date date not null,
  tickets    uuid[] not null default '{}',
  primary key (user_id, usage_date),
  foreign key (user_id, usage_date)
    references public.user_coach_usage (user_id, usage_date) on delete cascade
);

comment on table private.coach_usage_refund_tickets is
  'Unconsumed refund tickets (newest 32) for Coach messages spent through '
  'spend_coach_usage_slot, one row per user_coach_usage row and cascaded with '
  'it. Written only by that function and refund_coach_usage_slot.';

alter table private.coach_usage_refund_tickets enable row level security;
revoke all on table private.coach_usage_refund_tickets
  from public, anon, authenticated, service_role;

create or replace function public.spend_coach_usage_slot(p_user_id uuid)
returns table (used integer, spend_id uuid)
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
  v_used integer;
  v_spend uuid := gen_random_uuid();
begin
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'spend_coach_usage_slot: not authorized' using errcode = '42501';
  end if;

  -- Bumps today's bucket (current_date is fixed for the transaction, so the
  -- ticket below lands on the same row) and returns the rolling-24h count.
  v_used := increment_coach_usage(p_user_id);

  insert into private.coach_usage_refund_tickets as t (user_id, usage_date, tickets)
    values (p_user_id, current_date, array[v_spend])
    on conflict (user_id, usage_date) do update
      set tickets = (array_append(t.tickets, v_spend))[
            greatest(1, cardinality(t.tickets) + 1 - 31):
          ];

  return query select v_used, v_spend;
end;
$$;

create or replace function public.refund_coach_usage_slot(p_user_id uuid, p_spend_id uuid)
returns boolean
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
  v_usage_date date;
begin
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'refund_coach_usage_slot: not authorized' using errcode = '42501';
  end if;

  -- Fail-soft like the route-bucket refund: an unknown, consumed or evicted
  -- ticket is a no-op, because the caller is already on its unhappy path and
  -- a raise would only mask the original error. The row lock taken here makes
  -- a concurrent second refund of the same ticket re-read it and find nothing.
  update private.coach_usage_refund_tickets t
     set tickets = array_remove(t.tickets, p_spend_id)
   where t.user_id = p_user_id
     and p_spend_id = any (t.tickets)
  returning t.usage_date into v_usage_date;

  if not found then
    return false;
  end if;

  update user_coach_usage
     set message_count = greatest(0, message_count - 1)
   where user_id = p_user_id
     and usage_date = v_usage_date;

  return true;
end;
$$;

revoke execute on function public.spend_coach_usage_slot(uuid) from public, anon;
grant  execute on function public.spend_coach_usage_slot(uuid) to authenticated, service_role;
revoke execute on function public.refund_coach_usage_slot(uuid, uuid) from public, anon;
grant  execute on function public.refund_coach_usage_slot(uuid, uuid) to authenticated, service_role;

comment on function public.spend_coach_usage_slot(uuid) is
  'increment_coach_usage plus a refund ticket (spend_id). The billed handler '
  'keeps the ticket server-side and hands it to refund_coach_usage_slot when '
  'the model call yields nothing.';
comment on function public.refund_coach_usage_slot(uuid, uuid) is
  'Gives back one Coach message for an unconsumed ticket from '
  'spend_coach_usage_slot and consumes the ticket. Replaces '
  'decrement_coach_usage, which let a runner reset their own daily cap.';

drop function public.decrement_coach_usage(uuid);
