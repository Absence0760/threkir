-- A rate-limit slot the server can give back, and only the server.
--
-- The three Anthropic handlers that throttle on `check_rate_limit`
-- (plate-photo, route-request, route-describe) take the slot BEFORE the model
-- call and never return it, so a provider outage, a refusal or an unusable
-- reply costs the runner one of a small hourly allowance (plate-photo is 20)
-- for nothing. The Coach-counter rail already refunds those cases
-- (`decrement_coach_usage`, 20261001_001); this is the same semantics for the
-- per-user route buckets.
--
-- ── Why a ticket, not a bare decrement ──
-- The handlers hold only the caller's JWT, never a service-role key, so any
-- refund RPC they can call the runner can call too, straight through
-- PostgREST. A `decrement(bucket)` guarded by `auth.uid() = p_user_id` would
-- therefore let a runner reset their own bucket after every SUCCESSFUL call and
-- spend without limit — the ceiling exists because Pro is a monthly price and
-- each call is an Opus (or vision) request on the operator's key.
--
-- `spend_rate_limit_slot` is `check_rate_limit` plus a fresh random ticket,
-- recorded on the window's row and returned only to the caller of that spend.
-- `refund_rate_limit_slot` gives a slot back only for a ticket still on the
-- row, and consumes it. The handler's ticket travels Lambda <-> PostgREST and
-- never reaches the browser, and `rate_limits` has RLS on with no policy at
-- all, so the runner cannot read it off the row either. What a runner CAN do
-- is spend directly and refund their own ticket, which is net zero.
--
-- The ticket list is held to the newest 32 per window row inside the
-- function: a runner calling the spend RPC directly with a huge `p_max` grows
-- only their own row, and only to that bound. A handler ticket evicted by such
-- a flood is simply not refunded, which costs only the flooder. Bounded in the
-- function rather than by a CHECK because a validating constraint on this
-- table is a full scan under a writer-blocking lock
-- (docs/backend/migration_locks.md); the column has no other writer.
--
-- ── Online safety ──
-- ADD COLUMN with a constant default is a catalogue-only change on PG 11+
-- (no rewrite, no scan); it takes ACCESS EXCLUSIVE for that instant only.
-- `check_rate_limit` is untouched, so its other callers (the route engines,
-- the Edge Functions) and its return shape do not move.

alter table public.rate_limits
  add column refundable_spends uuid[] not null default '{}';

comment on column public.rate_limits.refundable_spends is
  'Unconsumed refund tickets for slots taken in this window through '
  'spend_rate_limit_slot (newest 32). Written only by that function and '
  'refund_rate_limit_slot; RLS has no policy, so no client reads it.';

create or replace function public.spend_rate_limit_slot(
  p_user_id uuid,
  p_bucket text,
  p_max integer,
  p_window_seconds integer
)
returns table (allowed boolean, retry_after_seconds integer, spend_id uuid)
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
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_count integer;
  v_spend uuid;
begin
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'spend_rate_limit_slot: not authorized' using errcode = '42501';
  end if;

  if p_max <= 0 or p_window_seconds <= 0 then
    raise exception 'spend_rate_limit_slot: max and window must be positive';
  end if;

  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );
  v_window_end := v_window_start + make_interval(secs => p_window_seconds);

  insert into rate_limits (user_id, bucket, window_start, count)
    values (p_user_id, p_bucket, v_window_start, 1)
    on conflict (user_id, bucket, window_start) do update
      set count = rate_limits.count + 1
    returning rate_limits.count into v_count;

  if v_count > p_max then
    return query
      select false, greatest(1, ceil(extract(epoch from v_window_end - now()))::integer), null::uuid;
    return;
  end if;

  v_spend := gen_random_uuid();
  update rate_limits r
     set refundable_spends = (array_append(r.refundable_spends, v_spend))[
           greatest(1, cardinality(r.refundable_spends) + 1 - 31):
         ]
   where r.user_id = p_user_id
     and r.bucket = p_bucket
     and r.window_start = v_window_start;

  return query select true, 0, v_spend;
end;
$$;

create or replace function public.refund_rate_limit_slot(
  p_user_id uuid,
  p_bucket text,
  p_spend_id uuid
)
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
begin
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'refund_rate_limit_slot: not authorized' using errcode = '42501';
  end if;

  -- Fail-soft like decrement_coach_usage: an unknown, already-consumed or
  -- evicted ticket is a no-op, because the caller is already on its unhappy
  -- path and a raise would only mask the original error.
  update rate_limits r
     set count = greatest(0, r.count - 1),
         refundable_spends = array_remove(r.refundable_spends, p_spend_id)
   where r.user_id = p_user_id
     and r.bucket = p_bucket
     and p_spend_id = any (r.refundable_spends);

  return found;
end;
$$;

revoke execute on function public.spend_rate_limit_slot(uuid, text, integer, integer) from public, anon;
grant  execute on function public.spend_rate_limit_slot(uuid, text, integer, integer) to authenticated, service_role;
revoke execute on function public.refund_rate_limit_slot(uuid, text, uuid) from public, anon;
grant  execute on function public.refund_rate_limit_slot(uuid, text, uuid) to authenticated, service_role;

comment on function public.spend_rate_limit_slot(uuid, text, integer, integer) is
  'check_rate_limit plus a refund ticket (spend_id) for an allowed spend. '
  'The billed handler keeps the ticket server-side and hands it to '
  'refund_rate_limit_slot when the provider call fails.';
comment on function public.refund_rate_limit_slot(uuid, text, uuid) is
  'Gives back one slot for an unconsumed ticket from spend_rate_limit_slot '
  'and consumes the ticket. A bare per-bucket decrement would let the caller '
  'reset their own ceiling after a successful call.';
