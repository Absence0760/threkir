-- Pins migration 20271115002382 (issue #1215 Phase 2, decisions § 2382): an
-- athlete sends a change to a coach-assigned plan to that coach, and the
-- coach approves (all or some lines) or declines it.
--
--   * only the plan's owner proposes, only on a plan an ACTIVE coach assigned,
--     and a proposal the apply checks would refuse is refused at once, with
--     nothing written to the plan by the dry run;
--   * the request is readable by its athlete and coach and nobody else, and
--     no client writes the table directly;
--   * only the request's coach decides, only while pending and only while the
--     link is active; approving a subset applies exactly that subset;
--   * a newer proposal withdraws the older pending one;
--   * the athlete may withdraw, or apply it themselves (the coach is told);
--   * each step leaves the notification it promises.

begin;
select plan(38);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('d6d6d6d6-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'pcr-athlete@pcr.local', '', now(), now()),
  ('d6d6d6d6-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'pcr-coach@pcr.local', '', now(), now()),
  ('d6d6d6d6-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'pcr-other@pcr.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('d6d6d6d6-0000-0000-0000-0000000000a1', 'PCR athlete'),
  ('d6d6d6d6-0000-0000-0000-0000000000c1', 'PCR coach'),
  ('d6d6d6d6-0000-0000-0000-0000000000b1', 'PCR other')
on conflict (id) do nothing;
insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('d6d6d6d6-0000-0000-0000-0000000000c1', 'd6d6d6d6-0000-0000-0000-0000000000a1', 'active', 'pcr-tok', now());

-- P: assigned by the coach. Q: the athlete's own, later block with no coach.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, assigned_by_coach_id) values
  ('d6d6d6d6-1111-0000-0000-000000000001', 'd6d6d6d6-0000-0000-0000-0000000000a1', 'P', 'distance_half', 21097,
   current_date, current_date + 13, 4, 'active', 'd6d6d6d6-0000-0000-0000-0000000000c1'),
  ('d6d6d6d6-1111-0000-0000-000000000002', 'd6d6d6d6-0000-0000-0000-0000000000a1', 'Q', 'distance_10k', 10000,
   current_date + 20, current_date + 26, 4, 'active', null);

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('d6d6d6d6-2222-0000-0000-000000000000', 'd6d6d6d6-1111-0000-0000-000000000001', 0, 'build', 30000),
  ('d6d6d6d6-2222-0000-0000-000000000001', 'd6d6d6d6-1111-0000-0000-000000000001', 1, 'build', 30000),
  ('d6d6d6d6-2222-0000-0000-000000000010', 'd6d6d6d6-1111-0000-0000-000000000002', 0, 'build', 20000);

insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m) values
  ('d6d6d6d6-3333-0000-0000-000000000001', 'd6d6d6d6-2222-0000-0000-000000000000', current_date + 1, 'easy', 10000),
  ('d6d6d6d6-3333-0000-0000-000000000002', 'd6d6d6d6-2222-0000-0000-000000000000', current_date + 2, 'easy', 8000),
  ('d6d6d6d6-3333-0000-0000-000000000003', 'd6d6d6d6-2222-0000-0000-000000000001', current_date + 8, 'easy', 6000),
  ('d6d6d6d6-3333-0000-0000-000000000010', 'd6d6d6d6-2222-0000-0000-000000000010', current_date + 21, 'easy', 6000);

create function pg_temp.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end;
$$;
grant execute on function pg_temp.as_user(text) to authenticated;

-- The two-line change every proposal below sends.
create function pg_temp.two_lines() returns jsonb language sql as $$
  select '[{"id":"d6d6d6d6-3333-0000-0000-000000000001","target_distance_m":9000},
           {"id":"d6d6d6d6-3333-0000-0000-000000000002","target_distance_m":7000}]'::jsonb;
$$;
grant execute on function pg_temp.two_lines() to authenticated;

create function pg_temp.pending_id() returns uuid language sql security definer as $$
  select id from plan_change_requests
  where plan_id = 'd6d6d6d6-1111-0000-0000-000000000001' and status = 'pending';
$$;
grant execute on function pg_temp.pending_id() to authenticated;

set local role authenticated;

-- 1. The athlete proposes; nothing is applied yet.
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000001', current_date, false,
       pg_temp.two_lines(), '[{"id":"d6d6d6d6-2222-0000-0000-000000000000","target_volume_m":27000}]'::jsonb) $$,
  'the athlete proposes a change to the plan their coach assigned'
);
select is(
  (select (status, jsonb_array_length(workouts), jsonb_array_length(weeks))::text
   from plan_change_requests where plan_id = 'd6d6d6d6-1111-0000-0000-000000000001'),
  '(pending,2,1)',
  'the athlete reads back their pending request with its two workout lines and one week'
);
select is(
  (select target_distance_m from plan_workouts where id = 'd6d6d6d6-3333-0000-0000-000000000001'),
  10000.00,
  'the dry run wrote nothing to the plan'
);
reset role;
select is(
  (select count(*)::int from notifications
   where user_id = 'd6d6d6d6-0000-0000-0000-0000000000c1' and kind = 'plan_change_request'
     and actor_id = 'd6d6d6d6-0000-0000-0000-0000000000a1' and read_at is null),
  1,
  'the coach has one unread plan_change_request notification'
);

-- 2. Who may propose, and what.
set local role authenticated;
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000a1');
select throws_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000002', current_date, false,
       '[{"id":"d6d6d6d6-3333-0000-0000-000000000010","target_distance_m":5000}]'::jsonb, '[]'::jsonb) $$,
  '42501', 'propose_plan_change: the plan has no coach you are linked with',
  'a plan no coach assigned has nobody to send a change to'
);
select throws_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000001', current_date, false,
       '[{"id":"d6d6d6d6-3333-0000-0000-000000000001","target_distance_m":20000}]'::jsonb, '[]'::jsonb) $$,
  '22023', null,
  'a change the apply checks refuse (double the distance) is refused when proposed'
);
select throws_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000001', current_date, false,
       '[]'::jsonb, '[]'::jsonb) $$,
  '22023', 'propose_plan_change: nothing to change',
  'an empty change is refused'
);
select is(
  (select count(*)::int from plan_change_requests where plan_id = 'd6d6d6d6-1111-0000-0000-000000000001'),
  1,
  'the refused proposals filed no request: the athlete still reads only the first'
);
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000b1');
select throws_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000001', current_date, false,
       pg_temp.two_lines(), '[]'::jsonb) $$,
  'P0002', null,
  'someone else cannot propose a change to the athlete''s plan'
);

-- 3. Visibility: the coach reads it, a third person does not.
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000c1');
select is(
  (select count(*)::int from plan_change_requests where plan_id = 'd6d6d6d6-1111-0000-0000-000000000001'),
  1,
  'the coach reads the request'
);
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000b1');
select is(
  (select count(*)::int from plan_change_requests where plan_id = 'd6d6d6d6-1111-0000-0000-000000000001'),
  0,
  'a third person cannot read the request'
);
select throws_ok(
  $$ insert into plan_change_requests (plan_id, athlete_id, coach_id)
     values ('d6d6d6d6-1111-0000-0000-000000000001', 'd6d6d6d6-0000-0000-0000-0000000000a1',
             'd6d6d6d6-0000-0000-0000-0000000000b1') $$,
  '42501', null,
  'no client inserts a request directly'
);
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000a1');
select throws_ok(
  $$ update plan_change_requests set status = 'approved', decided_at = now()
     where plan_id = 'd6d6d6d6-1111-0000-0000-000000000001' $$,
  '42501', null,
  'the athlete cannot approve their own request by writing the row'
);

-- 4. Only the coach decides.
select throws_ok(
  $$ select decide_plan_change(pg_temp.pending_id(), true, current_date) $$,
  'P0002', null,
  'the athlete cannot decide their own request'
);
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000b1');
select throws_ok(
  $$ select decide_plan_change(pg_temp.pending_id(), true, current_date) $$,
  'P0002', null,
  'a third person cannot decide the request'
);

-- 5. A newer proposal withdraws the older one.
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000001', current_date, false,
       pg_temp.two_lines(), '[]'::jsonb) $$,
  'the athlete sends a newer change'
);
select is(
  (select string_agg(status, ',' order by created_at, status) from plan_change_requests
   where plan_id = 'd6d6d6d6-1111-0000-0000-000000000001'),
  'pending,withdrawn',
  'the older request is withdrawn and the newer one is the only one pending'
);
reset role;
select is(
  (select count(*)::int from notifications
   where user_id = 'd6d6d6d6-0000-0000-0000-0000000000c1' and kind = 'plan_change_request' and read_at is null),
  1,
  'the coach still has one unread notification, refreshed rather than repeated'
);

-- 6. The coach approves one line of two.
set local role authenticated;
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000c1');
select throws_ok(
  $$ select decide_plan_change(pg_temp.pending_id(), true, current_date,
       array['d6d6d6d6-3333-0000-0000-000000000003']::uuid[], array[]::uuid[]) $$,
  '22023', 'decide_plan_change: a chosen workout is not in the request',
  'the coach cannot approve a line the request does not hold'
);
select lives_ok(
  $$ select decide_plan_change(pg_temp.pending_id(), true, current_date,
       array['d6d6d6d6-3333-0000-0000-000000000001']::uuid[], null, 'Keep Tuesday as it is.') $$,
  'the coach approves one of the two lines'
);
select is(
  (select (target_distance_m)::text from plan_workouts where id = 'd6d6d6d6-3333-0000-0000-000000000001'),
  '9000.00',
  'the approved line is applied to the athlete''s plan'
);
select is(
  (select (target_distance_m)::text from plan_workouts where id = 'd6d6d6d6-3333-0000-0000-000000000002'),
  '8000.00',
  'the line the coach left out is not'
);
select is(
  (select (status, edited_by_coach, jsonb_array_length(workouts), coach_note)::text from plan_change_requests
   where plan_id = 'd6d6d6d6-1111-0000-0000-000000000001' and status = 'approved'),
  '(approved,t,1,"Keep Tuesday as it is.")',
  'the request records the approval, the edit, the applied line and the note'
);
select throws_ok(
  $$ select decide_plan_change(
       (select id from plan_change_requests where status = 'approved'
          and plan_id = 'd6d6d6d6-1111-0000-0000-000000000001'), false, current_date) $$,
  '22023', 'decide_plan_change: the request is no longer pending',
  'a decided request cannot be decided again'
);
reset role;
select is(
  (select count(*)::int from notifications
   where user_id = 'd6d6d6d6-0000-0000-0000-0000000000a1' and kind = 'plan_change_decision'
     and actor_id = 'd6d6d6d6-0000-0000-0000-0000000000c1'),
  1,
  'the athlete is told the coach decided'
);

-- 7. Decline applies nothing.
set local role authenticated;
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000001', current_date, false,
       '[{"id":"d6d6d6d6-3333-0000-0000-000000000002","target_distance_m":7000}]'::jsonb, '[]'::jsonb) $$,
  'the athlete proposes again'
);
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000c1');
select lives_ok(
  $$ select decide_plan_change(pg_temp.pending_id(), false, current_date, null, null, 'Not this week.') $$,
  'the coach declines'
);
select is(
  (select (target_distance_m)::text from plan_workouts where id = 'd6d6d6d6-3333-0000-0000-000000000002'),
  '8000.00',
  'a declined change leaves the plan as it was'
);

-- 8. The athlete withdraws; the coach's unread notice goes with it.
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000001', current_date, false,
       '[{"id":"d6d6d6d6-3333-0000-0000-000000000002","target_distance_m":7000}]'::jsonb, '[]'::jsonb) $$,
  'the athlete proposes once more'
);
select lives_ok($$ select withdraw_plan_change(pg_temp.pending_id()) $$, 'the athlete withdraws it');
reset role;
select is(
  (select count(*)::int from notifications
   where user_id = 'd6d6d6d6-0000-0000-0000-0000000000c1' and kind = 'plan_change_request' and read_at is null),
  0,
  'withdrawing removes the coach''s unread notice'
);

-- 9. The athlete applies it themselves; the coach is told.
set local role authenticated;
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000001', current_date, false,
       '[{"id":"d6d6d6d6-3333-0000-0000-000000000002","target_distance_m":7000}]'::jsonb, '[]'::jsonb) $$,
  'the athlete proposes a last time'
);
select lives_ok(
  $$ select apply_plan_change_myself(pg_temp.pending_id(), current_date) $$,
  'the athlete applies it without the coach'
);
select is(
  (select (target_distance_m)::text from plan_workouts where id = 'd6d6d6d6-3333-0000-0000-000000000002'),
  '7000.00',
  'the athlete''s own apply writes the change'
);
reset role;
select is(
  (select count(*)::int from notifications
   where user_id = 'd6d6d6d6-0000-0000-0000-0000000000c1' and kind = 'plan_ai_edit'
     and plan_id = 'd6d6d6d6-1111-0000-0000-000000000001'),
  1,
  'the coach is told the athlete applied it'
);

-- 10. An ended link stops proposals and decisions.
set local role authenticated;
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select propose_plan_change('d6d6d6d6-1111-0000-0000-000000000001', current_date, false,
       '[{"id":"d6d6d6d6-3333-0000-0000-000000000003","target_distance_m":5000}]'::jsonb, '[]'::jsonb) $$,
  'a request is pending when the link ends'
);
select is(
  (select (status, include_following)::text from plan_change_requests
   where plan_id = 'd6d6d6d6-1111-0000-0000-000000000001' and status = 'pending'),
  '(pending,f)',
  'the athlete reads the new request back as pending, block-only'
);
reset role;
update coach_athletes set status = 'ended', ended_at = now()
where coach_id = 'd6d6d6d6-0000-0000-0000-0000000000c1' and athlete_id = 'd6d6d6d6-0000-0000-0000-0000000000a1';
set local role authenticated;
select pg_temp.as_user('d6d6d6d6-0000-0000-0000-0000000000c1');
select throws_ok(
  $$ select decide_plan_change(pg_temp.pending_id(), true, current_date) $$,
  '42501', 'decide_plan_change: you no longer coach this athlete',
  'a coach whose link has ended cannot approve'
);

select * from finish();
rollback;
