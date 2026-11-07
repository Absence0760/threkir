-- Display name from the sign-in provider (migration 20271111000002,
-- decisions § 2363, issue #1300 BUG-013).
--
-- Pins: the rule takes full_name, else name, cleaned and capped at 60, and
-- never an email-shaped value or anything from the email address; a closed
-- gate fills nothing; a new profile row gets the provider name whoever
-- inserts it, and a name the client sent wins; a metadata write within a day
-- of creation fills a still-null name (Apple), never overwrites one, and
-- does nothing for an older account; the backfill fills only null rows that
-- have a provider name, is a no-op while the gate is closed, and reports what
-- it changed; no client role can call the functions.

begin;

select plan(21);

insert into private.feature_flags (name, enabled) values ('display_name_from_provider', false)
  on conflict (name) do update set enabled = false;

-- ── The rule ──
select is(private.display_name_from_auth_meta('{"full_name":"Ana Souza","name":"Ana"}'::jsonb),
  'Ana Souza', 'full_name wins over name');
select is(private.display_name_from_auth_meta('{"name":"  Kenji \t  Sato \n"}'::jsonb),
  'Kenji Sato', 'name is used when full_name is absent, whitespace collapsed');
select is(private.display_name_from_auth_meta('{"full_name":"   ","name":"Lea"}'::jsonb),
  'Lea', 'a blank full_name falls through to name');
select is(private.display_name_from_auth_meta('{"full_name":"ana.souza@example.com"}'::jsonb),
  null, 'an email-shaped name is refused');
select is(private.display_name_from_auth_meta('{"email":"ana.souza@example.com"}'::jsonb),
  null, 'nothing is derived from the email address');
select is(private.display_name_from_auth_meta('{"full_name":42}'::jsonb),
  null, 'a non-string name is ignored');
select is(char_length(private.display_name_from_auth_meta(jsonb_build_object('full_name', repeat('x', 80)))),
  60, 'a long name is capped at the column''s 60 characters');
select is(private.display_name_from_auth_meta(null), null, 'null metadata gives null');

-- ── Gate closed ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000d4000001', 'authenticated', 'authenticated', 'closed@dn.local', '',
        now(), now(), '{"full_name":"Closed Gate"}'::jsonb);
insert into user_profiles (id) values ('00000000-0000-0000-0000-0000d4000001');
select is((select display_name from user_profiles where id = '00000000-0000-0000-0000-0000d4000001'),
  null, 'a closed gate leaves a new profile unnamed');
select is(private.backfill_display_names_from_provider(), 0, 'the backfill is a no-op while the gate is closed');

update private.feature_flags set enabled = true where name = 'display_name_from_provider';

-- ── New profile rows ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000d4000002', 'authenticated', 'authenticated', 'google@dn.local', '',
        now(), now(), '{"full_name":"Grace Hopper","name":"Grace Hopper"}'::jsonb);
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000d4000002","role":"authenticated"}';
insert into user_profiles (id, preferred_unit, subscription_tier)
  values ('00000000-0000-0000-0000-0000d4000002', 'km', 'free');
reset role;
select is((select display_name from user_profiles where id = '00000000-0000-0000-0000-0000d4000002'),
  'Grace Hopper', 'a client-created profile gets the provider name');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000d4000003', 'authenticated', 'authenticated', 'typed@dn.local', '',
        now(), now(), '{"full_name":"Provider Name"}'::jsonb);
insert into user_profiles (id, display_name) values ('00000000-0000-0000-0000-0000d4000003', 'Typed');
select is((select display_name from user_profiles where id = '00000000-0000-0000-0000-0000d4000003'),
  'Typed', 'a name the client sent is kept');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000d4000004', 'authenticated', 'authenticated', 'jane.doe@dn.local', '',
        now(), now(), '{"age_confirmed_at":"2026-01-01T00:00:00Z"}'::jsonb);
insert into user_profiles (id) values ('00000000-0000-0000-0000-0000d4000004');
select is((select display_name from user_profiles where id = '00000000-0000-0000-0000-0000d4000004'),
  null, 'an email sign-up with no provider name stays unnamed, never the email local-part');

-- ── A name that arrives after the row (Apple) ──
update auth.users set raw_user_meta_data = raw_user_meta_data || '{"full_name":"Jane Doe"}'::jsonb
 where id = '00000000-0000-0000-0000-0000d4000004';
select is((select display_name from user_profiles where id = '00000000-0000-0000-0000-0000d4000004'),
  'Jane Doe', 'a metadata name written within a day fills the null name');

update auth.users set raw_user_meta_data = raw_user_meta_data || '{"full_name":"Jane Renamed"}'::jsonb
 where id = '00000000-0000-0000-0000-0000d4000004';
select is((select display_name from user_profiles where id = '00000000-0000-0000-0000-0000d4000004'),
  'Jane Doe', 'a later metadata name never overwrites a name');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000d4000005', 'authenticated', 'authenticated', 'old@dn.local', '',
        now() - interval '3 days', now(), '{}'::jsonb);
insert into user_profiles (id) values ('00000000-0000-0000-0000-0000d4000005');
update auth.users set raw_user_meta_data = '{"full_name":"Old Account"}'::jsonb
 where id = '00000000-0000-0000-0000-0000d4000005';
select is((select display_name from user_profiles where id = '00000000-0000-0000-0000-0000d4000005'),
  null, 'a metadata name on an account older than a day does not refill');

-- ── Backfill ──
select is(private.backfill_display_names_from_provider(), 2,
  'the backfill fills the two null rows that have a provider name');
select is((select display_name from user_profiles where id = '00000000-0000-0000-0000-0000d4000001'),
  'Closed Gate', 'the backfill fills a row created while the gate was closed');
select is((select display_name from user_profiles where id = '00000000-0000-0000-0000-0000d4000003'),
  'Typed', 'the backfill leaves a named row alone');

-- ── Grants ──
set local role authenticated;
select throws_ok($$ select private.backfill_display_names_from_provider() $$, '42501',
  null, 'authenticated cannot run the backfill');
reset role;
set local role anon;
select throws_ok($$ select private.display_name_from_auth_meta('{}'::jsonb) $$, '42501',
  null, 'anon cannot call the rule');
reset role;

select * from finish();
rollback;
