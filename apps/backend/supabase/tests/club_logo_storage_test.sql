-- Storage policies for club logos (migration 20270918000007): objects at
-- `avatars/clubs/{club_id}/logo.{ext}` are writable by that club's owners and
-- admins only.
--
-- Blast radius if regressed: a member, an outsider or anon replacing a club's
-- public logo (defacement on the share page and in Browse), or an admin of one
-- club writing into another club's path.

begin;

select plan(12);

-- storage-api's protect_delete trigger refuses any direct DELETE on
-- storage.objects unless this is set; the policies are what is under test.
select set_config('storage.allow_delete_query', 'true', true);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c1001', 'authenticated', 'authenticated',
   'owner@club-logo.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c1002', 'authenticated', 'authenticated',
   'admin@club-logo.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c1003', 'authenticated', 'authenticated',
   'member@club-logo.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c1004', 'authenticated', 'authenticated',
   'outsider@club-logo.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c1005', 'authenticated', 'authenticated',
   'other-owner@club-logo.local', '', now(), now());

-- The enroll_club_owner trigger makes each owner an active 'owner' member.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values
  ('11111111-1111-1111-1111-11110000c101',
   '00000000-0000-0000-0000-0000000c1001', 'Logo Club', 'logo-club-c1', true, 'open'),
  ('11111111-1111-1111-1111-11110000c102',
   '00000000-0000-0000-0000-0000000c1005', 'Other Club', 'other-club-c1', true, 'open');

insert into club_members (club_id, user_id, role, status)
values
  ('11111111-1111-1111-1111-11110000c101', '00000000-0000-0000-0000-0000000c1002', 'admin', 'active'),
  ('11111111-1111-1111-1111-11110000c101', '00000000-0000-0000-0000-0000000c1003', 'member', 'active');

set local role authenticated;

-- 1. The owner can upload the club's logo.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c1001","role":"authenticated"}';
select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
       values ('avatars', 'clubs/11111111-1111-1111-1111-11110000c101/logo.png') $$,
  'club owner can upload the club logo'
);

-- 2. ...and see the object row, which Storage .remove() needs.
select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'avatars'
      and name = 'clubs/11111111-1111-1111-1111-11110000c101/logo.png'),
  1,
  'club owner can read the club logo object row'
);

-- 3. An admin can upload too.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c1002","role":"authenticated"}';
select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
       values ('avatars', 'clubs/11111111-1111-1111-1111-11110000c101/logo.webp') $$,
  'club admin can upload the club logo'
);

-- 4. An admin of this club cannot write another club's path.
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
       values ('avatars', 'clubs/11111111-1111-1111-1111-11110000c102/logo.png') $$,
  '42501',
  null,
  'club admin cannot upload another club''s logo'
);

-- 5-6. Only the exact logo filename is writable, not anything under the prefix.
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
       values ('avatars', 'clubs/11111111-1111-1111-1111-11110000c101/payload.html') $$,
  '42501',
  null,
  'club admin cannot upload a non-logo filename under the club prefix'
);

select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
       values ('avatars', 'clubs/11111111-1111-1111-1111-11110000c101/x/logo.png') $$,
  '42501',
  null,
  'club admin cannot upload into a sub-folder of the club prefix'
);

-- 7. A plain member cannot upload.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c1003","role":"authenticated"}';
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
       values ('avatars', 'clubs/11111111-1111-1111-1111-11110000c101/logo.jpg') $$,
  '42501',
  null,
  'club member cannot upload the club logo'
);

-- A member's delete matches nothing they may touch: the object survives.
delete from storage.objects
  where bucket_id = 'avatars'
    and name = 'clubs/11111111-1111-1111-1111-11110000c101/logo.png';

-- 8. A non-member cannot upload.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c1004","role":"authenticated"}';
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
       values ('avatars', 'clubs/11111111-1111-1111-1111-11110000c101/logo.jpg') $$,
  '42501',
  null,
  'non-member cannot upload the club logo'
);

delete from storage.objects
  where bucket_id = 'avatars'
    and name = 'clubs/11111111-1111-1111-1111-11110000c101/logo.png';

-- 9. The other club's owner cannot write this club's path.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c1005","role":"authenticated"}';
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
       values ('avatars', 'clubs/11111111-1111-1111-1111-11110000c101/logo.jpg') $$,
  '42501',
  null,
  'another club''s owner cannot upload this club''s logo'
);

-- 10. Anon cannot upload.
set local role anon;
reset "request.jwt.claims";
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
       values ('avatars', 'clubs/11111111-1111-1111-1111-11110000c101/logo.jpg') $$,
  '42501',
  null,
  'anon cannot upload the club logo'
);

-- 11. The member's and outsider's deletes above removed nothing.
set local role service_role;
select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'avatars'
      and name = 'clubs/11111111-1111-1111-1111-11110000c101/logo.png'),
  1,
  'a member''s or non-member''s delete leaves the club logo in place'
);

-- 12. The owner can delete it.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c1001","role":"authenticated"}';
select lives_ok(
  $$ do $d$
     declare n int;
     begin
       delete from storage.objects
         where bucket_id = 'avatars'
           and name = 'clubs/11111111-1111-1111-1111-11110000c101/logo.png';
       get diagnostics n = row_count;
       if n <> 1 then raise exception 'owner deleted % club logo rows, expected 1', n; end if;
     end $d$ $$,
  'club owner can delete the club logo'
);

select * from finish();

rollback;
