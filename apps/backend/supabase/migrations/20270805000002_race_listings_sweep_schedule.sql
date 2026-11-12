-- Schedule the RunSignUp race-calendar sweep (decisions § 1902).
--
-- Nothing called `race-listings-sync`, so `race_listings` never received a
-- RunSignUp race. The `race-listings-sweep` Edge Function reads one state over
-- one 14-day window per run, the slot chosen from the clock, and this job runs
-- it every five minutes: 51 jurisdictions x 6 windows is a full pass of the
-- next 84 days every 25.5 hours, one request to RunSignUp per run.
--
-- Fails closed on configuration, the `invoke_event_refund_sweep` shape: with
-- either Vault secret missing (`race_listings_sweep_url`, `cron_secret`) the
-- job returns NULL and calls nothing, so a deployment that has not been armed
-- does no work rather than an unauthenticated POST. Arming is the operator
-- step recorded in docs/ops/deployment.md.
--
-- A new function and a new cron row: no lock on anything populated
-- (docs/backend/migration_locks.md).

create or replace function public.invoke_race_listings_sweep()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'race_listings_sweep_url';
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  return net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secret,
      'Content-Type', 'application/json'
    ),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function public.invoke_race_listings_sweep() from public, anon, authenticated;
grant execute on function public.invoke_race_listings_sweep() to service_role;

comment on function public.invoke_race_listings_sweep() is
  'Five-minute pg_cron entry for the RunSignUp race-calendar sweep (decisions '
  '1902). POSTs to race-listings-sweep with the cron bearer, only when the Vault '
  'secrets race_listings_sweep_url and cron_secret both exist. Service-role grant '
  'lets an operator run it by hand.';

select cron.schedule(
  'race-listings-sweep',
  '*/5 * * * *',
  $$select public.invoke_race_listings_sweep()$$
);
