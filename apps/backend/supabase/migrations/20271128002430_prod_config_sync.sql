-- Production config as code (issue #1350, decisions § 2430): the database half
-- of the release's "Sync production state" stages that apply
-- apps/backend/ops/prod_config.json and run apps/backend/ops/tasks/*.sql.
--
--   * private.apply_feature_flag   - upserts one private.feature_flags row,
--     reporting created / updated / unchanged. service_role holds no grant on
--     the table itself (20270802000001), so the sync writes through this.
--   * private.arm_cron_url         - creates or updates the `<fn>_url` Vault
--     entry an invoke_<fn>() reads, by name. Refuses a function with no
--     public.invoke_<fn>(), a URL that is not this project's Edge Function URL,
--     and a project with no `cron_secret` entry (checked by name, never read).
--   * private.cron_invoke_outcome  - waits, bounded, for pg_net's response to
--     one request and returns its status code only, never a body.
--   * private.ops_task_runs        - the one-off task ledger. A task runs once;
--     private.begin_ops_task refuses a task whose file changed after it ran,
--     and a trigger refuses rewriting a recorded sha256.
--
-- Every function is service_role only.
--
-- Locks (docs/backend/migration_locks.md): one new table, its trigger, and new
-- functions. Nothing existing is altered.

create or replace function private.apply_feature_flag(p_name text, p_enabled boolean)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_current boolean;
begin
  if p_name is null or p_name !~ '^[a-z][a-z0-9_]*$' then
    raise exception 'apply_feature_flag: % is not a flag name', p_name using errcode = '22023';
  end if;
  if p_enabled is null then
    raise exception 'apply_feature_flag: % needs an enabled value', p_name using errcode = '22023';
  end if;

  select f.enabled into v_current from private.feature_flags f where f.name = p_name for update;
  if not found then
    insert into private.feature_flags (name, enabled, updated_at) values (p_name, p_enabled, now());
    return 'created';
  end if;
  if v_current is not distinct from p_enabled then
    return 'unchanged';
  end if;
  update private.feature_flags set enabled = p_enabled, updated_at = now() where name = p_name;
  return 'updated';
end;
$$;

comment on function private.apply_feature_flag(text, boolean) is
  'Sets one private.feature_flags row to the committed value and reports created / updated / unchanged; '
  'an unchanged flag writes nothing. Service role only; the release''s prod config sync calls it '
  '(decisions § 2430).';

revoke execute on function private.apply_feature_flag(text, boolean) from public, anon, authenticated;
grant execute on function private.apply_feature_flag(text, boolean) to service_role;

create or replace function private.arm_cron_url(p_function text, p_url text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_id uuid;
  v_current text;
begin
  if p_function is null or p_function !~ '^[a-z][a-z0-9_]*$' then
    raise exception 'arm_cron_url: % is not a function name', p_function using errcode = '22023';
  end if;
  if to_regprocedure(format('public.invoke_%s()', p_function)) is null then
    raise exception 'arm_cron_url: no public.invoke_%() reads a Vault URL entry', p_function using errcode = 'P0002';
  end if;
  -- The URL is the project's own function endpoint and nothing else: the
  -- invoker sends the cron bearer to whatever this entry says.
  if p_url is null
     or p_url !~ '^https://[a-z0-9]{20}\.supabase\.co/functions/v1/[a-z0-9]+(-[a-z0-9]+)*$'
     or substring(p_url from '/functions/v1/(.*)$') <> replace(p_function, '_', '-') then
    raise exception 'arm_cron_url: the URL for % is not its Edge Function URL on a Supabase project', p_function
      using errcode = '22023';
  end if;
  if not exists (select 1 from vault.secrets s where s.name = 'cron_secret') then
    raise exception 'arm_cron_url: the Vault entry cron_secret does not exist; set it before arming %', p_function
      using errcode = '55000';
  end if;

  v_name := p_function || '_url';
  select d.id, d.decrypted_secret into v_id, v_current from vault.decrypted_secrets d where d.name = v_name;
  if v_id is null then
    perform vault.create_secret(p_url, v_name, format('Endpoint public.invoke_%s() posts to (decisions § 2430).', p_function));
    return 'created';
  end if;
  if v_current is not distinct from p_url then
    return 'unchanged';
  end if;
  perform vault.update_secret(v_id, p_url);
  return 'updated';
end;
$$;

comment on function private.arm_cron_url(text, text) is
  'Creates or updates the <fn>_url Vault entry public.invoke_<fn>() reads, by name, and reports created / '
  'updated / unchanged. Refuses a function with no invoker, a URL that is not its Edge Function URL, and a '
  'project with no cron_secret entry (checked by name). Service role only (decisions § 2430).';

revoke execute on function private.arm_cron_url(text, text) from public, anon, authenticated;
grant execute on function private.arm_cron_url(text, text) to service_role;

-- pg_net sends a request only after the transaction that queued it commits,
-- so this runs in a later one. Under read committed each poll sees the
-- worker's newly committed row.
create or replace function private.cron_invoke_outcome(p_request_id bigint, p_timeout_seconds integer default 30)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_deadline timestamptz := clock_timestamp() + make_interval(secs => least(greatest(p_timeout_seconds, 1), 120));
  v_status integer;
  v_timed_out boolean;
  v_error boolean;
begin
  if p_request_id is null then
    return 'not sent';
  end if;
  loop
    select r.status_code, r.timed_out, r.error_msg is not null
      into v_status, v_timed_out, v_error
      from net._http_response r
     where r.id = p_request_id;
    if found then
      if v_timed_out then
        return 'timed out';
      end if;
      if v_status is null then
        return case when v_error then 'error' else 'no status' end;
      end if;
      return v_status::text;
    end if;
    if clock_timestamp() >= v_deadline then
      return 'pending';
    end if;
    perform pg_sleep(0.5);
  end loop;
end;
$$;

comment on function private.cron_invoke_outcome(bigint, integer) is
  'Waits up to p_timeout_seconds (at most 120) for pg_net''s response to one request and returns its status '
  'code, or timed out / error / no status / pending / not sent. Never returns a body. Service role only '
  '(decisions § 2430).';

revoke execute on function private.cron_invoke_outcome(bigint, integer) from public, anon, authenticated;
grant execute on function private.cron_invoke_outcome(bigint, integer) to service_role;

create table private.ops_task_runs (
  name    text primary key check (name ~ '^[0-9]{14}_[a-z0-9]+(_[a-z0-9]+)*$'),
  sha256  text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  ran_at  timestamptz not null default now(),
  result  jsonb not null default '{}'::jsonb check (jsonb_typeof(result) = 'object')
);

comment on table private.ops_task_runs is
  'One row per one-off operator task (apps/backend/ops/tasks/<timestamp>_<name>.sql) the release has run, '
  'with the sha256 of the file it ran. A task runs once and is never edited after (decisions § 2430).';

alter table private.ops_task_runs enable row level security;
revoke all on table private.ops_task_runs from public, anon, authenticated;
grant select, insert, update on table private.ops_task_runs to service_role;

create or replace function private.ops_task_runs_keep_sha()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.name is distinct from old.name or new.sha256 is distinct from old.sha256 then
    raise exception 'ops_task_runs: % ran as %; a task is never edited after it runs, add a new one',
      old.name, old.sha256 using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke execute on function private.ops_task_runs_keep_sha() from public, anon, authenticated;

create trigger ops_task_runs_keep_sha
  before update on private.ops_task_runs
  for each row execute function private.ops_task_runs_keep_sha();

-- 'run' records the task and names it for private.set_ops_task_result for
-- the rest of the transaction; 'already ran' means the same file ran before.
create or replace function private.begin_ops_task(p_name text, p_sha256 text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_sha text;
begin
  select r.sha256 into v_sha from private.ops_task_runs r where r.name = p_name;
  if found then
    if v_sha <> p_sha256 then
      raise exception 'begin_ops_task: % ran as %, and the file is now %; a task is never edited after it runs, add a new one',
        p_name, v_sha, p_sha256 using errcode = '55000';
    end if;
    return 'already ran';
  end if;
  insert into private.ops_task_runs (name, sha256) values (p_name, p_sha256);
  perform set_config('threkir.ops_task', p_name, true);
  return 'run';
end;
$$;

comment on function private.begin_ops_task(text, text) is
  'Records an ops task as run and returns ''run'', or ''already ran'' for a task the ledger holds with the '
  'same sha256; refuses one whose file changed. Service role only (decisions § 2430).';

revoke execute on function private.begin_ops_task(text, text) from public, anon, authenticated;
grant execute on function private.begin_ops_task(text, text) to service_role;

create or replace function private.set_ops_task_result(p_result jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_name text := nullif(current_setting('threkir.ops_task', true), '');
begin
  if v_name is null then
    raise exception 'set_ops_task_result: no ops task is running in this transaction' using errcode = '55000';
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object' then
    raise exception 'set_ops_task_result: the result must be a json object' using errcode = '22023';
  end if;
  update private.ops_task_runs set result = p_result where name = v_name;
end;
$$;

comment on function private.set_ops_task_result(jsonb) is
  'Records what the running ops task did, as a json object, on its ledger row. Service role only '
  '(decisions § 2430).';

revoke execute on function private.set_ops_task_result(jsonb) from public, anon, authenticated;
grant execute on function private.set_ops_task_result(jsonb) to service_role;
