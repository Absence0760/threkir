-- Direct messages: image attachments (issue #1216).
--
-- A message can carry one photo. The bytes live in a private Storage bucket;
-- the conversation only ever shows a copy the server re-encoded, so no
-- metadata the sender's camera wrote (GPS position, capture time, device) can
-- reach the recipient whatever the sending client did.
--
-- ── The flow ────────────────────────────────────────────────────────────
--
--   1. create_dm_image_upload() makes a direct_message_images row (status
--      pending) and returns where to upload: {owner}/{image}/upload.
--   2. The client strips the metadata itself (re-encodes to JPEG at most
--      2048 px on the long edge) and uploads to that path. The bucket takes
--      image/jpeg only, at most 5 MB, and the INSERT policy takes an object
--      only at the upload path of the caller's own pending, unsent image.
--      There is no UPDATE or DELETE policy, so an upload cannot be swapped.
--   3. The client sends the message with image_id. The direct_messages
--      INSERT policy admits it only through private.dm_image_send_admitted:
--      the gate is open, the image is the sender's, pending, unsent and
--      uploaded, and the conversation is not a message request (below).
--   4. An AFTER INSERT trigger links the image to the message (one message
--      per image, enforced by a unique message_id) and queues a
--      dm_image_process job.
--   5. The Go worker downloads the upload, decodes it with Go's image
--      decoders (JPEG or PNG; anything else, or over 40 megapixels, is
--      rejected), scales it to at most 2048 px, encodes a fresh JPEG to
--      {owner}/{image}.jpg, removes the upload, and marks the row ready
--      with its size. A failure marks it rejected.
--
-- ── Why the server re-encodes rather than strips or rejects ─────────────
--
-- Decoding to pixels and encoding a new file keeps nothing but pixels: no
-- EXIF, XMP, IPTC, ICC, comments or trailing bytes, in any segment or chunk
-- type, known or not. A marker stripper (what run photos use) removes the
-- segments it knows; a rejecter has to recognise every place metadata can
-- hide. Both depend on a list. The cost is one lossy re-encode of a photo
-- the client already re-encoded, and a few seconds before the recipient sees
-- it. Until the row is ready nobody, the sender included, can read any image
-- bytes: the SELECT policy admits only the re-encoded object of a ready row.
-- The client strip is kept so the raw upload, which only the worker reads,
-- holds no metadata either.
--
-- ── Who may send one ────────────────────────────────────────────────────
--
-- Only inside an established conversation: a follow edge either way (or an
-- active coaching link), or a request the recipient has accepted. A pending
-- request cannot carry an image, from either side: a stranger's first
-- contact is text only, which is the stricter of the two defaults. A
-- declined request and a block refuse it like any send. The refusal is the
-- same 42501 every other refusal is (decisions § 1916).
--
-- The gate is private.feature_flags 'dm_images', which no migration writes:
-- prod refuses image uploads and image sends until it is set, after the
-- pre-deploy review in docs/ops/deployment.md. seed.sql opens it for local
-- dev and CI. dm_images_enabled() tells clients whether to offer it.
--
-- ── Who may read one ────────────────────────────────────────────────────
--
-- The object {owner}/{image}.jpg of a ready image whose message the caller
-- can read under direct_messages' own SELECT policy (participant, not hidden
-- by a delete-for-me) and that is not unsent. Clients get a signed URL, never
-- a public one. An admin may read an image a report holds.
--
-- ── Unsend, deletion, retention, reports ────────────────────────────────
--
-- The image row outlives its message only while a report holds it:
--
--   * unsend detaches the image (a BEFORE trigger clears image_id, the
--     body CHECK requires it), the purges and the sender's account deletion
--     delete the message, and either way direct_message_images.message_id
--     becomes null;
--   * a detached image no report names is deleted at once
--     (private.dm_image_release);
--   * a report filed on the message snapshots the image
--     (reports.snapshot_image_id), and the image is deleted when that report
--     is (purge_stale_reports, after its retention window);
--   * an upload never sent is deleted after a day by the nightly
--     dm-images-housekeeping job.
--
-- Deleting an image row queues a dm_image_orphan_sweep job with its two
-- paths, and the worker erases the bytes through the Storage API (a
-- storage.objects row delete leaves the bytes behind, decisions § 1049). The
-- nightly job also queues a backstop sweep of every object no row names.
-- Both Art 20 exports carry the subject's own images and their rows.
--
-- ── Locks ───────────────────────────────────────────────────────────────
--
-- direct_messages: ADD COLUMN (catalogue-only), a CHECK swapped NOT VALID
-- and validated by 20271213121605, a policy expression, grants, triggers
-- (SHARE ROW EXCLUSIVE, no scan). No index on direct_messages: the image link
-- of record is direct_message_images.message_id, on the new table. reports:
-- ADD COLUMN, a NOT VALID CHECK and FK (validated, and the column indexed,
-- by 20271213121605), triggers. jobs: the kind CHECK widened NOT VALID with no VALIDATE, the
-- guarded-table precedent (decisions § 1148).

-- ─── the gate ───────────────────────────────────────────────────────────

create function private.dm_images_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'dm_images'),
    false
  );
$$;

revoke execute on function private.dm_images_enabled() from public, anon, authenticated;

create function public.dm_images_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.dm_images_enabled();
$$;

revoke execute on function public.dm_images_enabled() from public, anon;
grant execute on function public.dm_images_enabled() to authenticated, service_role;

comment on function public.dm_images_enabled() is
  'Whether photos can be sent in direct messages (issue #1216). Clients hide '
  'the attach button when false.';

-- ─── the table ──────────────────────────────────────────────────────────

create table direct_message_images (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users (id) on delete set null,
  message_id uuid unique references direct_messages (id) on delete set null,
  status text not null default 'pending',
  upload_path text not null unique,
  storage_path text not null unique,
  width integer,
  height integer,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  constraint direct_message_images_status_check
    check (status in ('pending', 'ready', 'rejected')),
  constraint direct_message_images_size_check
    check (
      (status = 'ready') = (width is not null and height is not null)
      and (width is null or width between 1 and 2048)
      and (height is null or height between 1 and 2048)
    )
);

create index direct_message_images_owner on direct_message_images (owner_id);

comment on table direct_message_images is
  'A photo attached to a direct message (issue #1216). upload_path holds the '
  'client upload until the worker re-encodes it to storage_path and marks '
  'the row ready. message_id is null before the send and after the message '
  'is unsent or deleted; a detached row lives only while a report holds it.';

alter table direct_message_images enable row level security;

revoke all on direct_message_images from public, anon, authenticated;
-- Every column is readable by whoever the policy admits, so the grant is
-- table-wide (a per-column grant of every column is what
-- column_grant_lockdown_registry_test calls a table-wide grant written the
-- long way). No client holds INSERT, UPDATE or DELETE.
grant select on direct_message_images to anon, authenticated;
grant all on direct_message_images to service_role;

create policy "owner and participants read message images"
  on direct_message_images for select
  to authenticated
  using (
    owner_id = (select auth.uid())
    or exists (
      select 1 from direct_messages m
       where m.id = direct_message_images.message_id
         and m.unsent_at is null
    )
  );

-- ─── reports keep the image (the column; the triggers are below) ──────

alter table reports
  add column snapshot_image_id uuid;

alter table reports
  add constraint reports_snapshot_image_id_fkey
    foreign key (snapshot_image_id) references direct_message_images (id) on delete set null
    not valid;

alter table reports
  add constraint reports_snapshot_image_check
    check (snapshot_image_id is null or target_kind = 'direct_message')
    not valid;

comment on column reports.snapshot_image_id is
  'The photo a reported direct message carried when it was reported (issue '
  '#1216). Holds the image past an unsend, the sender''s account deletion and '
  'the purges until the report itself is deleted. Set by a trigger, never by '
  'a client.';

-- ─── the bucket ─────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dm-images', 'dm-images', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

create policy "dm-images upload to own pending image"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'dm-images'
    and exists (
      select 1 from public.direct_message_images i
       where i.upload_path = storage.objects.name
         and i.owner_id = (select auth.uid())
         and i.status = 'pending'
         and i.message_id is null
    )
  );

create function private.dm_image_report_held(p_path text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from reports r
      join direct_message_images i on i.id = r.snapshot_image_id
     where i.storage_path = p_path
       and i.status = 'ready'
  );
$$;

revoke execute on function private.dm_image_report_held(text) from public, anon;
grant execute on function private.dm_image_report_held(text) to authenticated, service_role;

create policy "dm-images read by who can read the message"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'dm-images'
    and (
      exists (
        select 1
          from public.direct_message_images i
          join public.direct_messages m on m.id = i.message_id
         where i.storage_path = storage.objects.name
           and i.status = 'ready'
           and m.unsent_at is null
      )
      or (
        private.is_admin((select auth.uid()))
        and private.dm_image_report_held(storage.objects.name)
      )
    )
  );

-- ─── starting an upload ─────────────────────────────────────────────────

create function create_dm_image_upload()
returns table (id uuid, upload_path text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_id uuid := gen_random_uuid();
begin
  if v_me is null then
    raise exception 'create_dm_image_upload: not authorized' using errcode = '42501';
  end if;
  if not private.dm_images_enabled() then
    raise exception 'create_dm_image_upload: photos in messages are not available'
      using errcode = '0A000';
  end if;

  perform enforce_create_rate_limit('dm_image_upload', v_me, 30, 3600);

  insert into direct_message_images (id, owner_id, upload_path, storage_path)
  values (
    v_id,
    v_me,
    v_me::text || '/' || v_id::text || '/upload',
    v_me::text || '/' || v_id::text || '.jpg'
  );

  return query select v_id, v_me::text || '/' || v_id::text || '/upload';
end;
$$;

revoke execute on function create_dm_image_upload() from public, anon;
grant execute on function create_dm_image_upload() to authenticated, service_role;

comment on function create_dm_image_upload() is
  'Starts a photo for a direct message (issue #1216): a pending '
  'direct_message_images row and the Storage path to upload the JPEG to. '
  '0A000 while the dm_images gate is closed. Spends dm_image_upload '
  '(30/hour).';

-- ─── sending one ────────────────────────────────────────────────────────

alter table direct_messages
  add column image_id uuid;

comment on column direct_messages.image_id is
  'The direct_message_images row this message carries (issue #1216), or '
  'null. Cleared on unsend. No FK: the link of record is '
  'direct_message_images.message_id, which is unique and indexed.';

grant select (image_id) on direct_messages to anon, authenticated;
grant insert (image_id) on direct_messages to authenticated;

alter table direct_messages
  drop constraint direct_messages_body_check;

alter table direct_messages
  add constraint direct_messages_body_check
  check (
    (
      unsent_at is null
      and (
        (body is not null and length(btrim(body)) between 1 and 4000)
        or (body is null and image_id is not null)
      )
    )
    or (unsent_at is not null and body is null and route_id is null and image_id is null)
  ) not valid;

create function private.dm_image_send_admitted(p_recipient uuid, p_image uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_state text;
begin
  if v_me is null or p_recipient is null or p_image is null then
    return false;
  end if;
  if not private.dm_images_enabled() then
    return false;
  end if;

  if not exists (
    select 1
      from direct_message_images i
      join storage.objects o on o.bucket_id = 'dm-images' and o.name = i.upload_path
     where i.id = p_image
       and i.owner_id = v_me
       and i.status = 'pending'
       and i.message_id is null
  ) then
    return false;
  end if;

  v_state := private.dm_recipient_request_state(v_me, p_recipient);
  if v_state = 'declined' then
    return false;
  end if;
  if v_state = 'accepted' then
    return true;
  end if;
  return private.dm_follow_edge(v_me, p_recipient);
end;
$$;

revoke execute on function private.dm_image_send_admitted(uuid, uuid) from public, anon;
grant execute on function private.dm_image_send_admitted(uuid, uuid) to authenticated, service_role;

comment on function private.dm_image_send_admitted(uuid, uuid) is
  'The direct_messages INSERT policy''s rule for a message carrying an image '
  '(issue #1216): the dm_images gate is open, the image is the caller''s own, '
  'pending, unsent and uploaded, and the conversation is not a request (a '
  'follow edge either way, or the recipient accepted).';

-- Re-emitted whole (bare-body rule): 20271210001217's expression plus the
-- image clause.
alter policy "send when not blocked and within follow graph" on direct_messages
  with check (
    sender_id = (select auth.uid())
    and not is_blocked_either_way(sender_id, recipient_id)
    and private.dm_send_admitted(recipient_id)
    and (
      direct_messages.route_id is null
      or private.is_route_visible_to(direct_messages.route_id, (select auth.uid()))
    )
    and (
      direct_messages.kind = 'text'
      or (
        direct_messages.kind = 'ai_assisted'
        and private.is_active_coach_of((select auth.uid()), direct_messages.recipient_id)
      )
    )
    and direct_messages.coach_message_id is null
    and (
      direct_messages.image_id is null
      or private.dm_image_send_admitted(direct_messages.recipient_id, direct_messages.image_id)
    )
  );

-- ─── jobs ───────────────────────────────────────────────────────────────

alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push', 'lifecycle_drip', 'route_photo_process',
      'club_photo_process', 'safety_sms', 'data_export', 'export_blob_reap',
      'distance_recompute', 'security_email', 'route_photo_orphan_sweep',
      'segment_match', 'club_verification_email', 'dm_image_process',
      'dm_image_orphan_sweep'
    )
  )
  not valid;

-- ─── linking on send ────────────────────────────────────────────────────

create function private.direct_messages_link_image()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update direct_message_images
     set message_id = new.id
   where id = new.image_id
     and owner_id = new.sender_id
     and message_id is null
     and status = 'pending';
  if not found then
    raise exception 'direct_messages: that image is already sent or not yours'
      using errcode = '23505';
  end if;

  insert into public.jobs (kind, payload)
  values ('dm_image_process', jsonb_build_object('image_id', new.image_id));
  return null;
end;
$$;

revoke execute on function private.direct_messages_link_image() from public, anon, authenticated;

create trigger direct_messages_link_image
  after insert on direct_messages
  for each row
  when (new.image_id is not null)
  execute function private.direct_messages_link_image();

-- ─── unsend detaches ────────────────────────────────────────────────────

create function private.direct_messages_unsent_drop_image()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.image_id := null;
  return new;
end;
$$;

revoke execute on function private.direct_messages_unsent_drop_image() from public, anon, authenticated;

create trigger direct_messages_unsent_drop_image
  before update of unsent_at on direct_messages
  for each row
  when (old.unsent_at is null and new.unsent_at is not null)
  execute function private.direct_messages_unsent_drop_image();

create function private.direct_messages_unsent_detach_image()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update direct_message_images set message_id = null where message_id = new.id;
  return null;
end;
$$;

revoke execute on function private.direct_messages_unsent_detach_image() from public, anon, authenticated;

create trigger direct_messages_unsent_detach_image
  after update of unsent_at on direct_messages
  for each row
  when (old.unsent_at is null and new.unsent_at is not null)
  execute function private.direct_messages_unsent_detach_image();

-- ─── release: a detached image no report holds goes ─────────────────────

create function private.dm_image_release(p_image uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from direct_message_images i
   where i.id = p_image
     and i.message_id is null
     and not exists (select 1 from reports r where r.snapshot_image_id = i.id);
$$;

revoke execute on function private.dm_image_release(uuid) from public, anon, authenticated;

create function private.direct_message_images_detached()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.dm_image_release(new.id);
  return null;
end;
$$;

revoke execute on function private.direct_message_images_detached() from public, anon, authenticated;

-- Fires when the message goes (unsend, a purge, the sender's account
-- deletion: message_id set null) and when the owner's account goes before
-- the image was ever sent (owner_id set null).
create trigger direct_message_images_detached
  after update of message_id, owner_id on direct_message_images
  for each row
  when (
    new.message_id is null
    and (old.message_id is not null or (old.owner_id is not null and new.owner_id is null))
  )
  execute function private.direct_message_images_detached();

-- ─── erasing the bytes ──────────────────────────────────────────────────

create function private.direct_message_images_enqueue_erase()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_paths text[];
begin
  select array_agg(p order by p) into v_paths
    from (
      select g.upload_path as p from gone g
      union
      select g.storage_path from gone g
    ) s;
  if v_paths is not null then
    insert into public.jobs (kind, payload, max_attempts)
    select 'dm_image_orphan_sweep',
           jsonb_build_object('paths', to_jsonb(v_paths[i:i + 999])),
           5
      from generate_series(1, cardinality(v_paths), 1000) as i;
  end if;
  return null;
end;
$$;

revoke execute on function private.direct_message_images_enqueue_erase() from public, anon, authenticated;

create trigger direct_message_images_enqueue_erase
  after delete on direct_message_images
  referencing old table as gone
  for each statement
  execute function private.direct_message_images_enqueue_erase();

-- The worklist: of the paths asked about (or, with null, every object in
-- the bucket last written over 24 hours ago), the ones no image row names.
-- The worker erases exactly these. Service role only.
create function public.dm_image_orphan_paths(p_paths text[] default null, p_limit integer default 100)
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select o.name
    from storage.objects o
   where o.bucket_id = 'dm-images'
     and (
       (p_paths is not null and o.name = any (p_paths))
       or (p_paths is null and greatest(o.created_at, o.updated_at) < now() - interval '24 hours')
     )
     and not exists (select 1 from direct_message_images i where i.storage_path = o.name)
     and not exists (
       select 1 from direct_message_images i
        where i.upload_path = o.name
          and i.status = 'pending'
     )
   order by o.name
   limit least(greatest(coalesce(p_limit, 100), 1), 500);
$$;

revoke execute on function public.dm_image_orphan_paths(text[], integer) from public, anon, authenticated;
grant execute on function public.dm_image_orphan_paths(text[], integer) to service_role;

comment on function public.dm_image_orphan_paths(text[], integer) is
  'Worklist for the dm_image_orphan_sweep job (issue #1216): dm-images '
  'objects no direct_message_images row names (as its re-encoded image, or as '
  'the upload of a pending one). With p_paths, those paths; with null, every '
  'such object last written over 24 hours ago. At most 500. Service role only.';

-- ─── nightly housekeeping ───────────────────────────────────────────────

create function private.dm_images_housekeeping()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from direct_message_images i
   where i.message_id is null
     and i.created_at < now() - interval '24 hours'
     and not exists (select 1 from reports r where r.snapshot_image_id = i.id);

  insert into public.jobs (kind, payload, max_attempts)
  select 'dm_image_orphan_sweep', '{}'::jsonb, 3
  where not exists (
    select 1 from public.jobs j
     where j.kind = 'dm_image_orphan_sweep'
       and j.payload = '{}'::jsonb
       and j.status in ('queued', 'running')
  );
end;
$$;

revoke execute on function private.dm_images_housekeeping() from public, anon, authenticated;

select cron.schedule(
  'dm-images-housekeeping',
  '27 4 * * *',
  $$select private.dm_images_housekeeping()$$
);

-- ─── reports keep the image ─────────────────────────────────────────────

create function private.reports_snapshot_dm_image()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.target_kind = 'direct_message' then
    select i.id into new.snapshot_image_id
      from direct_message_images i
     where i.message_id = new.target_id
       and i.status in ('pending', 'ready');
    if new.snapshot_image_id is not null and new.snapshot_body is null then
      new.snapshot_body := '';
    end if;
  else
    new.snapshot_image_id := null;
  end if;
  return new;
end;
$$;

revoke execute on function private.reports_snapshot_dm_image() from public, anon, authenticated;

create trigger reports_snapshot_dm_image
  before insert on reports
  for each row
  execute function private.reports_snapshot_dm_image();

create function private.reports_release_dm_image()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.dm_image_release(g.snapshot_image_id)
     from gone g
    where g.snapshot_image_id is not null;
  return null;
end;
$$;

revoke execute on function private.reports_release_dm_image() from public, anon, authenticated;

create trigger reports_release_dm_image
  after delete on reports
  referencing old table as gone
  for each statement
  execute function private.reports_release_dm_image();

-- An admin reviewing a reported message reads the photo it carried.
create function admin_dm_report_image_path(p_report_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_path text;
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'admin_dm_report_image_path: not authorized' using errcode = '42501';
  end if;
  select i.storage_path into v_path
    from reports r
    join direct_message_images i on i.id = r.snapshot_image_id
   where r.id = p_report_id
     and i.status = 'ready';
  return v_path;
end;
$$;

revoke execute on function admin_dm_report_image_path(uuid) from public, anon;
grant execute on function admin_dm_report_image_path(uuid) to authenticated, service_role;

comment on function admin_dm_report_image_path(uuid) is
  'Admin only (issue #1216): the dm-images path of the photo a reported '
  'direct message carried, or null. The admin signs a URL for it under the '
  'dm-images SELECT policy''s report clause.';

-- ─── dm_threads: whether the newest message is a photo ──────────────────
--
-- Bare-body re-emit of 20271210001215's dm_threads with last_image
-- appended, so an inbox whose newest message is a photo with no caption can
-- say so. A new OUT column changes the return type, hence the drop.

drop function dm_threads();

create function dm_threads()
returns table (
  conversation_id uuid,
  partner_id uuid,
  deleted_partner_key uuid,
  last_body text,
  last_unsent boolean,
  last_at timestamptz,
  last_from_me boolean,
  unread bigint,
  muted boolean,
  archived boolean,
  marked_unread boolean,
  request boolean,
  last_kind text,
  last_image boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with my_msgs as (
    select
      m.conversation_id,
      case when m.sender_id = (select auth.uid()) then m.recipient_id else m.sender_id end as partner_id,
      m.deleted_partner_key,
      m.sender_id,
      m.recipient_id,
      m.body,
      m.unsent_at,
      m.created_at,
      m.read_at,
      m.id,
      m.kind,
      m.image_id
    from direct_messages m
    where (m.sender_id = (select auth.uid()) or m.recipient_id = (select auth.uid()))
      and not exists (
        select 1 from conversation_participants hp
         where hp.conversation_id = m.conversation_id
           and hp.user_id = (select auth.uid())
           and hp.hidden_before is not null
           and m.created_at <= hp.hidden_before
      )
  ),
  latest as (
    select distinct on (conversation_id)
      conversation_id,
      partner_id,
      deleted_partner_key,
      body as last_body,
      (unsent_at is not null) as last_unsent,
      created_at as last_at,
      (sender_id = (select auth.uid())) as last_from_me,
      kind as last_kind,
      (image_id is not null) as last_image
    from my_msgs
    order by conversation_id, created_at desc, id desc
  ),
  unread as (
    select conversation_id, count(*) as cnt
    from my_msgs
    where recipient_id = (select auth.uid()) and read_at is null and unsent_at is null
    group by conversation_id
  )
  select
    l.conversation_id,
    l.partner_id,
    l.deleted_partner_key,
    l.last_body,
    l.last_unsent,
    l.last_at,
    l.last_from_me,
    greatest(coalesce(u.cnt, 0), case when p.marked_unread_at is not null then 1 else 0 end) as unread,
    coalesce(p.muted_at is not null, false) as muted,
    coalesce(p.archived_at is not null and p.archived_at >= l.last_at, false) as archived,
    coalesce(p.marked_unread_at is not null, false) as marked_unread,
    coalesce(p.request_state = 'pending', false) as request,
    l.last_kind,
    l.last_image
  from latest l
  left join unread u using (conversation_id)
  left join conversation_participants p
    on p.conversation_id = l.conversation_id
   and p.user_id = (select auth.uid())
  where p.request_state is distinct from 'declined'
  order by l.last_at desc;
$$;

revoke execute on function dm_threads() from public, anon;
grant execute on function dm_threads() to authenticated, service_role;
