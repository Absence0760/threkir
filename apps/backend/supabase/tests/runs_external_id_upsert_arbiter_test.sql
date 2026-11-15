-- Pins 20271231002548 + 20271231012548 (decisions § 2548): the client upsert
-- of an imported run, `on_conflict=user_id,external_id`, has an arbiter.
--
-- The partial index it replaced could not be inferred from a conflict target
-- with no WHERE, which is the only shape PostgREST sends, so every mobile push
-- of an imported run raised 42P10 and the run never left the phone. The
-- statements below are the ones PostgREST builds for that upsert.

begin;
select plan(7);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values ('99999999-9999-9999-9999-99999999a548', 'extid-upsert@example.com', '',
        now(), '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated')
on conflict (id) do nothing;

select lives_ok(
  $$insert into runs (user_id, started_at, distance_m, duration_s, source,
                      external_id, metadata)
    values ('99999999-9999-9999-9999-99999999a548', '2026-11-14 12:00:08+00',
            42324.64, 15506, 'healthconnect', 'healthconnect:upsert-1',
            '{"activity_type":"run"}')
    on conflict (user_id, external_id) do update
      set distance_m = excluded.distance_m$$,
  'An imported run upserts on (user_id, external_id) without 42P10'
);

select lives_ok(
  $$insert into runs (user_id, started_at, distance_m, duration_s, source,
                      external_id, metadata)
    values ('99999999-9999-9999-9999-99999999a548', '2026-11-14 12:00:08+00',
            42330, 15506, 'healthconnect', 'healthconnect:upsert-1',
            '{"activity_type":"run"}')
    on conflict (user_id, external_id) do update
      set distance_m = excluded.distance_m$$,
  'Re-pushing the same import takes the update branch'
);

select is(
  (select count(*) from runs
    where user_id = '99999999-9999-9999-9999-99999999a548'
      and external_id = 'healthconnect:upsert-1'),
  1::bigint,
  'The re-push updated the row rather than adding a second one'
);

select is(
  (select distance_m from runs
    where user_id = '99999999-9999-9999-9999-99999999a548'
      and external_id = 'healthconnect:upsert-1'),
  42330::numeric,
  'The update branch wrote the re-pushed value'
);

select is(
  (select metadata from runs
    where user_id = '99999999-9999-9999-9999-99999999a548'
      and external_id = 'healthconnect:upsert-1'),
  '{"activity_type":"run"}'::jsonb,
  'The upserted run stores the metadata it was given'
);

insert into runs (user_id, started_at, distance_m, duration_s, source, metadata)
values ('99999999-9999-9999-9999-99999999a548', '2026-11-15 09:00:00+00',
        5000, 1500, 'app', '{"activity_type":"run"}'),
       ('99999999-9999-9999-9999-99999999a548', '2026-11-15 10:00:00+00',
        5000, 1500, 'app', '{"activity_type":"run"}');

select is(
  (select count(*) from runs
    where user_id = '99999999-9999-9999-9999-99999999a548'
      and external_id is null),
  2::bigint,
  'Runs with no external_id never collide on the non-partial index'
);

select is(
  (select count(*) from pg_indexes
    where schemaname = 'public' and tablename = 'runs'
      and indexdef ilike '%(user_id, external_id)%'
      and indexdef ilike '%where%'),
  0::bigint,
  'No partial (user_id, external_id) index is left for a later change to rely on'
);

select * from finish();
rollback;
