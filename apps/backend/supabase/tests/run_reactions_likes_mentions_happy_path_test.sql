-- Happy-path round trips for 20270826000001 (decisions § 1971), the companion
-- to run_reactions_likes_mentions_test.sql, which pins the gates. Here: a
-- viewer reacts and un-reacts and the summary follows, a comment is liked and
-- unliked and its summary follows, every reactor notifies the owner once with
-- the run as the activity, the logged-out share page reads counts, and a
-- mention reaches a follower on a followers-only run.
--
-- Cast: bob owns the runs, erin follows bob, alice and dave are other runners.

begin;
select plan(15);

insert into private.feature_flags (name, enabled) values ('audience_sharing', true)
  on conflict (name) do update set enabled = true;

do $$
declare
  v_alice uuid := '74000000-0000-0000-0000-00000000aaaa';
  v_bob   uuid := '74000000-0000-0000-0000-00000000bbbb';
  v_erin  uuid := '74000000-0000-0000-0000-00000000eeee';
  v_dave  uuid := '74000000-0000-0000-0000-00000000dddd';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_alice, 'alice-rlh@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_bob, 'bob-rlh@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_erin, 'erin-rlh@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_dave, 'dave-rlh@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier, handle)
    values (v_alice, 'Alice', 'km', 'free', 'alice_rlh'),
           (v_bob,   'Bob',   'km', 'free', 'bob_rlh'),
           (v_erin,  'Erin',  'km', 'free', 'erin_rlh'),
           (v_dave,  'Dave',  'km', 'free', 'dave_rlh')
    on conflict (id) do update set handle = excluded.handle;
  insert into user_follows (follower_id, followee_id) values (v_erin, v_bob);
  insert into runs (id, user_id, started_at, distance_m, duration_s, source,
                    is_public, followers_only, metadata)
    values ('75000000-0000-0000-0000-0000000000b1', v_bob, now(), 5000, 1500, 'app',
            true, false, '{"activity_type":"run"}'),
           ('75000000-0000-0000-0000-0000000000f1', v_bob, now(), 8000, 2400, 'app',
            false, true, '{"activity_type":"run"}');
end $$;

-- ─────────────── reactions: react, un-react, summary follows ───────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
insert into run_reactions (user_id, run_id, reaction)
  values ('74000000-0000-0000-0000-00000000aaaa', '75000000-0000-0000-0000-0000000000b1', 'fire'),
         ('74000000-0000-0000-0000-00000000aaaa', '75000000-0000-0000-0000-0000000000b1', 'strong');
set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000dddd","role":"authenticated"}';
insert into run_reactions (user_id, run_id, reaction)
  values ('74000000-0000-0000-0000-00000000dddd', '75000000-0000-0000-0000-0000000000b1', 'fire');

select results_eq(
  $$ select reaction, reaction_count, viewer_reacted
       from run_reaction_summary('75000000-0000-0000-0000-0000000000b1') order by reaction $$,
  $$ values ('fire'::text, 2::bigint, true), ('strong', 1::bigint, false) $$,
  'two reactors on one key count together, and the caller''s own key is flagged'
);

set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
select lives_ok(
  $$ delete from run_reactions
      where user_id = '74000000-0000-0000-0000-00000000aaaa'
        and run_id = '75000000-0000-0000-0000-0000000000b1'
        and reaction = 'fire' $$,
  'alice un-reacts'
);
select results_eq(
  $$ select reaction, reaction_count, viewer_reacted
       from run_reaction_summary('75000000-0000-0000-0000-0000000000b1') order by reaction $$,
  $$ values ('fire'::text, 1::bigint, false), ('strong', 1::bigint, true) $$,
  'after un-reacting the count drops by one and the caller''s flag clears on that key only'
);

set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000dddd","role":"authenticated"}';
delete from run_reactions
 where user_id = '74000000-0000-0000-0000-00000000dddd'
   and run_id = '75000000-0000-0000-0000-0000000000b1';
select results_eq(
  $$ select reaction, reaction_count, viewer_reacted
       from run_reaction_summary('75000000-0000-0000-0000-0000000000b1') order by reaction $$,
  $$ values ('strong'::text, 1::bigint, false) $$,
  'a key whose last reaction is removed drops out of the summary'
);

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select results_eq(
  $$ select reaction, reaction_count, viewer_reacted
       from run_reaction_summary('75000000-0000-0000-0000-0000000000b1') order by reaction $$,
  $$ values ('strong'::text, 1::bigint, false) $$,
  'the logged-out share page reads the counts, with no viewer flag set'
);

set local role service_role;
select results_eq(
  $$ select actor_id, activity_kind, activity_id
       from notifications
      where user_id = '74000000-0000-0000-0000-00000000bbbb'
        and kind = 'reaction'
        and run_id = '75000000-0000-0000-0000-0000000000b1'
      order by actor_id $$,
  $$ values ('74000000-0000-0000-0000-00000000aaaa'::uuid, 'run'::text,
             '75000000-0000-0000-0000-0000000000b1'::uuid),
            ('74000000-0000-0000-0000-00000000dddd'::uuid, 'run'::text,
             '75000000-0000-0000-0000-0000000000b1'::uuid) $$,
  'each reactor notifies the run owner once, with the run as the activity'
);

-- ─────────────── comment likes: like, unlike, summary follows ───────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000dddd","role":"authenticated"}';
insert into run_comments (id, run_id, author_id, body)
  values ('76000000-0000-0000-0000-0000000000d1', '75000000-0000-0000-0000-0000000000b1',
          '74000000-0000-0000-0000-00000000dddd', 'negative split, nice');

set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
insert into run_comment_likes (user_id, comment_id)
  values ('74000000-0000-0000-0000-00000000aaaa', '76000000-0000-0000-0000-0000000000d1');
set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000eeee","role":"authenticated"}';
insert into run_comment_likes (user_id, comment_id)
  values ('74000000-0000-0000-0000-00000000eeee', '76000000-0000-0000-0000-0000000000d1');

set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
select results_eq(
  $$ select comment_id, like_count, viewer_liked
       from run_comment_like_summary('75000000-0000-0000-0000-0000000000b1') $$,
  $$ values ('76000000-0000-0000-0000-0000000000d1'::uuid, 2::bigint, true) $$,
  'two likes on one comment count together and the caller''s own is flagged'
);
select lives_ok(
  $$ delete from run_comment_likes
      where user_id = '74000000-0000-0000-0000-00000000aaaa'
        and comment_id = '76000000-0000-0000-0000-0000000000d1' $$,
  'alice unlikes the comment'
);
select results_eq(
  $$ select comment_id, like_count, viewer_liked
       from run_comment_like_summary('75000000-0000-0000-0000-0000000000b1') $$,
  $$ values ('76000000-0000-0000-0000-0000000000d1'::uuid, 1::bigint, false) $$,
  'after unliking the count drops by one and the caller''s flag clears'
);
select is(
  (select count(*)::int from run_comment_likes
    where comment_id = '76000000-0000-0000-0000-0000000000d1'
      and user_id = '74000000-0000-0000-0000-00000000eeee'),
  1,
  'unliking leaves another runner''s like on the same comment alone'
);

insert into run_comment_likes (user_id, comment_id)
  values ('74000000-0000-0000-0000-00000000aaaa', '76000000-0000-0000-0000-0000000000d1');
set local role service_role;
select results_eq(
  $$ select actor_id, count(*)::int
       from notifications
      where user_id = '74000000-0000-0000-0000-00000000dddd'
        and kind = 'comment_like'
        and comment_id = '76000000-0000-0000-0000-0000000000d1'
      group by actor_id order by actor_id $$,
  $$ values ('74000000-0000-0000-0000-00000000aaaa'::uuid, 1),
            ('74000000-0000-0000-0000-00000000eeee'::uuid, 1) $$,
  'each liker notifies the comment author once, and a like-unlike-like does not re-notify'
);
select is(
  (select run_id from notifications
    where user_id = '74000000-0000-0000-0000-00000000dddd'
      and kind = 'comment_like'
      and actor_id = '74000000-0000-0000-0000-00000000eeee'),
  '75000000-0000-0000-0000-0000000000b1'::uuid,
  'a comment-like notification carries the run, so every channel can link to it'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000eeee","role":"authenticated"}';
delete from run_comment_likes where user_id = '74000000-0000-0000-0000-00000000eeee';
set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
delete from run_comment_likes where user_id = '74000000-0000-0000-0000-00000000aaaa';
select is(
  (select count(*)::int from run_comment_like_summary('75000000-0000-0000-0000-0000000000b1')),
  0,
  'a comment whose last like is removed drops out of the summary'
);

-- ─────────────── mentions on a followers-only run ───────────────

set local "request.jwt.claims" = '{"sub":"74000000-0000-0000-0000-00000000bbbb","role":"authenticated"}';
insert into run_comments (id, run_id, author_id, body)
  values ('76000000-0000-0000-0000-0000000000f1', '75000000-0000-0000-0000-0000000000f1',
          '74000000-0000-0000-0000-00000000bbbb', 'tempo again Thursday? @Erin_RLH @alice_rlh');

set local role service_role;
select results_eq(
  $$ select actor_id, run_id, activity_kind, activity_id
       from notifications
      where user_id = '74000000-0000-0000-0000-00000000eeee'
        and kind = 'mention'
        and comment_id = '76000000-0000-0000-0000-0000000000f1' $$,
  $$ values ('74000000-0000-0000-0000-00000000bbbb'::uuid,
             '75000000-0000-0000-0000-0000000000f1'::uuid,
             'run'::text,
             '75000000-0000-0000-0000-0000000000f1'::uuid) $$,
  'a follower mentioned on a followers-only run is notified, pointing at the run'
);
select is(
  (select count(*)::int from notifications
    where user_id = '74000000-0000-0000-0000-00000000aaaa'
      and kind = 'mention'
      and comment_id = '76000000-0000-0000-0000-0000000000f1'),
  0,
  'control: a non-follower in the same comment is outside that audience'
);

select * from finish();
rollback;
