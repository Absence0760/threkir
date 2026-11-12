-- Weak-GPS live pings (issue #1300 BUG-007, decisions § 2357).
--
-- The live link published only fixes that cleared the recorder's 20 m map
-- gate. A budget phone in a pocket can state 20-50 m for a whole walk: the
-- distance estimator keeps those fixes, so distance advanced, but the gated
-- position never did, nothing was published and the spectator sat on
-- "Connecting" for the entire run.
--
-- The recorder now publishes the estimator's latest kept fix while the gated
-- position is stale, and flags it `weak_gps`. Every spectator surface draws a
-- weak ping as an approximate position (a halo, no join into the trace line),
-- the same way the saved run keeps those fixes off its line.
--
-- `weak_gps` is a separate flag from `coarse`. `coarse` is the privacy-zone
-- last-seen carve-out (20270121_001), whose trigger DELETES every earlier
-- coarse row for the run before keeping the newest; folding weak fixes into it
-- would let one in-zone ping wipe a whole weak stretch.
--
-- Locks: ADD COLUMN ... NOT NULL DEFAULT false is catalogue-only on PG 11+.
-- safety_live_pings changes its return type, so it is dropped and re-created
-- (catalogue-only) and its grants re-issued exactly as 20270821000001 left
-- them.

alter table public.live_run_pings
  add column if not exists weak_gps boolean not null default false;

comment on column public.live_run_pings.weak_gps is
  'A fix the recorder kept for distance but not for the line (stated accuracy '
  'worse than its map gate). Render as an approximate position; never join it '
  'into the trace. Distinct from `coarse` (decisions § 2357).';

drop function if exists public.safety_live_pings(uuid, uuid, timestamptz);

create function public.safety_live_pings(
  p_run_id uuid,
  p_token uuid,
  p_since timestamptz default null
)
returns table (
  lat double precision,
  lng double precision,
  distance_m double precision,
  elapsed_s integer,
  at timestamptz,
  coarse boolean,
  weak_gps boolean
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.safety_link_admits(p_run_id, p_token) then
    return;
  end if;
  if p_since is null then
    return query
      select p.lat, p.lng, p.distance_m::double precision, p.elapsed_s, p.at,
             p.coarse, p.weak_gps
        from live_run_pings p
       where p.run_id = p_run_id
       order by p.at desc
       limit 1000;
  else
    return query
      select p.lat, p.lng, p.distance_m::double precision, p.elapsed_s, p.at,
             p.coarse, p.weak_gps
        from live_run_pings p
       where p.run_id = p_run_id
         and p.at > p_since
       order by p.at asc
       limit 1000;
  end if;
end;
$$;

revoke execute on function public.safety_live_pings(uuid, uuid, timestamptz) from public;
grant execute on function public.safety_live_pings(uuid, uuid, timestamptz)
  to anon, authenticated, service_role;

comment on function public.safety_live_pings(uuid, uuid, timestamptz) is
  'Privacy-clipped live pings for a safety contact''s escalation link '
  '(decisions § 1964), carrying the weak_gps flag (§ 2357). Empty when the '
  'token does not admit the run.';
