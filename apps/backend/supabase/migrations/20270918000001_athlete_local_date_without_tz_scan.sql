-- private.athlete_local_date looked its zone up in pg_timezone_names, which is
-- a set-returning function that reads the whole time-zone database from disk on
-- every call: 12-17 ms each on the local stack. The run-to-workout matcher
-- (20270901000001) calls it once per inserted run and again per candidate run,
-- so a 55-run insert spent 1.4 s in that trigger and timed out at the
-- authenticator's 8 s statement_timeout on CI (decisions § 2110).
--
-- `at time zone` resolves a name without the scan and raises 22023 for one it
-- does not know, which falls back to the UTC day exactly as a miss on
-- pg_timezone_names did. The two accept different sets only outside zone names
-- (`at time zone` also takes POSIX strings such as 'UTC+5'), and every value
-- this is called with is user_settings.prefs.time_zone, which
-- private.check_time_zone_pref already refuses unless pg_timezone_names lists
-- it, so no reachable input changes answer.

create or replace function private.athlete_local_date(p_time_zone text, p_at timestamptz)
returns date
language plpgsql
stable
set search_path = public, pg_catalog
as $$
begin
  if p_time_zone is null then
    return p_at::date;
  end if;
  return (p_at at time zone p_time_zone)::date;
exception when invalid_parameter_value then
  return p_at::date;
end;
$$;

revoke execute on function private.athlete_local_date(text, timestamptz) from public, anon, authenticated;
