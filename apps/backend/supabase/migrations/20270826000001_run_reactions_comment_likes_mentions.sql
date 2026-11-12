-- Reactions on runs, likes on run comments, and @mentions in run comments
-- (issue #1168 item 7, decisions § 1971, reversing the "defer" in § 32).
--
-- 1. run_reactions — a SIBLING of run_kudos, not a widened run_kudos. § 32's
--    "don't re-litigate" note sketched a `reaction` column on run_kudos with
--    the PK widened to (user_id, run_id, reaction); that would make every kudos
--    count in the product (feed, digest, recap, export, run_engagement_counts)
--    start counting reactions too, and every kudos reader would need a
--    `reaction = 'kudos'` filter forever — the polymorphic-table cost § 32
--    already rejected for kudos vs comments. Kudos stay the one-tap yes/no;
--    a reaction is a second, optional signal next to it.
--
--    The vocabulary is a fixed whitelist of stable string keys, never emoji
--    literals (the repo carries no emoji in source); clients render each key
--    with an icon. A runner may leave several different reactions on one run
--    and each at most once: PK (user_id, run_id, reaction).
--
-- 2. run_comment_likes — a one-tap heart on a comment or reply. PK
--    (user_id, comment_id) so a like is idempotent.
--
-- 3. Mentions — `@handle` in a comment body, using the § 269 handle rules
--    (lowercase-canonical, [a-z0-9_]{3,30}). No schema: the body stays plain
--    text (§ 32) and the parse happens in a trigger that writes a `mention`
--    notification. The mentioned runner is notified only when they could
--    already read the run (private.is_run_visible_to, the same audience every
--    other run surface answers to) and no block stands either way between
--    them and the comment's author or the run's owner — a mention must not be
--    a way to push a run, or a harasser's name, at someone the audience or a
--    block keeps it from.
--
-- Block gates follow § 158: the run owner / comment author is resolved inside
-- a SECURITY DEFINER predicate, never an RLS-visible subquery, because a
-- non-owner cannot see the base `runs` row and the subquery would read NULL
-- and admit every write.
--
-- Notifications: three new kinds — `reaction` (to the run owner),
-- `comment_like` (to the comment author) and `mention` (to the mentioned
-- runner). Each is de-duplicated per (recipient, actor, target) with a
-- NOT EXISTS against indexes notifications already carries
-- (notifications_run_id, notifications_comment_id), so toggling a reaction off
-- and on, or editing a comment that keeps its mentions, does not re-notify.
-- No new index is built on the populated notifications table.
--
-- The kind list is re-emitted whole, so it carries `follow_request` from the
-- private-profile migration (20270822000001) that sorts before this one.
-- The notifications_kind_check widen is the DROP + ADD ... NOT VALID half only;
-- its VALIDATE is 20270826000002 in its own transaction
-- (docs/backend/migration_locks.md § CHECK constraints).

-- ─────────────── 1. run_reactions ───────────────

create table public.run_reactions (
  user_id    uuid not null references auth.users(id) on delete cascade,
  run_id     uuid not null references public.runs(id) on delete cascade,
  reaction   text not null,
  reacted_at timestamptz not null default now(),
  primary key (user_id, run_id, reaction),
  constraint run_reactions_reaction_check
    check (reaction in ('fire', 'strong', 'trophy', 'thumbs_up', 'wave'))
);

create index run_reactions_run_id on public.run_reactions (run_id, reacted_at desc);

comment on table public.run_reactions is
  'Optional reactions on a run beside kudos (decisions § 1971). Visibility, '
  'block gate and cascade mirror run_kudos.';

alter table public.run_reactions enable row level security;

create policy "reactions readable when run is readable"
  on public.run_reactions for select
  to anon, authenticated
  using (private.is_run_visible_to(run_id, (select auth.uid())));

-- Self-reaction is refused like self-kudos. The owner can read their own run
-- under runs RLS, so a plain subquery is the right instrument here — it is
-- the cross-user block check that needs the definer predicate.
create policy "users react on their own behalf"
  on public.run_reactions for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and private.is_run_visible_to(run_id, (select auth.uid()))
    and not private.is_blocked_for_run((select auth.uid()), run_id)
    and not exists (
      select 1 from public.runs r
       where r.id = run_reactions.run_id
         and r.user_id = (select auth.uid())
    )
  );

create policy "users remove their own reactions"
  on public.run_reactions for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.run_reactions from public, anon, authenticated;
grant select on table public.run_reactions to anon, authenticated;
grant insert, delete on table public.run_reactions to authenticated;
grant select, insert, update, delete on table public.run_reactions to service_role;

-- ─────────────── 2. run_comment_likes ───────────────

create table public.run_comment_likes (
  user_id    uuid not null references auth.users(id) on delete cascade,
  comment_id uuid not null references public.run_comments(id) on delete cascade,
  liked_at   timestamptz not null default now(),
  primary key (user_id, comment_id)
);

create index run_comment_likes_comment_id on public.run_comment_likes (comment_id);

comment on table public.run_comment_likes is
  'One-tap likes on a run comment or reply (decisions § 1971). Readable when '
  'the comment''s run is readable.';

-- A like inherits the visibility of the comment's run. Definer because the
-- run_comments row is itself RLS-gated and a policy-time subquery against it
-- would re-enter its policy.
create or replace function private.is_run_comment_visible_to(p_comment_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from run_comments c
     where c.id = p_comment_id
       and private.is_run_visible_to(c.run_id, p_user_id)
  );
$$;

revoke execute on function private.is_run_comment_visible_to(uuid, uuid) from public, anon;
grant execute on function private.is_run_comment_visible_to(uuid, uuid) to anon, authenticated, service_role;

-- Whether p_actor may like p_comment_id: the comment's run is readable to
-- them, they did not write the comment, and no block stands either way
-- between them and the comment's author or the run's owner. Both identities
-- are resolved here in definer context (§ 158).
create or replace function private.can_like_run_comment(p_actor uuid, p_comment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_actor is not null
     and exists (
       select 1 from run_comments c
        where c.id = p_comment_id
          and c.author_id <> p_actor
          and private.is_run_visible_to(c.run_id, p_actor)
          and not is_blocked_either_way(p_actor, c.author_id)
          and not private.is_blocked_for_run(p_actor, c.run_id)
     );
$$;

revoke execute on function private.can_like_run_comment(uuid, uuid) from public, anon;
grant execute on function private.can_like_run_comment(uuid, uuid) to authenticated, service_role;

alter table public.run_comment_likes enable row level security;

create policy "comment likes readable when the run is readable"
  on public.run_comment_likes for select
  to anon, authenticated
  using (private.is_run_comment_visible_to(comment_id, (select auth.uid())));

create policy "users like comments on their own behalf"
  on public.run_comment_likes for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and private.can_like_run_comment((select auth.uid()), comment_id)
  );

create policy "users remove their own comment likes"
  on public.run_comment_likes for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.run_comment_likes from public, anon, authenticated;
grant select on table public.run_comment_likes to anon, authenticated;
grant insert, delete on table public.run_comment_likes to authenticated;
grant select, insert, update, delete on table public.run_comment_likes to service_role;

-- ─────────────── 3. read RPCs ───────────────

-- Per-reaction counts on one run plus whether the caller left each. INVOKER:
-- run_reactions RLS decides what is counted, so a run the caller cannot read
-- returns no rows rather than counts.
create or replace function public.run_reaction_summary(p_run_id uuid)
returns table (reaction text, reaction_count bigint, viewer_reacted boolean)
language sql
stable
set search_path = public, pg_temp
as $$
  select r.reaction,
         count(*) as reaction_count,
         coalesce(bool_or(r.user_id = (select auth.uid())), false) as viewer_reacted
    from run_reactions r
   where r.run_id = p_run_id
   group by r.reaction;
$$;

revoke execute on function public.run_reaction_summary(uuid) from public, anon;
grant execute on function public.run_reaction_summary(uuid) to anon, authenticated, service_role;

-- Per-comment like counts for every liked comment on one run, plus whether the
-- caller liked each. INVOKER for the same reason.
create or replace function public.run_comment_like_summary(p_run_id uuid)
returns table (comment_id uuid, like_count bigint, viewer_liked boolean)
language sql
stable
set search_path = public, pg_temp
as $$
  select l.comment_id,
         count(*) as like_count,
         coalesce(bool_or(l.user_id = (select auth.uid())), false) as viewer_liked
    from run_comment_likes l
    join run_comments c on c.id = l.comment_id
   where c.run_id = p_run_id
   group by l.comment_id;
$$;

revoke execute on function public.run_comment_like_summary(uuid) from public, anon;
grant execute on function public.run_comment_like_summary(uuid) to anon, authenticated, service_role;

-- ─────────────── 4. mention parsing ───────────────

-- The handles a comment body mentions, lowercased, de-duplicated, in order of
-- first appearance, at most ten. A mention is `@` + a § 269 handle that is
-- not glued to a word or a second `@` on its left (so `me@example.com` is not
-- a mention of `example`) and not followed by another handle character (so a
-- 31-character run is not truncated into a 30-character handle). The rule is
-- the TS / Dart parity pair social/mentions.ts / mentions.dart.
create or replace function private.extract_mention_handles(p_body text)
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(array_agg(h order by first_at), '{}'::text[])
    from (
      select h, min(rn) as first_at
        from (
          select pg_catalog.lower(m[2]) as h, row_number() over () as rn
            from pg_catalog.regexp_matches(
                   coalesce(p_body, ''),
                   '(^|[^A-Za-z0-9_@])@([A-Za-z0-9_]{3,30})(?![A-Za-z0-9_])',
                   'g'
                 ) as m
        ) found
       group by h
       order by min(rn)
       limit 10
    ) firsts;
$$;

revoke execute on function private.extract_mention_handles(text) from public, anon, authenticated;
grant execute on function private.extract_mention_handles(text) to service_role;

-- ─────────────── 5. notification kinds ───────────────

alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement', 'challenge_complete', 'content_hidden',
      'data_export_ready', 'refund_failed', 'event_waitlist_slot',
      'follow_request',
      'reaction', 'comment_like', 'mention'
    )
  )
  not valid;

-- ─────────────── 6. notify triggers ───────────────

create or replace function public.notify_run_reaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  run_owner uuid;
begin
  select user_id into run_owner from runs where id = NEW.run_id;
  if run_owner is null or run_owner = NEW.user_id then
    return NEW;
  end if;
  -- One notification per reactor per run, however many reactions they leave
  -- or how often they toggle one.
  if exists (
    select 1 from notifications n
     where n.run_id = NEW.run_id
       and n.user_id = run_owner
       and n.actor_id = NEW.user_id
       and n.kind = 'reaction'
  ) then
    return NEW;
  end if;
  insert into notifications (user_id, actor_id, kind, run_id, activity_kind, activity_id)
    values (run_owner, NEW.user_id, 'reaction', NEW.run_id, 'run', NEW.run_id);
  return NEW;
end;
$$;

revoke execute on function public.notify_run_reaction() from public, anon, authenticated;

create trigger run_reactions_notify
  after insert on public.run_reactions
  for each row execute function public.notify_run_reaction();

create or replace function public.notify_run_comment_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author uuid;
  v_run    uuid;
begin
  select author_id, run_id into v_author, v_run
    from run_comments where id = NEW.comment_id;
  if v_author is null or v_author = NEW.user_id then
    return NEW;
  end if;
  if exists (
    select 1 from notifications n
     where n.comment_id = NEW.comment_id
       and n.user_id = v_author
       and n.actor_id = NEW.user_id
       and n.kind = 'comment_like'
  ) then
    return NEW;
  end if;
  insert into notifications (user_id, actor_id, kind, run_id, comment_id, activity_kind, activity_id)
    values (v_author, NEW.user_id, 'comment_like', v_run, NEW.comment_id, 'run', v_run);
  return NEW;
end;
$$;

revoke execute on function public.notify_run_comment_like() from public, anon, authenticated;

create trigger run_comment_likes_notify
  after insert on public.run_comment_likes
  for each row execute function public.notify_run_comment_like();

-- Runs on INSERT and on an edit of the body. An edit notifies only the handles
-- the new body adds; a handle already in the old body was notified then.
--
-- Skipped recipients: the author; on a top-level comment the run owner, and on
-- a reply the parent comment's author — each already gets the `comment` /
-- `comment_reply` row for the same comment, and two rows for one comment is
-- noise. Then the two gates the mention exists to honour: the recipient must
-- already be able to read the run, and no block may stand either way between
-- the recipient and the author or the recipient and the run owner.
create or replace function public.notify_run_comment_mentions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_handles       text[];
  v_previous      text[] := '{}';
  v_owner         uuid;
  v_parent_author uuid;
begin
  v_handles := private.extract_mention_handles(NEW.body);
  if coalesce(array_length(v_handles, 1), 0) = 0 then
    return NEW;
  end if;
  if TG_OP = 'UPDATE' then
    v_previous := private.extract_mention_handles(OLD.body);
  end if;

  select user_id into v_owner from runs where id = NEW.run_id;
  if NEW.parent_comment_id is not null then
    select author_id into v_parent_author
      from run_comments where id = NEW.parent_comment_id;
  end if;

  insert into notifications (user_id, actor_id, kind, run_id, comment_id, activity_kind, activity_id)
  select p.id, NEW.author_id, 'mention', NEW.run_id, NEW.id, 'run', NEW.run_id
    from user_profiles p
   where p.handle is not null
     and lower(p.handle) = any(v_handles)
     and not (lower(p.handle) = any(v_previous))
     and p.id <> NEW.author_id
     and (NEW.parent_comment_id is not null or p.id is distinct from v_owner)
     and (NEW.parent_comment_id is null or p.id is distinct from v_parent_author)
     and private.is_run_visible_to(NEW.run_id, p.id)
     and not is_blocked_either_way(NEW.author_id, p.id)
     and not private.is_blocked_for_run(p.id, NEW.run_id)
     and not exists (
       select 1 from notifications n
        where n.comment_id = NEW.id
          and n.user_id = p.id
          and n.kind = 'mention'
     );
  return NEW;
end;
$$;

revoke execute on function public.notify_run_comment_mentions() from public, anon, authenticated;

create trigger run_comments_notify_mentions
  after insert or update of body on public.run_comments
  for each row execute function public.notify_run_comment_mentions();
