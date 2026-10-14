-- Pins migration 20270805000002 (decisions § 1902): pg_cron runs the RunSignUp
-- race-calendar sweep every five minutes through invoke_race_listings_sweep,
-- and the invoker fails closed — no pg_net request — until BOTH Vault secrets
-- (`race_listings_sweep_url`, `cron_secret`) exist.

begin;
select plan(10);

delete from vault.secrets where name in ('race_listings_sweep_url', 'cron_secret');

select is(
  (select count(*)::int from cron.job where jobname = 'race-listings-sweep'),
  1, 'exactly one race-listings-sweep cron job is registered');

select is(
  (select schedule from cron.job where jobname = 'race-listings-sweep'),
  '*/5 * * * *', 'pg_cron runs the sweep every five minutes');

select is(
  (select command from cron.job where jobname = 'race-listings-sweep'),
  'select public.invoke_race_listings_sweep()',
  'the job calls the fail-closed invoker, not the Edge Function directly');

select ok(
  (select active from cron.job where jobname = 'race-listings-sweep'),
  'the job is active');

select is(public.invoke_race_listings_sweep(), null,
  'nothing is sent while both Vault secrets are absent');

do $$ begin perform vault.create_secret(repeat('c', 40), 'cron_secret'); end $$;
select is(public.invoke_race_listings_sweep(), null,
  'the bearer alone is not enough: the sweep URL is missing');

delete from vault.secrets where name = 'cron_secret';
do $$ begin
  perform vault.create_secret('https://example.invalid/functions/v1/race-listings-sweep',
                              'race_listings_sweep_url');
end $$;
select is(public.invoke_race_listings_sweep(), null,
  'the URL alone is not enough: the bearer is missing');

do $$ begin perform vault.create_secret(repeat('c', 40), 'cron_secret'); end $$;
select isnt(public.invoke_race_listings_sweep(), null,
  'configured: one pg_net request is queued');

select ok(
  not has_function_privilege('anon', 'public.invoke_race_listings_sweep()', 'execute'),
  'anon cannot fire the sweep');

select ok(
  not has_function_privilege('authenticated', 'public.invoke_race_listings_sweep()', 'execute'),
  'a signed-in client cannot fire the sweep');

select * from finish();
rollback;
