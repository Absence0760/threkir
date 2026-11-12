-- `user_profiles.parkrun_number` holds a parkrun athlete number: `A` + 1-12
-- digits, the shape `parkrun-import` accepts (`/^A\d{1,12}$/`).
--
-- Since decisions § 1904 both clients save it canonical through
-- `normalizeParkrunAthleteNumber` (web `lib/integrations/parkrun_barcode.ts`,
-- Dart `lib/parkrun_barcode.dart`), but the column itself accepted any text up
-- to 32 characters, so legacy free text, an older mobile build and a direct
-- PostgREST PATCH could all store a value the import refuses and the barcode
-- cannot draw.
--
--   1. `private.normalize_parkrun_number` — the clients' normalisation in SQL:
--      every whitespace character dropped, a leading lowercase `a` raised to
--      `A`, then the result kept only if it is `A` + 1-12 ASCII digits, else
--      NULL. The whitespace class is spelled out rather than written `\s`,
--      because the clients' `\s` is the ECMAScript set (Dart's RegExp follows
--      it) and Postgres's `\s` is the database locale's `[[:space:]]`: on the
--      local en_US.UTF-8 stack it misses U+FEFF, which ECMAScript drops.
--      Digits are `[0-9]`, not `\d`, because the same locale's `\d` matches
--      Arabic-Indic and fullwidth digits that ECMAScript's `\d` refuses.
--   2. `user_profiles_parkrun_number_normalize` — a BEFORE trigger that
--      rewrites a normalisable write into its canonical form and leaves
--      anything else as supplied, so an older client that sends `a 123 456`
--      still saves while junk reaches the CHECK and is refused with 23514
--      rather than being silently cleared. A value that is empty once its
--      whitespace is dropped is stored as NULL: a blank field is how a
--      client clears the number, and both clients already send NULL for it.
--   3. A backfill that rewrites every stored value through (1), NULLing what
--      cannot be normalised: an existing value is not the runner's input in
--      this session, so there is nobody to refuse it to, and a value the
--      import refuses was never usable.
--   4. `user_profiles_parkrun_number_format_chk`, added NOT VALID here and
--      validated in 20270818000002, in its own transaction
--      (migration_locks.md, decisions § 1180).
--
-- The function is a pure text transform that reads no table, so EXECUTE is
-- left to PUBLIC: the trigger evaluates it as whichever role is writing.
-- `private` is not a PostgREST-exposed schema, so this exposes no RPC.
--
-- Lock profile: CREATE FUNCTION locks no table. CREATE TRIGGER takes SHARE ROW
-- EXCLUSIVE on user_profiles (readers proceed; writers wait), held through the
-- backfill, which is why the trigger comes first: a write committing between a
-- backfill and a later trigger would escape both and fail the VALIDATE.
-- `user_profiles` is one row per account, not one of the high-volume tables;
-- the backfill is still scoped to rows whose value changes and batched by
-- primary key. ADD CONSTRAINT … NOT VALID is a metadata flip with no scan and
-- goes last, so its ACCESS EXCLUSIVE is held for the shortest span.

create or replace function private.compact_parkrun_number(p_raw text)
returns text
language sql
immutable
parallel safe
returns null on null input
set search_path = ''
as $$
  select regexp_replace(p_raw, '[\t\n\v\f\r    -     　﻿]+', '', 'g');
$$;

comment on function private.compact_parkrun_number(text) is
  'A typed parkrun number with every whitespace character dropped (the ECMAScript \s set). The first step of private.normalize_parkrun_number; the trigger also reads it to tell a cleared field from junk.';

grant execute on function private.compact_parkrun_number(text) to public;

create or replace function private.normalize_parkrun_number(p_raw text)
returns text
language sql
immutable
parallel safe
returns null on null input
set search_path = ''
as $$
  select case when canonical ~ '^A[0-9]{1,12}$' then canonical end
  from (
    select case when left(compact, 1) = 'a' then 'A' || substr(compact, 2) else compact end
      as canonical
    from (
      select private.compact_parkrun_number(p_raw) as compact
    ) as stripped
  ) as raised;
$$;

comment on function private.normalize_parkrun_number(text) is
  'Canonical parkrun athlete number (A + 1-12 digits) for a typed value, or NULL when it is not one. SQL twin of normalizeParkrunAthleteNumber (web parkrun_barcode.ts, Dart parkrun_barcode.dart). Backs trigger user_profiles_parkrun_number_normalize and CHECK user_profiles_parkrun_number_format_chk.';

grant execute on function private.normalize_parkrun_number(text) to public;

create or replace function private.user_profiles_parkrun_number_normalize()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.compact_parkrun_number(new.parkrun_number) = '' then
    new.parkrun_number := null;
  else
    new.parkrun_number := coalesce(
      private.normalize_parkrun_number(new.parkrun_number),
      new.parkrun_number
    );
  end if;
  return new;
end;
$$;

create trigger user_profiles_parkrun_number_normalize
  before insert or update of parkrun_number on public.user_profiles
  for each row execute function private.user_profiles_parkrun_number_normalize();

do $$
declare
  batch_size constant integer := 1000;
  touched integer;
begin
  loop
    with candidates as (
      select id
      from public.user_profiles
      where parkrun_number is not null
        and parkrun_number is distinct from private.normalize_parkrun_number(parkrun_number)
      order by id
      limit batch_size
    )
    update public.user_profiles p
    set parkrun_number = private.normalize_parkrun_number(p.parkrun_number)
    from candidates c
    where p.id = c.id;
    get diagnostics touched = row_count;
    exit when touched = 0;
  end loop;
end;
$$;

alter table public.user_profiles
  add constraint user_profiles_parkrun_number_format_chk
  check (parkrun_number ~ '^A[0-9]{1,12}$')
  not valid;
