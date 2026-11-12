-- The database half of the release's prod config sync (migration
-- 20271128002430, issue #1350, decisions § 2430):
--   * private.apply_feature_flag creates, updates, or leaves a flag alone,
--     and an unchanged flag writes nothing;
--   * private.arm_cron_url creates or updates the <fn>_url Vault entry by
--     name, refuses without cron_secret, a function with no invoker, and a
--     URL that is not that function's endpoint;
--   * private.cron_invoke_outcome returns a status code and never waits
--     unbounded;
--   * private.ops_task_runs runs a task once and refuses a changed file, in
--     the function and in the trigger;
-- and none of it reaches a client role.

begin;

select plan(37);

-- ── Feature flags ──

delete from private.feature_flags where name = 'pcs_test_flag';

select is(private.apply_feature_flag('pcs_test_flag', true), 'created', 'an absent flag is created');
select is((select enabled from private.feature_flags where name = 'pcs_test_flag'), true, 'created with the committed value');

update private.feature_flags set updated_at = '2026-01-01T00:00:00Z' where name = 'pcs_test_flag';
select is(private.apply_feature_flag('pcs_test_flag', true), 'unchanged', 'the same value again is unchanged');
select is((select updated_at from private.feature_flags where name = 'pcs_test_flag'),
          '2026-01-01T00:00:00Z'::timestamptz, 'an unchanged flag writes nothing');
select is(private.apply_feature_flag('pcs_test_flag', true), 'unchanged', 'and stays unchanged on every later run');

select is(private.apply_feature_flag('pcs_test_flag', false), 'updated', 'a different value updates');
select is((select enabled from private.feature_flags where name = 'pcs_test_flag'), false, 'the flag is now off');
select isnt((select updated_at from private.feature_flags where name = 'pcs_test_flag'),
            '2026-01-01T00:00:00Z'::timestamptz, 'an update stamps updated_at');

select throws_ok($$select private.apply_feature_flag('Bad-Name', true)$$, '22023', null, 'a malformed name is refused');
select throws_ok($$select private.apply_feature_flag('pcs_test_flag', null)$$, '22023', null, 'a null value is refused');

-- ── Cron URL entries ──

select throws_ok(
  $$select private.arm_cron_url('race_listings_sweep', 'https://abcdefghijklmnopqrst.supabase.co/functions/v1/race-listings-sweep')$$,
  '55000', null, 'arming refuses while the cron_secret entry is missing');

select vault.create_secret('pcs-test-bearer', 'cron_secret');

select throws_ok(
  $$select private.arm_cron_url('no_such_sweep', 'https://abcdefghijklmnopqrst.supabase.co/functions/v1/no-such-sweep')$$,
  'P0002', null, 'a function with no public.invoke_<fn>() is refused');
select throws_ok(
  $$select private.arm_cron_url('race_listings_sweep', 'https://evil.example.com/functions/v1/race-listings-sweep')$$,
  '22023', null, 'a URL off a Supabase project is refused');
select throws_ok(
  $$select private.arm_cron_url('race_listings_sweep', 'https://abcdefghijklmnopqrst.supabase.co/functions/v1/club-verification-recheck')$$,
  '22023', null, 'another function''s URL is refused');
select throws_ok(
  $$select private.arm_cron_url('race_listings_sweep', 'http://abcdefghijklmnopqrst.supabase.co/functions/v1/race-listings-sweep')$$,
  '22023', null, 'a plain-http URL is refused');

select is(
  private.arm_cron_url('race_listings_sweep', 'https://abcdefghijklmnopqrst.supabase.co/functions/v1/race-listings-sweep'),
  'created', 'an absent URL entry is created');
select is(
  (select decrypted_secret from vault.decrypted_secrets where name = 'race_listings_sweep_url'),
  'https://abcdefghijklmnopqrst.supabase.co/functions/v1/race-listings-sweep',
  'the entry holds the URL under the name the invoker reads');
select is(
  private.arm_cron_url('race_listings_sweep', 'https://abcdefghijklmnopqrst.supabase.co/functions/v1/race-listings-sweep'),
  'unchanged', 'the same URL again is unchanged');
select is(
  private.arm_cron_url('race_listings_sweep', 'https://tsrqponmlkjihgfedcba.supabase.co/functions/v1/race-listings-sweep'),
  'updated', 'a different project''s URL updates the entry in place');
select is(
  (select count(*)::int from vault.secrets where name = 'race_listings_sweep_url'), 1,
  'updated by name, never duplicated');
select is(
  (select decrypted_secret from vault.decrypted_secrets where name = 'race_listings_sweep_url'),
  'https://tsrqponmlkjihgfedcba.supabase.co/functions/v1/race-listings-sweep',
  'the entry holds the new URL');
select is(
  private.arm_cron_url('event_refund_sweep', 'https://abcdefghijklmnopqrst.supabase.co/functions/v1/event-refund-sweep'),
  'created', 'the refund sweep is supported, though the committed file leaves it undeclared');
select isnt(public.invoke_race_listings_sweep(), null, 'an armed invoker queues a request');

-- ── The invoke outcome ──

select is(private.cron_invoke_outcome(null, 1), 'not sent', 'no request id is not sent');
select is(private.cron_invoke_outcome(-424242, 1), 'pending', 'a response that never lands is pending after the bound');
insert into net._http_response (id, status_code, content, timed_out) values (-424243, 200, '{"secret":"body"}', false);
select is(private.cron_invoke_outcome(-424243, 1), '200', 'a landed response is its status code, never its body');
insert into net._http_response (id, status_code, timed_out, error_msg) values (-424244, null, true, 'Timeout');
select is(private.cron_invoke_outcome(-424244, 1), 'timed out', 'a timed-out request says so');

-- ── Ops task ledger ──

select throws_ok($$select private.set_ops_task_result('{"n":1}')$$, '55000', null,
  'no result is recorded outside a running task');
select is(private.begin_ops_task('20271128000001_pcs_example', repeat('a', 64)), 'run', 'a new task runs');
select lives_ok($$select private.set_ops_task_result('{"updated":3}')$$, 'the running task records its result');
select is((select result from private.ops_task_runs where name = '20271128000001_pcs_example'),
          '{"updated":3}'::jsonb, 'the ledger holds the result');
select is(private.begin_ops_task('20271128000001_pcs_example', repeat('a', 64)), 'already ran',
  'the same file never runs twice');
select throws_ok($$select private.begin_ops_task('20271128000001_pcs_example', repeat('b', 64))$$, '55000', null,
  'a task whose file changed after it ran is refused');
select throws_ok($$update private.ops_task_runs set sha256 = repeat('c', 64) where name = '20271128000001_pcs_example'$$,
  '55000', null, 'a recorded sha256 is never rewritten');

-- ── No client role ──

select ok(
  not has_function_privilege('authenticated', 'private.apply_feature_flag(text, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'private.arm_cron_url(text, text)', 'execute')
  and not has_function_privilege('authenticated', 'private.cron_invoke_outcome(bigint, integer)', 'execute')
  and not has_function_privilege('authenticated', 'private.begin_ops_task(text, text)', 'execute')
  and not has_function_privilege('authenticated', 'private.set_ops_task_result(jsonb)', 'execute')
  and not has_function_privilege('anon', 'private.apply_feature_flag(text, boolean)', 'execute')
  and not has_function_privilege('anon', 'private.arm_cron_url(text, text)', 'execute'),
  'no client role can call the sync functions');
select ok(
  has_function_privilege('service_role', 'private.apply_feature_flag(text, boolean)', 'execute')
  and has_function_privilege('service_role', 'private.arm_cron_url(text, text)', 'execute')
  and has_function_privilege('service_role', 'private.cron_invoke_outcome(bigint, integer)', 'execute')
  and has_function_privilege('service_role', 'private.begin_ops_task(text, text)', 'execute')
  and has_function_privilege('service_role', 'private.set_ops_task_result(jsonb)', 'execute'),
  'the sync''s service_role can');
select ok(
  not has_table_privilege('authenticated', 'private.ops_task_runs', 'select')
  and not has_table_privilege('anon', 'private.ops_task_runs', 'select')
  and has_table_privilege('service_role', 'private.ops_task_runs', 'select'),
  'the ledger is service_role only');

select * from finish();
rollback;
