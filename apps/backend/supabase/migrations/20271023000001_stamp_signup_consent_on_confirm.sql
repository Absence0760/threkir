-- Issue #1229 — stamp the sign-up consent when the account becomes usable.
--
-- Email sign-up asks for the 16+ affirmation and the Terms / Privacy
-- acceptance, and both clients send those timestamps in the GoTrue sign-up
-- `data` (so they land in `auth.users.raw_user_meta_data`). The stamp on
-- `user_profiles` was then made by confirm_age_and_terms(), which needs a
-- session. With email confirmation on there is no session at sign-up, so
-- mobile skipped the stamp and web replayed it only when the confirmation
-- link opened in the same browser tab session. Everyone else met the consent
-- gate on first sign-in and was asked the same two questions again.
--
-- The metadata timestamps are the same evidence the RPC records: written by
-- the same client at the moment of the affirmative act, just earlier. So the
-- stamp now happens server-side, when `email_confirmed_at` is first set (or
-- at insert, when confirmation is off), from that metadata. First stamp wins,
-- as in confirm_age_and_terms(). Metadata that is missing, does not parse, or
-- falls outside a window around the account's creation leaves the columns
-- NULL, so the client gate (ConfirmAgeScreen / /auth/confirm-age) and the
-- consent_write_gate trigger beneath it still apply. OAuth sign-ups carry no
-- such metadata and are untouched.
--
-- The trigger can create the user_profiles row, so it also seeds
-- preferred_unit from the metadata's `preferred_unit` ('mi' | anything else
-- reads as 'km'), the same insert-only default confirm_age_and_terms()
-- applies (#488).
--
-- Online safety: CREATE FUNCTION and CREATE TRIGGER take a brief catalogue
-- lock on auth.users and scan nothing. No column moves, so neither row-type
-- generator has anything to regenerate.
--
-- The gate. This changes how Art 8 evidence is captured, so it waits on a
-- legal-researcher memo plus owner approval recorded on #1097 before it
-- reaches real users. It reads a row in private.feature_flags
-- (20270802000001) that no migration writes, so every environment this
-- reaches starts closed and behaves exactly as before; seed.sql opens it for
-- local + CI. Flipping prod is the pre-deploy item in docs/ops/deployment.md.

create or replace function private.stamp_signup_consent()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  created timestamptz := coalesce(new.created_at, now());
  -- The tick happens on the sign-up screen just before the sign-up call, so
  -- a genuine stamp sits just before created_at. The window allows for a
  -- slow form and a device clock that is somewhat off; outside it the
  -- stamp is not trusted and the gate asks instead.
  earliest timestamptz := created - interval '1 day';
  latest timestamptz := least(created + interval '1 hour', now());
  v_age timestamptz;
  v_terms timestamptz;
  v_unit text := case when meta->>'preferred_unit' = 'mi' then 'mi' else 'km' end;
begin
  if new.email_confirmed_at is null
     or not coalesce(
       (select f.enabled from private.feature_flags f
         where f.name = 'signup_consent_from_metadata'),
       false) then
    return new;
  end if;

  begin
    v_age := (meta->>'age_confirmed_at')::timestamptz;
    v_terms := (meta->>'terms_accepted_at')::timestamptz;
  -- Any class-22 error (a bad format, an unknown zone name, an
  -- out-of-range offset) means the stamp is not trusted. It must never abort
  -- the trigger, which would fail the sign-up or the confirmation itself.
  exception when data_exception then
    return new;
  end;

  if v_age is null or v_terms is null
     or v_age < earliest or v_age > latest
     or v_terms < earliest or v_terms > latest then
    return new;
  end if;

  insert into user_profiles (id, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
    values (new.id, v_age, v_terms, v_unit, 'free')
    on conflict (id) do update
    set age_confirmed_at = coalesce(user_profiles.age_confirmed_at, excluded.age_confirmed_at),
        terms_accepted_at = coalesce(user_profiles.terms_accepted_at, excluded.terms_accepted_at);

  return new;
end;
$$;

revoke execute on function private.stamp_signup_consent() from public, anon, authenticated;

comment on function private.stamp_signup_consent() is
  'Stamps user_profiles.age_confirmed_at + terms_accepted_at from the '
  'sign-up metadata when an auth.users row is first confirmed (issue #1229). '
  'First stamp wins; missing, malformed or out-of-window metadata leaves '
  'them NULL so the consent gate still asks. Off until the '
  'signup_consent_from_metadata row in private.feature_flags is enabled.';

create trigger auth_users_stamp_signup_consent_on_insert
  after insert on auth.users
  for each row
  when (new.email_confirmed_at is not null)
  execute function private.stamp_signup_consent();

create trigger auth_users_stamp_signup_consent_on_confirm
  after update of email_confirmed_at on auth.users
  for each row
  when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
  execute function private.stamp_signup_consent();
