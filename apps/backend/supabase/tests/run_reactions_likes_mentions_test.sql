-- Pins 20270826000001 (decisions § 1971): run reactions, comment likes and
-- comment @mentions.
--
-- Every write gate is driven through a real authenticated JWT, not by calling
-- the helper, because § 158's lesson was a block predicate that passed its own
-- helper test while the policy around it admitted every cross-user write.
--
-- Cast: alice reacts / likes / mentions, bob owns the runs, carol is the one
-- mentioned, dave is a bystander.

begin;
select plan(37);

do $$
declare
  v_alice uuid := '71000000-0000-0000-0000-00000000aaaa';
  v_bob   uuid := '71000000-0000-0000-0000-00000000bbbb';
  v_carol uuid := '71000000-0000-0000-0000-00000000cccc';
  v_dave  uuid := '71000000-0000-0000-0000-00000000dddd';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_alice, 'alice-rlm@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_bob, 'bob-rlm@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_carol, 'carol-rlm@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_dave, 'dave-rlm@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier, handle)
    values (v_alice, 'Alice', 'km', 'free', 'alice_rlm'),
           (v_bob,   'Bob',   'km', 'free', 'bob_rlm'),
           (v_carol, 'Carol', 'km', 'free', 'carol_rlm'),
           (v_dave,  'Dave',  'km', 'free', 'dave_rlm')
    on conflict (id) do update set handle = excluded.handle;
  insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
    values ('72000000-0000-0000-0000-0000000000b1', v_bob, now(), 5000, 1500, 'app', true,
            '{"activity_type":"run"}'),
           ('72000000-0000-0000-0000-0000000000b2', v_bob, now(), 5000, 1500, 'app', false,
            '{"activity_type":"run"}');
end $$;

-- ─────────────── extract_mention_handles ───────────────

select is(
  private.extract_mention_handles(
    'hi @Alice and @bob_1, me@example.com @al (@carol) @@dave @alice @'
    || repeat('x', 31) || ' @abc@def'),
  array['alice', 'bob_1', 'carol', 'abc'],
  'mentions: lowercased, de-duplicated in first-seen order; email, 2-char, '
  'doubled @, 31-char and glued handles are not mentions'
);
select is(
  array_length(private.extract_mention_handles(
    '@aaa1 @aaa2 @aaa3 @aaa4 @aaa5 @aaa6 @aaa7 @aaa8 @aaa9 @aaa10 @aaa11'), 1),
  10,
  'at most ten handles are taken from one comment'
);
select is(private.extract_mention_handles(null), '{}'::text[], 'a null body mentions nobody');

-- ─────────────── reactions ───────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';

select lives_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000aaaa', '72000000-0000-0000-0000-0000000000b1', 'fire') $$,
  'alice can react to bob''s public run'
);
select lives_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000aaaa', '72000000-0000-0000-0000-0000000000b1', 'strong') $$,
  'alice can leave a second, different reaction on the same run'
);
select throws_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000aaaa', '72000000-0000-0000-0000-0000000000b1', 'fire') $$,
  '23505',
  null,
  'the same reaction twice is a duplicate'
);
select throws_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000aaaa', '72000000-0000-0000-0000-0000000000b1', 'heart_eyes') $$,
  '23514',
  null,
  'a reaction outside the whitelist is refused by the CHECK'
);
select throws_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000aaaa', '72000000-0000-0000-0000-0000000000b2', 'fire') $$,
  '42501',
  null,
  'alice cannot react to bob''s private run'
);
select throws_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000bbbb', '72000000-0000-0000-0000-0000000000b1', 'fire') $$,
  '42501',
  null,
  'alice cannot react on bob''s behalf'
);

set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000bbbb","role":"authenticated"}';
select throws_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000bbbb', '72000000-0000-0000-0000-0000000000b1', 'fire') $$,
  '42501',
  null,
  'bob cannot react to his own run'
);

set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000dddd","role":"authenticated"}';
select results_eq(
  $$ select reaction, reaction_count, viewer_reacted
       from run_reaction_summary('72000000-0000-0000-0000-0000000000b1') order by reaction $$,
  $$ values ('fire'::text, 1::bigint, false), ('strong', 1::bigint, false) $$,
  'run_reaction_summary counts each reaction for a bystander'
);

set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
select is(
  (select bool_and(viewer_reacted) from run_reaction_summary('72000000-0000-0000-0000-0000000000b1')),
  true,
  'run_reaction_summary marks the caller''s own reactions'
);

-- One notification per reactor per run, however many reactions or toggles.
select lives_ok(
  $$ delete from run_reactions
      where user_id = '71000000-0000-0000-0000-00000000aaaa' and reaction = 'fire' $$,
  'alice can remove her own reaction'
);
select lives_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000aaaa', '72000000-0000-0000-0000-0000000000b1', 'fire') $$,
  'and put it back'
);

set local role service_role;
select is(
  (select count(*)::int from notifications
    where user_id = '71000000-0000-0000-0000-00000000bbbb'
      and actor_id = '71000000-0000-0000-0000-00000000aaaa'
      and kind = 'reaction'
      and run_id = '72000000-0000-0000-0000-0000000000b1'),
  1,
  'three reaction inserts by one runner notify the run owner once'
);

-- A reaction on a run the reader cannot see is invisible, summary included.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000bbbb","role":"authenticated"}';
insert into run_comments (id, run_id, author_id, body)
  values ('73000000-0000-0000-0000-0000000000c9', '72000000-0000-0000-0000-0000000000b2',
          '71000000-0000-0000-0000-00000000bbbb', 'private note');
set local role service_role;
insert into run_reactions (user_id, run_id, reaction)
  values ('71000000-0000-0000-0000-00000000dddd', '72000000-0000-0000-0000-0000000000b2', 'wave');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
select is(
  (select count(*)::int from run_reaction_summary('72000000-0000-0000-0000-0000000000b2')),
  0,
  'run_reaction_summary returns nothing for a run the caller cannot read'
);
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select count(*)::int from run_reactions where run_id = '72000000-0000-0000-0000-0000000000b1'),
  2,
  'anon can read reactions on a public run (the logged-out share page)'
);
select is(
  (select count(*)::int from run_reactions where run_id = '72000000-0000-0000-0000-0000000000b2'),
  0,
  'anon cannot read reactions on a private run'
);

-- ─────────────── comment likes ───────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000dddd","role":"authenticated"}';
insert into run_comments (id, run_id, author_id, body)
  values ('73000000-0000-0000-0000-0000000000d1', '72000000-0000-0000-0000-0000000000b1',
          '71000000-0000-0000-0000-00000000dddd', 'great pacing');

set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
select lives_ok(
  $$ insert into run_comment_likes (user_id, comment_id)
       values ('71000000-0000-0000-0000-00000000aaaa', '73000000-0000-0000-0000-0000000000d1') $$,
  'alice can like dave''s comment on a public run'
);
select throws_ok(
  $$ insert into run_comment_likes (user_id, comment_id)
       values ('71000000-0000-0000-0000-00000000aaaa', '73000000-0000-0000-0000-0000000000c9') $$,
  '42501',
  null,
  'alice cannot like a comment on a run she cannot read'
);

set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000dddd","role":"authenticated"}';
select throws_ok(
  $$ insert into run_comment_likes (user_id, comment_id)
       values ('71000000-0000-0000-0000-00000000dddd', '73000000-0000-0000-0000-0000000000d1') $$,
  '42501',
  null,
  'dave cannot like his own comment'
);

select results_eq(
  $$ select comment_id, like_count, viewer_liked
       from run_comment_like_summary('72000000-0000-0000-0000-0000000000b1') $$,
  $$ values ('73000000-0000-0000-0000-0000000000d1'::uuid, 1::bigint, false) $$,
  'run_comment_like_summary counts likes per comment'
);

set local role service_role;
select is(
  (select count(*)::int from notifications
    where user_id = '71000000-0000-0000-0000-00000000dddd'
      and actor_id = '71000000-0000-0000-0000-00000000aaaa'
      and kind = 'comment_like'
      and comment_id = '73000000-0000-0000-0000-0000000000d1'),
  1,
  'a comment like notifies the comment''s author'
);

-- Block gate: dave blocks alice. The run owner (bob) is unrelated, so this is
-- the comment-AUTHOR half of the gate, which kudos never needed.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
delete from run_comment_likes where user_id = '71000000-0000-0000-0000-00000000aaaa';
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000dddd","role":"authenticated"}';
do $$ begin perform block_user('71000000-0000-0000-0000-00000000aaaa'::uuid); end $$;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
select throws_ok(
  $$ insert into run_comment_likes (user_id, comment_id)
       values ('71000000-0000-0000-0000-00000000aaaa', '73000000-0000-0000-0000-0000000000d1') $$,
  '42501',
  null,
  'a block between the liker and the comment''s author denies the like'
);
select throws_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000aaaa', '72000000-0000-0000-0000-0000000000b1', 'strong') $$,
  '23505',
  null,
  'control: alice is not blocked by bob, so only the duplicate key stops her'
);
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000dddd","role":"authenticated"}';
do $$ begin perform unblock_user('71000000-0000-0000-0000-00000000aaaa'::uuid); end $$;

-- Bob (run owner) blocks dave: dave can no longer react to bob's run.
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000bbbb","role":"authenticated"}';
do $$ begin perform block_user('71000000-0000-0000-0000-00000000dddd'::uuid); end $$;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000dddd","role":"authenticated"}';
select throws_ok(
  $$ insert into run_reactions (user_id, run_id, reaction)
       values ('71000000-0000-0000-0000-00000000dddd', '72000000-0000-0000-0000-0000000000b1', 'trophy') $$,
  '42501',
  null,
  'a block between the reactor and the run owner denies the reaction'
);
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000bbbb","role":"authenticated"}';
do $$ begin perform unblock_user('71000000-0000-0000-0000-00000000dddd'::uuid); end $$;

-- ─────────────── mentions ───────────────

set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
insert into run_comments (id, run_id, author_id, body)
  values ('73000000-0000-0000-0000-0000000000a1', '72000000-0000-0000-0000-0000000000b1',
          '71000000-0000-0000-0000-00000000aaaa', 'run this with @Carol_RLM and @bob_rlm next week');

set local role service_role;
select is(
  (select count(*)::int from notifications
    where user_id = '71000000-0000-0000-0000-00000000cccc'
      and kind = 'mention'
      and comment_id = '73000000-0000-0000-0000-0000000000a1'
      and actor_id = '71000000-0000-0000-0000-00000000aaaa'
      and run_id = '72000000-0000-0000-0000-0000000000b1'),
  1,
  'a mention of someone who can read the run notifies them'
);
select is(
  (select array_agg(kind order by kind) from notifications
    where user_id = '71000000-0000-0000-0000-00000000bbbb'
      and comment_id = '73000000-0000-0000-0000-0000000000a1'),
  array['comment'],
  'the run owner mentioned in a top-level comment gets the comment row only'
);

-- Editing the body: a kept mention does not re-notify, an added one does.
set local role authenticated;
update run_comments
   set body = 'run this with @carol_rlm and @dave_rlm next week'
 where id = '73000000-0000-0000-0000-0000000000a1';
set local role service_role;
select is(
  (select count(*)::int from notifications
    where kind = 'mention' and comment_id = '73000000-0000-0000-0000-0000000000a1'),
  2,
  'an edit notifies only the newly added handle'
);

-- A reply that mentions its parent's author: comment_reply only.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000cccc","role":"authenticated"}';
insert into run_comments (id, run_id, author_id, parent_comment_id, body)
  values ('73000000-0000-0000-0000-0000000000a2', '72000000-0000-0000-0000-0000000000b1',
          '71000000-0000-0000-0000-00000000cccc', '73000000-0000-0000-0000-0000000000a1',
          '@alice_rlm count me in, and @bob_rlm too');
set local role service_role;
select is(
  (select array_agg(kind order by kind) from notifications
    where user_id = '71000000-0000-0000-0000-00000000aaaa'
      and comment_id = '73000000-0000-0000-0000-0000000000a2'),
  array['comment_reply'],
  'the parent''s author mentioned in a reply gets the reply row only'
);
select is(
  (select count(*)::int from notifications
    where user_id = '71000000-0000-0000-0000-00000000bbbb'
      and kind = 'mention'
      and comment_id = '73000000-0000-0000-0000-0000000000a2'),
  1,
  'the run owner mentioned in a reply is notified (no other row covers it)'
);

-- Audience gate: bob's own comment on his PRIVATE run mentions carol, who
-- cannot read that run.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000bbbb","role":"authenticated"}';
insert into run_comments (id, run_id, author_id, body)
  values ('73000000-0000-0000-0000-0000000000b9', '72000000-0000-0000-0000-0000000000b2',
          '71000000-0000-0000-0000-00000000bbbb', 'note to self, ask @carol_rlm');
set local role service_role;
select is(
  (select count(*)::int from notifications
    where kind = 'mention' and comment_id = '73000000-0000-0000-0000-0000000000b9'),
  0,
  'a mention on a run outside the mentioned runner''s audience writes no notification'
);

-- Block gate, author side: carol blocks alice, then alice mentions carol.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000cccc","role":"authenticated"}';
do $$ begin perform block_user('71000000-0000-0000-0000-00000000aaaa'::uuid); end $$;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
insert into run_comments (id, run_id, author_id, body)
  values ('73000000-0000-0000-0000-0000000000a3', '72000000-0000-0000-0000-0000000000b1',
          '71000000-0000-0000-0000-00000000aaaa', 'hey @carol_rlm');
set local role service_role;
select is(
  (select count(*)::int from notifications
    where kind = 'mention' and comment_id = '73000000-0000-0000-0000-0000000000a3'),
  0,
  'a block between the mentioned runner and the author suppresses the mention'
);

-- Block gate, owner side: bob blocks dave; alice (unblocked by both) mentions
-- dave on bob's public run.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000bbbb","role":"authenticated"}';
do $$ begin perform block_user('71000000-0000-0000-0000-00000000dddd'::uuid); end $$;
set local "request.jwt.claims" = '{"sub":"71000000-0000-0000-0000-00000000aaaa","role":"authenticated"}';
insert into run_comments (id, run_id, author_id, body)
  values ('73000000-0000-0000-0000-0000000000a4', '72000000-0000-0000-0000-0000000000b1',
          '71000000-0000-0000-0000-00000000aaaa', 'hey @dave_rlm');
set local role service_role;
select is(
  (select count(*)::int from notifications
    where kind = 'mention' and comment_id = '73000000-0000-0000-0000-0000000000a4'),
  0,
  'a block between the mentioned runner and the run owner suppresses the mention'
);

-- ─────────────── cascade + grants ───────────────

delete from run_comments where id = '73000000-0000-0000-0000-0000000000d1';
select is(
  (select count(*)::int from run_comment_likes where comment_id = '73000000-0000-0000-0000-0000000000d1'),
  0,
  'deleting a comment removes its likes'
);
select ok(
  not has_function_privilege('authenticated', 'private.extract_mention_handles(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.extract_mention_handles(text)', 'EXECUTE'),
  'the mention parser is reachable only from the definer trigger'
);
select ok(
  not has_function_privilege('anon', 'private.can_like_run_comment(uuid, uuid)', 'EXECUTE'),
  'anon cannot execute the like gate'
);

select * from finish();
rollback;
