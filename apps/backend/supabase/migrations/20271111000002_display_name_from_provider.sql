-- Fill user_profiles.display_name from the sign-in provider's name
-- (issue #1300 BUG-013, decisions § 2365).
--
-- Club rosters, RSVP lists and post bylines showed "Member" with a "?"
-- avatar because display_name was null: both clients create the profile row
-- without a name (ensureMyProfile, auth.svelte.ts fetchUser,
-- confirm_age_and_terms, stamp_signup_consent), and only the setup wizard's
-- skippable first step ever asks for one.
--
-- 1. The rule. private.display_name_from_auth_meta() reads the name Google or
--    Apple put in auth.users.raw_user_meta_data (`full_name`, else `name`),
--    collapses whitespace, drops control characters, caps it at the column's
--    60 characters and refuses anything containing '@'. It never derives a
--    name from the email address: the local-part is often the person's real
--    name or a handle they use elsewhere, and a display name is shown to
--    club members, attendees and, on a public profile, to anyone, while the
--    email address is shown to nobody. An account with no provider name keeps
--    a null display_name; the clients show a neutral, localised label for it
--    and the wizard and club pages ask for a name.
--
-- 2. Where it applies. On the profile row, not on one creator: a BEFORE
--    INSERT trigger on user_profiles fills a null display_name, so every path
--    that creates the row gets it, including the auth.users sign-up hook
--    (stamp_signup_consent, 20271023000001), which inserts the row from the
--    same trigger chain. Extending that hook alone would have missed OAuth
--    sign-ups (they carry no consent metadata) and the client-created rows.
--    Apple sends the name only on the first authorization and outside the
--    identity token, so mobile writes it to the user metadata after sign-in;
--    an AFTER UPDATE OF raw_user_meta_data trigger on auth.users fills a still
--    null display_name from that write, only within a day of the account's
--    creation, so a later provider-side rename never refills a name the person
--    cleared on purpose.
--
-- 3. The gate. Showing other people a name the person did not type is a
--    privacy-boundary change (the Privacy Policy calls the display name
--    optional), so the whole path is fail-closed behind a
--    'display_name_from_provider' row in private.feature_flags that NO
--    MIGRATION WRITES. It waits on the CISO + counsel sign-off in
--    docs/ops/deployment.md; seed.sql opens it for local + CI.
--
-- 4. Existing rows. private.backfill_display_names_from_provider() fills the
--    rows that are still null by the same rule and returns how many it
--    changed. This migration calls it, which is a no-op while the gate is
--    closed; the operator runs it once after opening the gate. user_profiles
--    is one row per account and is on the small, bounded list in
--    docs/backend/migration_locks.md, so it is a single UPDATE scoped by
--    predicate (display_name is null and a provider name exists), not an
--    id-range loop: a migration or a function call runs in one transaction,
--    where chunking buys no lock relief.
--
-- Locks: new functions and triggers (catalogue only). The backfill takes row
-- locks only on the rows it fills. No column moves, so neither row-type
-- generator has anything to regenerate.

-- ── 1. The rule ─────────────────────────────────────────────────────────────

create or replace function private.display_name_from_auth_meta(meta jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  k text;
  v text;
begin
  if meta is null or jsonb_typeof(meta) <> 'object' then
    return null;
  end if;
  foreach k in array array['full_name', 'name'] loop
    if jsonb_typeof(meta -> k) = 'string' then
      v := btrim(regexp_replace(regexp_replace(meta ->> k, '[[:cntrl:]]', ' ', 'g'), '\s+', ' ', 'g'));
      if v <> '' and position('@' in v) = 0 then
        return btrim(left(v, 60));
      end if;
    end if;
  end loop;
  return null;
end;
$$;

revoke execute on function private.display_name_from_auth_meta(jsonb) from public, anon, authenticated;

comment on function private.display_name_from_auth_meta(jsonb) is
  'The display name a sign-in provider supplied in auth.users metadata '
  '(full_name, else name), cleaned and capped at 60; null when absent or when '
  'it contains @. Never derived from the email address. decisions § 2365.';

-- ── 2. The gate ─────────────────────────────────────────────────────────────

create or replace function private.display_name_from_provider_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'display_name_from_provider'),
    false
  );
$$;

revoke execute on function private.display_name_from_provider_enabled() from public, anon, authenticated;

-- ── 3. New profile rows ─────────────────────────────────────────────────────

create or replace function private.fill_display_name_from_provider()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if new.display_name is null and private.display_name_from_provider_enabled() then
    new.display_name := private.display_name_from_auth_meta(
      (select u.raw_user_meta_data from auth.users u where u.id = new.id));
  end if;
  return new;
end;
$$;

revoke execute on function private.fill_display_name_from_provider() from public, anon, authenticated;

create trigger user_profiles_fill_display_name
  before insert on public.user_profiles
  for each row
  when (new.display_name is null)
  execute function private.fill_display_name_from_provider();

-- ── 4. A name that arrives after the row (Apple) ────────────────────────────

create or replace function private.fill_display_name_from_metadata()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_name text;
begin
  if coalesce(new.created_at, now()) < now() - interval '1 day'
     or not private.display_name_from_provider_enabled() then
    return new;
  end if;
  v_name := private.display_name_from_auth_meta(new.raw_user_meta_data);
  if v_name is null then
    return new;
  end if;
  update public.user_profiles
     set display_name = v_name
   where id = new.id
     and display_name is null;
  return new;
end;
$$;

revoke execute on function private.fill_display_name_from_metadata() from public, anon, authenticated;

create trigger auth_users_fill_display_name_on_metadata
  after update of raw_user_meta_data on auth.users
  for each row
  when ((old.raw_user_meta_data -> 'full_name') is distinct from (new.raw_user_meta_data -> 'full_name')
        or (old.raw_user_meta_data -> 'name') is distinct from (new.raw_user_meta_data -> 'name'))
  execute function private.fill_display_name_from_metadata();

-- ── 5. Existing rows ────────────────────────────────────────────────────────

create or replace function private.backfill_display_names_from_provider()
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_count integer;
begin
  if not private.display_name_from_provider_enabled() then
    return 0;
  end if;
  update public.user_profiles p
     set display_name = private.display_name_from_auth_meta(u.raw_user_meta_data)
    from auth.users u
   where u.id = p.id
     and p.display_name is null
     and private.display_name_from_auth_meta(u.raw_user_meta_data) is not null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function private.backfill_display_names_from_provider() from public, anon, authenticated;

comment on function private.backfill_display_names_from_provider() is
  'Fills every null user_profiles.display_name from the provider name in '
  'auth.users metadata; returns the rows changed. No-op while the '
  'display_name_from_provider gate is closed. Run once after opening it '
  '(docs/ops/deployment.md). decisions § 2365.';

select private.backfill_display_names_from_provider();
