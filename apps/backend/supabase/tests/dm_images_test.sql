-- Pins migrations 20271213121604/5 — photos in direct messages (issue
-- #1216): the gate, the owner-only upload path, sending only inside an
-- established conversation, the link and the processing job, who can read
-- the bytes (only a ready, re-encoded copy, only by who can read the
-- message), unsend and account deletion erasing the image unless a report
-- holds it, the report snapshot, and the orphan worklist.

begin;
select plan(38);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
select ('aaaa1216-1a6e-0000-0000-0000000000' || s)::uuid, 'img-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['a1', 'b2', 'c3', 'd4', 'e5']) as s
on conflict (id) do nothing;

-- A follows B. D shares a club with A and no follow edge. E is an admin.
insert into user_follows (follower_id, followee_id)
values ('aaaa1216-1a6e-0000-0000-0000000000a1', 'aaaa1216-1a6e-0000-0000-0000000000b2');
insert into clubs (id, owner_id, name, slug, is_public)
values ('cccc1216-1a6e-0000-0000-000000000001', 'aaaa1216-1a6e-0000-0000-0000000000a1',
        'Images Club', 'images-club-1216', true);
insert into club_members (club_id, user_id, role, status) values
  ('cccc1216-1a6e-0000-0000-000000000001', 'aaaa1216-1a6e-0000-0000-0000000000a1', 'owner', 'active'),
  ('cccc1216-1a6e-0000-0000-000000000001', 'aaaa1216-1a6e-0000-0000-0000000000d4', 'member', 'active')
on conflict (club_id, user_id) do update set status = excluded.status;
insert into app_admins (user_id) values ('aaaa1216-1a6e-0000-0000-0000000000e5')
on conflict do nothing;
insert into private.feature_flags (name, enabled) values ('dm_images', true)
on conflict (name) do update set enabled = true;

create temporary table img (k text primary key, id uuid, path text);
grant all on img to authenticated;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000a1","role":"authenticated"}';

insert into img select 'one', u.id, u.upload_path from create_dm_image_upload() u;
insert into img select 'two', u.id, u.upload_path from create_dm_image_upload() u;
insert into img select 'three', u.id, u.upload_path from create_dm_image_upload() u;

select is(
  (select path from img where k = 'one'),
  'aaaa1216-1a6e-0000-0000-0000000000a1/' || (select id from img where k = 'one') || '/upload',
  'an upload path sits under the owner''s folder and the image id');

-- ── uploading ──

select lives_ok(
  $$insert into storage.objects (bucket_id, name) select 'dm-images', path from img where k = 'one'$$,
  'the owner can upload to their pending image''s path');
insert into storage.objects (bucket_id, name) select 'dm-images', path from img where k in ('two', 'three');
select throws_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('dm-images', 'aaaa1216-1a6e-0000-0000-0000000000a1/anything.jpg')$$,
  '42501', null,
  'any other path in the bucket is refused');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'dm-images'),
  0,
  'not even the owner can read an upload');

set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000c3","role":"authenticated"}';
select throws_ok(
  $$insert into storage.objects (bucket_id, name) select 'dm-images', replace(path, '/upload', '/x') from img where k = 'one'$$,
  '42501', null,
  'someone else cannot upload into the owner''s folder');

-- ── sending ──

set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body, image_id)
    select '4444a216-1a6e-0000-0000-000000000001', 'aaaa1216-1a6e-0000-0000-0000000000a1',
           'aaaa1216-1a6e-0000-0000-0000000000b2', null, id from img where k = 'one'$$,
  'a photo with no caption can be sent along a follow edge');
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, image_id)
    select 'aaaa1216-1a6e-0000-0000-0000000000a1', 'aaaa1216-1a6e-0000-0000-0000000000b2', 'again', id
      from img where k = 'one'$$,
  '42501', null,
  'an image already sent cannot be sent again');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) select 'dm-images', path || '2' from img where k = 'one'$$,
  '42501', null,
  'nothing more can be uploaded for a sent image');
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, image_id)
    values ('aaaa1216-1a6e-0000-0000-0000000000a1', 'aaaa1216-1a6e-0000-0000-0000000000b2', 'x', gen_random_uuid())$$,
  '42501', null,
  'an image id that is not the sender''s is refused');
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa1216-1a6e-0000-0000-0000000000a1', 'aaaa1216-1a6e-0000-0000-0000000000b2', null)$$,
  '23514', null,
  'a message with neither text nor a photo is refused');

reset role;
select is(
  (select message_id from direct_message_images where id = (select id from img where k = 'one')),
  '4444a216-1a6e-0000-0000-000000000001'::uuid,
  'the send links the image to its message');
select is(
  (select count(*)::int from jobs where kind = 'dm_image_process'
     and payload ->> 'image_id' = (select id::text from img where k = 'one')),
  1,
  'the send queues the image for the worker');

-- ── a request carries no photo ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000d4","role":"authenticated"}';
insert into img select 'd', u.id, u.upload_path from create_dm_image_upload() u;
insert into storage.objects (bucket_id, name) select 'dm-images', path from img where k = 'd';
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, image_id)
    select 'aaaa1216-1a6e-0000-0000-0000000000d4', 'aaaa1216-1a6e-0000-0000-0000000000a1', 'hi', id from img where k = 'd'$$,
  '42501', null,
  'a first message request cannot carry a photo');
select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa1216-1a6e-0000-0000-0000000000d4', 'aaaa1216-1a6e-0000-0000-0000000000a1', 'hi')$$,
  'the same request as text is admitted');
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, image_id)
    select 'aaaa1216-1a6e-0000-0000-0000000000d4', 'aaaa1216-1a6e-0000-0000-0000000000a1', 'pic', id from img where k = 'd'$$,
  '42501', null,
  'a pending request cannot carry a photo either');

-- ── reading: only the re-encoded copy, only by who can read the message ──

reset role;
insert into storage.objects (bucket_id, name)
select 'dm-images', storage_path from direct_message_images where id = (select id from img where k = 'one');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000b2","role":"authenticated"}';
select is(
  (select status from direct_message_images where id = (select id from img where k = 'one')),
  'pending',
  'the recipient reads the image row');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'dm-images'),
  0,
  'no bytes are readable before the worker marks the image ready');

reset role;
update direct_message_images set status = 'ready', width = 800, height = 600, processed_at = now()
 where id = (select id from img where k = 'one');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000b2","role":"authenticated"}';
select is(
  (select array_agg(name) from storage.objects where bucket_id = 'dm-images'),
  array['aaaa1216-1a6e-0000-0000-0000000000a1/' || (select id from img where k = 'one') || '.jpg'],
  'once ready the recipient reads the re-encoded copy and never the upload');
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000c3","role":"authenticated"}';
select is(
  (select count(*)::int from direct_message_images),
  0,
  'someone outside the conversation reads no image row');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'dm-images'),
  0,
  'and no image bytes');
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000e5","role":"authenticated"}';
select is(
  (select count(*)::int from storage.objects where bucket_id = 'dm-images'),
  0,
  'an admin reads no image no report holds');

-- ── unsend erases ──

set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$select unsend_direct_message('4444a216-1a6e-0000-0000-000000000001')$$,
  'the sender unsends the photo');
reset role;
select is(
  (select count(*)::int from direct_message_images where id = (select id from img where k = 'one')),
  0,
  'unsending deleted the image row');
select ok(
  (select payload -> 'paths' from jobs where kind = 'dm_image_orphan_sweep' order by created_at desc limit 1)
    @> to_jsonb(array[(select path from img where k = 'one'),
                      replace((select path from img where k = 'one'), '/upload', '.jpg')]),
  'and queued both its objects for erasure');
select is(
  (select array_agg(p) from dm_image_orphan_paths(
     array[replace((select path from img where k = 'one'), '/upload', '.jpg'),
           (select path from img where k = 'two')]) p),
  array[replace((select path from img where k = 'one'), '/upload', '.jpg')],
  'the worklist names the orphaned object and not a pending image''s upload');

-- ── a report holds the image ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000a1","role":"authenticated"}';
insert into direct_messages (id, sender_id, recipient_id, body, image_id)
select '4444a216-1a6e-0000-0000-000000000002', 'aaaa1216-1a6e-0000-0000-0000000000a1',
       'aaaa1216-1a6e-0000-0000-0000000000b2', null, id from img where k = 'two';
reset role;
update direct_message_images set status = 'ready', width = 10, height = 10 where id = (select id from img where k = 'two');
insert into storage.objects (bucket_id, name)
select 'dm-images', storage_path from direct_message_images where id = (select id from img where k = 'two');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000b2","role":"authenticated"}';
select lives_ok(
  $$select submit_report('direct_message', '4444a216-1a6e-0000-0000-000000000002', 'harassment', null)$$,
  'the recipient can report a photo with no caption');
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000a1","role":"authenticated"}';
select unsend_direct_message('4444a216-1a6e-0000-0000-000000000002');
reset role;
select is(
  (select snapshot_image_id from reports where target_id = '4444a216-1a6e-0000-0000-000000000002'),
  (select id from img where k = 'two'),
  'the report snapshots the image and keeps it past the unsend');
insert into img select 'report', id, null from reports where target_id = '4444a216-1a6e-0000-0000-000000000002';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000e5","role":"authenticated"}';
select is(
  (select count(*)::int from storage.objects where bucket_id = 'dm-images'),
  1,
  'an admin reads an image a report holds');
select is(
  admin_dm_report_image_path((select id from img where k = 'report')),
  (select replace(path, '/upload', '.jpg') from img where k = 'two'),
  'and gets its path from the report');
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$select admin_dm_report_image_path(gen_random_uuid())$$,
  '42501', null,
  'a non-admin cannot ask for a report''s image');

reset role;
delete from reports where target_id = '4444a216-1a6e-0000-0000-000000000002';
select is(
  (select count(*)::int from direct_message_images where id = (select id from img where k = 'two')),
  0,
  'deleting the report deletes the image it held');

-- ── the sender's account deletion and abandoned uploads ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000a1","role":"authenticated"}';
insert into direct_messages (sender_id, recipient_id, body, image_id)
select 'aaaa1216-1a6e-0000-0000-0000000000a1', 'aaaa1216-1a6e-0000-0000-0000000000b2', 'last', id from img where k = 'three';
reset role;
delete from auth.users where id = 'aaaa1216-1a6e-0000-0000-0000000000a1';
select is(
  (select count(*)::int from direct_message_images where id = (select id from img where k = 'three')),
  0,
  'the sender''s account deletion deletes their sent image');

update direct_message_images set created_at = now() - interval '2 days' where id = (select id from img where k = 'd');
select private.dm_images_housekeeping();
select is(
  (select count(*)::int from direct_message_images where id = (select id from img where k = 'd')),
  0,
  'an upload never sent is deleted after a day');

-- ── the two-year purge takes the photo ──

insert into direct_message_images (id, owner_id, upload_path, storage_path)
values ('5555a216-1a6e-0000-0000-000000000001', 'aaaa1216-1a6e-0000-0000-0000000000b2',
        'aaaa1216-1a6e-0000-0000-0000000000b2/5555a216-1a6e-0000-0000-000000000001/upload',
        'aaaa1216-1a6e-0000-0000-0000000000b2/5555a216-1a6e-0000-0000-000000000001.jpg');
insert into direct_messages (id, sender_id, recipient_id, body, image_id, created_at)
values ('4444a216-1a6e-0000-0000-000000000009', 'aaaa1216-1a6e-0000-0000-0000000000b2',
        'aaaa1216-1a6e-0000-0000-0000000000d4', null, '5555a216-1a6e-0000-0000-000000000001',
        now() - interval '3 years');
select private.purge_stale_direct_messages();
select is(
  (select count(*)::int from direct_message_images where id = '5555a216-1a6e-0000-0000-000000000001'),
  0,
  'the two-year purge deletes the photo with its message');

-- ── withheld column and the waiting-upload cap ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$select upload_path from direct_message_images$$,
  '42501', null,
  'no client reads upload_path');
select lives_ok(
  $$select create_dm_image_upload() from generate_series(1, 10)$$,
  'ten photos can wait to be sent');
select throws_ok(
  $$select * from create_dm_image_upload()$$,
  '54000', null,
  'an eleventh waiting upload is refused');
reset role;

-- ── the gate ──

delete from private.feature_flags where name = 'dm_images';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-1a6e-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$select * from create_dm_image_upload()$$,
  '0A000', null,
  'with the gate closed no upload can start');

select * from finish();
rollback;
