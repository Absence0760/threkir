-- Pins the claim migration 20270807000001 makes about Art 20 / Art 17: a
-- run-less host photo needs no new export or erasure code, because both paths
-- key on `owner_id` and never on the run.
--   * export: export-data's backup_spec and the worker's exportPersonalDataSpecs
--     both read `run_photos.json` as `owner_id=eq.<uid>` with the service role,
--     and collect each row's `storage_path` for the photo bytes;
--   * erasure: the row cascades with `owner_id`, and delete-account drains the
--     `run-photos` bucket by the `{owner_id}/` prefix, which the
--     storage_path_shape CHECK makes every row's path start with.
-- A run-less row is the case those paths were not written for, and the one an
-- event deletion detaches (`event_id` set null) — so both shapes are held here.

begin;
select plan(8);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('99999999-9999-9999-9999-99991151a001', 'org-1151@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991151a002', 'host-1151@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values ('dddddddd-0000-0000-0000-00000001151c',
        '99999999-9999-9999-9999-99991151a001',
        'Host Photo Club 1151', 'host-photo-club-1151', true, 'open');

insert into events (id, club_id, title, starts_at, author_id, host_user_id)
values
  ('eeeeeeee-0000-0000-0000-0000000115f1',
   'dddddddd-0000-0000-0000-00000001151c',
   'Kept 10K', '2026-06-20T08:00:00Z',
   '99999999-9999-9999-9999-99991151a001',
   '99999999-9999-9999-9999-99991151a002'),
  ('eeeeeeee-0000-0000-0000-0000000115f2',
   'dddddddd-0000-0000-0000-00000001151c',
   'Deleted 5K', '2026-06-21T08:00:00Z',
   '99999999-9999-9999-9999-99991151a001',
   '99999999-9999-9999-9999-99991151a002');

-- The host posts one run-less photo to each event, through RLS.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991151a002","role":"authenticated"}';

insert into run_photos (id, owner_id, storage_path, event_id, event_instance_start)
values
  ('11111111-0000-0000-0000-0000001151b1',
   '99999999-9999-9999-9999-99991151a002',
   '99999999-9999-9999-9999-99991151a002/kept.jpg',
   'eeeeeeee-0000-0000-0000-0000000115f1', '2026-06-20T08:00:00Z'),
  ('11111111-0000-0000-0000-0000001151b2',
   '99999999-9999-9999-9999-99991151a002',
   '99999999-9999-9999-9999-99991151a002/detached.jpg',
   'eeeeeeee-0000-0000-0000-0000000115f2', '2026-06-21T08:00:00Z');

reset role;

-- As the table owner, so the refusal is the CHECK itself and not an RLS policy.
select throws_ok($$
  insert into run_photos (owner_id, storage_path, event_id, event_instance_start)
  values ('99999999-9999-9999-9999-99991151a002',
          'elsewhere/host.jpg',
          'eeeeeeee-0000-0000-0000-0000000115f1', '2026-06-20T08:00:00Z')
$$, '23514', null,
  'a run-less photo outside the owner''s prefix is refused, so the prefix drain reaches every one');

-- Deleting an event detaches its host photos rather than removing them.
delete from events where id = 'eeeeeeee-0000-0000-0000-0000000115f2';

select is(
  (select event_id from run_photos where id = '11111111-0000-0000-0000-0000001151b2'),
  null, 'deleting the event detaches its host photo and keeps the row');

-- ── Art 20: the export's own query, as the role it runs under ──
set local role service_role;

select is(
  (select array_agg(id::text order by id)
     from run_photos where owner_id = '99999999-9999-9999-9999-99991151a002'),
  array['11111111-0000-0000-0000-0000001151b1', '11111111-0000-0000-0000-0000001151b2'],
  'run_photos.json (owner_id=eq.<uid>) carries the host''s run-less photos, detached one included');

select is(
  (select count(*)::int from run_photos
    where owner_id = '99999999-9999-9999-9999-99991151a002' and run_id is null),
  2, 'both exported rows are the run-less shape');

select is(
  (select count(*)::int from run_photos
    where owner_id = '99999999-9999-9999-9999-99991151a002'
      and storage_path not like '99999999-9999-9999-9999-99991151a002/%'),
  0, 'every exported storage_path sits under the owner prefix the export and the drain both walk');

select is(
  (select count(*)::int from run_photos
    where owner_id = '99999999-9999-9999-9999-99991151a001'),
  0, 'the organiser''s export carries none of the host''s photos on their club''s events');

-- ── Art 17: deleting the host erases the rows ──
reset role;
delete from auth.users where id = '99999999-9999-9999-9999-99991151a002';

select is(
  (select count(*)::int from run_photos
    where id in ('11111111-0000-0000-0000-0000001151b1', '11111111-0000-0000-0000-0000001151b2')),
  0, 'deleting the host cascade-removes their run-less photos, detached one included');

select is(
  (select count(*)::int from events where id = 'eeeeeeee-0000-0000-0000-0000000115f1'
      and host_user_id is null),
  1, 'the event outlives its host''s erasure, with the host detached');

select * from finish();
rollback;
