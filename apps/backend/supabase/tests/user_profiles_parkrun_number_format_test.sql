-- pgtap suite for the user_profiles.parkrun_number format (migrations
-- 20270818000001 + 20270818000002).
--
-- Both clients save the number canonical (`A` + 1-12 digits) through
-- `normalizeParkrunAthleteNumber` (decisions § 1904); the column now holds
-- that shape itself, so a legacy value, an older client or a direct PATCH
-- cannot store one `parkrun-import` refuses and the barcode cannot draw.
--
-- Covers:
--   * `private.normalize_parkrun_number` against the clients' own case table
--     (web parkrun_barcode.test.ts, Dart parkrun_barcode_test.dart), plus the
--     whitespace and digit classes where Postgres's defaults differ from
--     ECMAScript's
--   * an owner's write of a normalisable value stores the canonical form
--   * an owner's write of junk is refused, not silently cleared
--   * NULL still clears the number
--   * a write that bypasses triggers is refused by the CHECK
--   * the CHECK is validated, not left NOT VALID

begin;

select plan(29);

-- ── The normaliser ──────────────────────────────────────────────────────────

select is(private.normalize_parkrun_number('A123456'), 'A123456', 'a canonical number is unchanged');
select is(private.normalize_parkrun_number('a123456'), 'A123456', 'a lowercase leading a is raised');
select is(private.normalize_parkrun_number('  A 123 456  '), 'A123456', 'spaces anywhere are dropped');
select is(private.normalize_parkrun_number(E'\tA123\n456\r'), 'A123456', 'tabs and line breaks are dropped');
select is(private.normalize_parkrun_number(E'A 123 456'), 'A123456',
  'a no-break and a thin space are dropped, as ECMAScript \s drops them');
select is(private.normalize_parkrun_number(E'﻿A123456　'), 'A123456',
  'a byte-order mark and an ideographic space are dropped');
select is(private.normalize_parkrun_number('A1'), 'A1', 'one digit is the floor');
select is(private.normalize_parkrun_number('A123456789012'), 'A123456789012', 'twelve digits is the ceiling');
select is(private.normalize_parkrun_number('A1234567890123'), null::text, 'thirteen digits is not a number');
select is(private.normalize_parkrun_number('123456'), null::text, 'the leading A is required, not invented');
select is(private.normalize_parkrun_number('A'), null::text, 'A alone has no digits');
select is(private.normalize_parkrun_number('a'), null::text, 'a alone has no digits');
select is(private.normalize_parkrun_number(''), null::text, 'the empty string is no number');
select is(private.normalize_parkrun_number('   '), null::text, 'whitespace alone is no number');
select is(private.normalize_parkrun_number('AA123'), null::text, 'a doubled A is refused');
select is(private.normalize_parkrun_number('aa123'), null::text, 'only the first a is raised');
select is(private.normalize_parkrun_number('A12b3'), null::text, 'a letter among the digits is refused');
select is(private.normalize_parkrun_number('A-123'), null::text, 'punctuation is refused, not stripped');
select is(private.normalize_parkrun_number('A１２３'), null::text, 'fullwidth digits are not ASCII digits');
select is(private.normalize_parkrun_number('A٣٤٥'), null::text, 'Arabic-Indic digits are not ASCII digits');
select is(private.normalize_parkrun_number('my number is A123'), null::text, 'free text is refused');
select is(private.normalize_parkrun_number(null), null::text, 'NULL stays NULL');

-- ── Every write path through the trigger ────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000a7b01', 'authenticated', 'authenticated',
        'parkrun@format.local', '', now(), now());

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000a7b01"}';

update user_profiles
set parkrun_number = ' a 765 432 '
where id = '00000000-0000-0000-0000-0000000a7b01';

select is(
  (select parkrun_number from get_my_profile()),
  'A765432',
  'an owner UPDATE of a normalisable number stores the canonical form'
);

select throws_ok(
  $$ update user_profiles set parkrun_number = 'my number'
     where id = '00000000-0000-0000-0000-0000000a7b01' $$,
  '23514',
  null,
  'an owner UPDATE of junk is refused rather than cleared'
);

select is(
  (select parkrun_number from get_my_profile()),
  'A765432',
  'the refused write left the stored number in place'
);

update user_profiles
set parkrun_number = null
where id = '00000000-0000-0000-0000-0000000a7b01';

select is(
  (select parkrun_number from get_my_profile()),
  null::text,
  'an owner can still clear the number'
);

reset role;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000a7b02', 'authenticated', 'authenticated',
        'parkrun-insert@format.local', '', now(), now());

insert into user_profiles (id, display_name, parkrun_number)
values ('00000000-0000-0000-0000-0000000a7b02', 'Inserted', E'a12 345');

select is(
  (select parkrun_number from user_profiles where id = '00000000-0000-0000-0000-0000000a7b02'),
  'A12345',
  'an INSERT of a normalisable number stores the canonical form'
);

-- ── The floor under the trigger ─────────────────────────────────────────────

set local session_replication_role = replica;

select throws_ok(
  $$ update user_profiles set parkrun_number = 'a123'
     where id = '00000000-0000-0000-0000-0000000a7b02' $$,
  '23514',
  null,
  'a write that bypasses triggers cannot store a non-canonical number'
);

set local session_replication_role = origin;

select is(
  (select convalidated from pg_constraint
   where conrelid = 'public.user_profiles'::regclass
     and conname = 'user_profiles_parkrun_number_format_chk'),
  true,
  'user_profiles_parkrun_number_format_chk is validated'
);

select * from finish();

rollback;
