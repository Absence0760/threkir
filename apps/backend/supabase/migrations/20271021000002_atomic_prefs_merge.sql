-- Atomic owner merges into the user_settings / user_device_settings prefs bags
-- (issue #1212).
--
-- Both clients pushed a settings change as a read-merge-write of the WHOLE bag:
-- select prefs, merge the change in the client, upsert the merged bag back.
-- Two writers in flight for the same user each read the bag before the other's
-- upsert landed, and the second upsert wrote the first one's key back to its
-- old value. A single page load has several such writers — the root layout's
-- `time_zone` sync, a prefs page's one-time `locale` stamp, the page's own
-- save — so the loss was not a cross-device rarity: on CI a /settings/body save
-- of `body_weight_kg` was overwritten by the `locale` stamp 28 ms later and the
-- calorie mirror kept the stale weight (run 39352386317).
--
-- set_push_subscription (20270419_001, issue #235) closed this for one key.
-- These close it for every key: the merge happens inside one
-- INSERT ... ON CONFLICT DO UPDATE, whose row lock serialises concurrent
-- merges, so each one applies its delta to the bag the previous one left.
--
-- `p_changes` is the client's delta with the clients' existing semantics
-- (applyPrefsChanges): a key whose value is JSON null is REMOVED, every other
-- key is set, keys not named are left alone. Returns the merged bag so the
-- caller can stamp its cache with the server's union.
--
-- SECURITY INVOKER: the owner-only RLS policies still apply and auth.uid()
-- names the row, so a caller can only ever reach their own bag. The device
-- variant's insert arm takes platform (NOT NULL) + label, matching the row
-- loadSettings provisions.

create or replace function merge_my_settings(p_changes jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_removed text[];
  v_set jsonb;
  v_prefs jsonb;
begin
  if p_changes is null or jsonb_typeof(p_changes) <> 'object' then
    raise exception 'merge_my_settings: p_changes must be a JSON object'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(key), '{}')
    into v_removed
    from jsonb_each(p_changes)
   where jsonb_typeof(value) = 'null';
  v_set := p_changes - v_removed;

  insert into user_settings (user_id, prefs, updated_at)
  values (auth.uid(), v_set, now())
  on conflict (user_id) do update
    set prefs = (user_settings.prefs - v_removed) || v_set,
        updated_at = now()
  returning prefs into v_prefs;

  return v_prefs;
end;
$$;

revoke execute on function merge_my_settings(jsonb) from public, anon;
grant execute on function merge_my_settings(jsonb) to authenticated;

create or replace function merge_my_device_settings(
  p_device_id text,
  p_changes jsonb,
  p_platform text,
  p_label text default null
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_removed text[];
  v_set jsonb;
  v_prefs jsonb;
begin
  if p_changes is null or jsonb_typeof(p_changes) <> 'object' then
    raise exception 'merge_my_device_settings: p_changes must be a JSON object'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(key), '{}')
    into v_removed
    from jsonb_each(p_changes)
   where jsonb_typeof(value) = 'null';
  v_set := p_changes - v_removed;

  insert into user_device_settings (user_id, device_id, platform, label, prefs, updated_at)
  values (auth.uid(), p_device_id, p_platform, p_label, v_set, now())
  on conflict (user_id, device_id) do update
    set prefs = (user_device_settings.prefs - v_removed) || v_set,
        updated_at = now()
  returning prefs into v_prefs;

  return v_prefs;
end;
$$;

revoke execute on function merge_my_device_settings(text, jsonb, text, text) from public, anon;
grant execute on function merge_my_device_settings(text, jsonb, text, text) to authenticated;
