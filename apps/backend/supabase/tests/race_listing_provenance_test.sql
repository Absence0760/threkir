-- Pins 20271124002406: a race listing's organiser badge follows the club's
-- verification at read time (issue #1190, decisions § 2406).
--
-- organiser_is_official is true only while the claiming club is verified,
-- public and not hidden. A claimed hand-added listing reads is_verified from
-- the same standing; a provider-synced one keeps its stored flag. A runner's
-- own write can never make a listing read as organiser-backed.

begin;
select plan(16);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a1d00000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rlp-org@rlp.local', '', now(), now()),
  ('a1d00000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rlp-runner@rlp.local', '', now(), now())
on conflict (id) do nothing;

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values ('a1d11111-0000-0000-0000-000000000001', 'a1d00000-0000-0000-0000-000000000001', 'RLP Marathon', 'rlp-marathon', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = 'a1d11111-0000-0000-0000-000000000001';
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified)
values
  ('a1d33333-0000-0000-0000-000000000001', 'manual', null, 'RLP Hand Added 10K', '2036-10-04', 10000, false),
  ('a1d33333-0000-0000-0000-000000000002', 'runsignup', 'rlp-2', 'RLP Synced Half', '2036-10-11', 21097, true),
  ('a1d33333-0000-0000-0000-000000000003', 'manual', null, 'RLP Unclaimed 5K', '2036-10-18', 5000, false);
reset role;
set local "request.jwt.claims" = '';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000001","role":"authenticated"}';
select claim_race_listing('a1d33333-0000-0000-0000-000000000001', 'a1d11111-0000-0000-0000-000000000001');
select claim_race_listing('a1d33333-0000-0000-0000-000000000002', 'a1d11111-0000-0000-0000-000000000001');
reset role;

-- ── while the club is verified ──────────────────────────────────────────────

set local role anon;
select results_eq(
  $$ select id, organiser_is_official, is_verified from public_race_listings
      where id::text like 'a1d33333%' order by id $$,
  $$ values
       ('a1d33333-0000-0000-0000-000000000001'::uuid, true, true),
       ('a1d33333-0000-0000-0000-000000000002'::uuid, true, true),
       ('a1d33333-0000-0000-0000-000000000003'::uuid, false, false) $$,
  'a claimed listing reads as organiser-backed; an unclaimed one does not'
);
reset role;

-- ── revoking the club's badge ───────────────────────────────────────────────

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = false where id = 'a1d11111-0000-0000-0000-000000000001';
reset role;
set local "request.jwt.claims" = '';

set local role anon;
select is(
  (select organiser_is_official from public_race_listings where id = 'a1d33333-0000-0000-0000-000000000001'),
  false,
  'revoking the club drops the organiser badge from a hand-added listing'
);
select is(
  (select is_verified from public_race_listings where id = 'a1d33333-0000-0000-0000-000000000001'),
  false,
  'a claimed hand-added listing stops reading as verified when its club is revoked'
);
select is(
  (select organiser_is_official from public_race_listings where id = 'a1d33333-0000-0000-0000-000000000002'),
  false,
  'revoking the club drops the organiser badge from a synced listing'
);
select is(
  (select is_verified from public_race_listings where id = 'a1d33333-0000-0000-0000-000000000002'),
  true,
  'a synced listing keeps the verification its provider sync gave it'
);
select is(
  (select organiser_club_name from public_race_listings where id = 'a1d33333-0000-0000-0000-000000000001'),
  'RLP Marathon',
  'the club that added the race is still named'
);
reset role;
select is(
  (select is_verified from race_listings where id = 'a1d33333-0000-0000-0000-000000000001'),
  true,
  'the stored flag is untouched; only the read follows the club'
);

-- ── re-verified, then hidden, then private ──────────────────────────────────

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = 'a1d11111-0000-0000-0000-000000000001';
reset role;
set local "request.jwt.claims" = '';

set local role anon;
select is(
  (select organiser_is_official from public_race_listings where id = 'a1d33333-0000-0000-0000-000000000001'),
  true,
  're-verifying the club restores the badge with no write to the listing'
);
reset role;

update clubs set shadow_hidden = true where id = 'a1d11111-0000-0000-0000-000000000001';
set local role anon;
select results_eq(
  $$ select organiser_is_official, is_verified from public_race_listings
      where id = 'a1d33333-0000-0000-0000-000000000001' $$,
  $$ values (false, false) $$,
  'a club hidden by the report flow lends no badge'
);
reset role;
update clubs set shadow_hidden = false, is_public = false where id = 'a1d11111-0000-0000-0000-000000000001';
set local role anon;
select is(
  (select organiser_is_official from public_race_listings where id = 'a1d33333-0000-0000-0000-000000000001'),
  false,
  'a private club lends no badge and is not named'
);
select is(
  (select organiser_club_id from public_race_listings where id = 'a1d33333-0000-0000-0000-000000000001'),
  null::uuid,
  'a private organiser club stays masked'
);
reset role;
update clubs set is_public = true where id = 'a1d11111-0000-0000-0000-000000000001';

-- ── a runner cannot forge it ────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into race_listings (id, provider, name, race_date, submitted_by, is_verified, organiser_club_id)
values ('a1d33333-0000-0000-0000-000000000004', 'manual', 'RLP Fan Copy', '2036-10-04',
        'a1d00000-0000-0000-0000-000000000002', true, 'a1d11111-0000-0000-0000-000000000001');
select results_eq(
  $$ select organiser_is_official, is_verified, organiser_club_id from public_race_listings
      where id = 'a1d33333-0000-0000-0000-000000000004' $$,
  $$ values (false, false, null::uuid) $$,
  'a runner''s insert naming a verified club reads as a community listing'
);
update race_listings set organiser_club_id = 'a1d11111-0000-0000-0000-000000000001', is_verified = true
 where id = 'a1d33333-0000-0000-0000-000000000004';
select results_eq(
  $$ select organiser_is_official, is_verified from public_race_listings
      where id = 'a1d33333-0000-0000-0000-000000000004' $$,
  $$ values (false, false) $$,
  'a runner''s update cannot attach a verified club to their listing'
);
reset role;

select is(
  (select organiser_club_id from race_listings where id = 'a1d33333-0000-0000-0000-000000000004'),
  null::uuid,
  'the stored organiser of the fan copy is still empty'
);
select ok(
  not has_table_privilege('authenticated', 'public.public_race_listings', 'UPDATE')
    and not has_table_privilege('anon', 'public.public_race_listings', 'UPDATE'),
  'the view takes no client write'
);
select has_column('public', 'public_race_listings', 'organiser_is_official',
  'public_race_listings exposes the derived organiser flag');

select * from finish();
rollback;
