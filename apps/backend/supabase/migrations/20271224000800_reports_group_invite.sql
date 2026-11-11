-- A group invite can be reported before it is accepted (audit of PR #1359,
-- Low).
--
-- A group's title is shown to everyone it invites before they join, and one
-- account may send fifty invites a day, but the only reportable target in a
-- conversation was a message the reporter can read, so an abusive title or
-- invite had no report path short of joining. submit_report takes a new
-- target kind, 'group_invite', whose target_id is the group conversation:
-- only someone holding a pending invite to it may file, with the general
-- reasons, and the report snapshots what they were shown -- the title
-- (snapshot_body), the inviter (snapshot_author_id) and when
-- (snapshot_sent_at) -- so the admin queue shows the evidence after the group
-- is renamed or the invite withdrawn. reports_group_invite_snapshot_check
-- requires the title.
--
-- Locks: both constraints are added NOT VALID (an instant catalog change
-- under ACCESS EXCLUSIVE on reports); 20271224000810 validates them in its
-- own transaction.

alter table reports drop constraint reports_target_kind_check;
alter table reports
  add constraint reports_target_kind_check
  check (target_kind in (
    'user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review', 'direct_message',
    'training_plan', 'gym_routine', 'challenge', 'race_listing',
    'park_course', 'group_invite'
  ))
  not valid;

alter table reports
  add constraint reports_group_invite_snapshot_check
  check (target_kind <> 'group_invite' or (snapshot_body is not null and snapshot_sent_at is not null))
  not valid;

create or replace function public.submit_report(
  p_target_kind text,
  p_target_id uuid,
  p_reason text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_reporter uuid := auth.uid();
  v_target_exists boolean;
  v_report_id uuid;
  v_dm direct_messages;
  v_invite_title text;
  v_invite_by uuid;
  v_invite_at timestamptz;
begin
  if v_reporter is null then
    raise exception 'submit_report: not authorized' using errcode = '42501';
  end if;

  if p_target_kind not in ('user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review', 'direct_message',
                           'group_invite') then
    raise exception 'submit_report: invalid target_kind %', p_target_kind
      using errcode = '22023';
  end if;

  if p_reason not in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other') then
    raise exception 'submit_report: invalid reason %', p_reason
      using errcode = '22023';
  end if;

  -- Don't let a user report themselves — most likely a misclick, and
  -- the queue noise isn't worth carrying.
  if p_target_kind = 'user' and p_target_id = v_reporter then
    raise exception 'submit_report: cannot report yourself'
      using errcode = '22023';
  end if;

  -- Validate the target exists. The FROM clauses run as the function owner
  -- (postgres) so RLS doesn't block visibility.
  if p_target_kind = 'user' then
    select exists (select 1 from user_profiles where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'club' then
    select exists (select 1 from clubs where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'route' then
    select exists (select 1 from routes where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'comment' then
    select exists (select 1 from run_comments where id = p_target_id) into v_target_exists;
    -- Reporting your own comment is a misclick; reject like self-user.
    if v_target_exists and exists (
      select 1 from run_comments where id = p_target_id and author_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own comment'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'club_post' then
    select exists (select 1 from club_posts where id = p_target_id) into v_target_exists;
    -- Reporting your own post is a misclick; reject like self-comment.
    if v_target_exists and exists (
      select 1 from club_posts where id = p_target_id and author_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own post'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'run' then
    select exists (select 1 from runs where id = p_target_id) into v_target_exists;
    -- Reporting your own run is a misclick; reject like self-comment.
    if v_target_exists and exists (
      select 1 from runs where id = p_target_id and user_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own run'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'route_review' then
    select exists (select 1 from route_reviews where id = p_target_id) into v_target_exists;
    -- Reporting your own review is a misclick; reject like self-comment.
    -- route_reviews' author column is `user_id` (no `author_id`).
    if v_target_exists and exists (
      select 1 from route_reviews where id = p_target_id and user_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own review'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'direct_message' then
    -- The read rule is the gate (private.can_read_message, decisions § 2461):
    -- the reporter reads their own report back, snapshot included, so a
    -- message the caller cannot read (not theirs, before they joined a group,
    -- after they left it) answers "not found", like one that does not exist.
    select * into v_dm
      from direct_messages
     where id = p_target_id
       and private.can_read_message(conversation_id, sender_id, recipient_id, is_group, created_at);
    v_target_exists := v_dm.id is not null;
    if v_target_exists and v_dm.sender_id = v_reporter then
      raise exception 'submit_report: cannot report your own message'
        using errcode = '22023';
    end if;
    if v_target_exists and v_dm.unsent_at is not null then
      raise exception 'submit_report: message was unsent'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'group_invite' then
    -- The target is the group conversation, and only someone it invited
    -- reports the invite: the title and the inviter are what they were shown
    -- before joining, so both are snapshotted for the moderator. Anyone else
    -- answers "not found", like a group that does not exist.
    select c.title, p.invited_by, p.invited_at
      into v_invite_title, v_invite_by, v_invite_at
      from conversation_participants p
      join conversations c on c.id = p.conversation_id and c.kind = 'group'
     where p.conversation_id = p_target_id
       and p.user_id = v_reporter
       and p.membership_state = 'invited';
    v_target_exists := found;
  end if;

  if not v_target_exists then
    raise exception 'submit_report: target % % not found', p_target_kind, p_target_id
      using errcode = '02000';
  end if;

  -- Rate-limit: 10 reports per hour per reporter.
  perform enforce_create_rate_limit('create_report', v_reporter, 10, 3600);

  begin
    insert into reports (
      reporter_id, target_kind, target_id, reason, notes,
      snapshot_body, snapshot_author_id, snapshot_sent_at, snapshot_original_body
    )
    values (
      v_reporter, p_target_kind, p_target_id, p_reason, p_notes,
      -- v_dm is only ever filled by the direct_message arm and the v_invite_*
      -- by the group_invite arm, so every other kind stores null snapshots.
      coalesce(v_dm.body, v_invite_title), coalesce(v_dm.sender_id, v_invite_by),
      coalesce(v_dm.created_at, v_invite_at), v_dm.original_body
    )
    returning id into v_report_id;
  exception when unique_violation then
    raise exception 'submit_report: already reported'
      using errcode = '23505',
            hint = 'You already have a pending report against this target.';
  end;

  return v_report_id;
end;
$function$;

revoke execute on function public.submit_report(text, uuid, text, text) from public, anon;
grant execute on function public.submit_report(text, uuid, text, text) to authenticated, service_role;
