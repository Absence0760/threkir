-- Club verification requests (issue #1190 § 2, decisions § 2398).
--
-- Until now `clubs.is_verified` was a direct database toggle. This is the
-- request flow the owner decided on (#1190 "Decisions → Verification"):
--
--   * The club OWNER applies, naming the organisation the club officially
--     represents. The claimed domain is the host of the club's own
--     `website_url`, so the domain a reviewer approves is the one every viewer
--     already sees linked from the club page, and a later website change is
--     detectable as a domain change.
--   * Proof is self-serve and objective, any one of: a DNS TXT record, a
--     `/.well-known/threkir-verification` file, or a confirm link mailed to an
--     address at the domain. The DNS and file checks run in the
--     `club-verification` Edge Function (it needs the network); it reports
--     each result through `record_club_verification_check`, granted to
--     service_role alone. The email proof is a job on the existing queue
--     (`club_verification_email`, 20271120000003) and is confirmed by the
--     link's single-use token.
--   * A person approves every request, even with proof passing: a domain
--     check cannot tell `comrades.com` from `comrades-marathon.net`. A site
--     admin (`private.is_admin`, the /admin allow-list) approves, rejects with
--     a reason, or revokes. Approving without automated proof is the manual
--     fallback and needs a note saying what was checked.
--   * Verified clubs are locked: changing a verified club's name, slug or
--     website domain drops the badge until it is re-reviewed
--     (`clubs_verification_lock`).
--   * Proof is re-checked: `club-verification-recheck` (hourly, pg_cron)
--     re-runs the DNS and file checks for every club approved on one of them,
--     at most once a day each. Three failed checks in a row drop the badge and
--     mark the request lapsed, so a lapsed domain is put back in front of a
--     reviewer instead of silently keeping the badge. Three, not one, so a
--     DNS blip or a deploy of the organiser's site does not unverify them.
--     A club proven by email or by manual review has nothing standing to
--     re-check, so it is not re-checked.
--   * Every action is written to `club_verification_audit`, which nobody can
--     update or delete, and every change of status notifies the club's owner
--     and admins (`club_verification`, 20271120000001).
--
-- `clubs.is_verified` stays writable only by the definer RPCs here and by
-- service_role. `freeze_club_managed_columns` (20270704000003) already
-- reverts it on any anon / authenticated insert or update, keyed on
-- current_user, which inside a definer RPC reads as the function owner. The
-- older `clubs_protect_is_verified_trg` (20260909_001) keyed on the JWT role
-- instead, which inside a definer RPC called by a signed-in admin still reads
-- `authenticated`, so it would have reverted the approval itself. It is
-- dropped: the freeze trigger covers every case it did, insert included.
--
-- The request row, not a new `clubs` column, holds the verified domain, so
-- `clubs` (and `search_clubs`' explicit column list) is untouched. The email
-- challenge's token hash sits in its own table with no client grant at all,
-- so the request table needs no column-level lockdown.
--
-- Locks: three new tables. On `clubs`, a DROP TRIGGER and a CREATE TRIGGER
-- (SHARE ROW EXCLUSIVE, catalogue only). Functions are catalogue only.

set search_path = public, extensions;

-- ── 1. the legacy JWT-keyed guard ───────────────────────────────────────────

drop trigger if exists clubs_protect_is_verified_trg on clubs;
drop function if exists clubs_protect_is_verified();

-- ── 2. helpers ──────────────────────────────────────────────────────────────

-- The registrable host of a club website: lower-cased, scheme, credentials,
-- port, path and one leading `www.` removed. NULL for anything that is not an
-- http(s) URL with a dotted, letters-digits-hyphens host (an IP literal has
-- no letter in its last label and is refused).
create or replace function private.club_website_domain(p_url text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_host text;
begin
  if p_url is null then
    return null;
  end if;
  v_host := lower(substring(btrim(p_url) from '^[hH][tT][tT][pP][sS]?://(?:[^@/?#]*@)?([^/:?#]+)'));
  if v_host is null then
    return null;
  end if;
  v_host := regexp_replace(rtrim(v_host, '.'), '^www\.', '');
  if char_length(v_host) < 4 or char_length(v_host) > 253 then
    return null;
  end if;
  if v_host !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$' then
    return null;
  end if;
  return v_host;
end;
$$;

revoke execute on function private.club_website_domain(text) from public, anon, authenticated;
grant execute on function private.club_website_domain(text) to service_role;

-- ── 3. tables ───────────────────────────────────────────────────────────────

create table club_verification_requests (
  id                uuid primary key default gen_random_uuid(),
  club_id           uuid not null references clubs (id) on delete cascade,
  submitted_by      uuid references auth.users (id) on delete set null,
  organisation      text not null,
  domain            text not null,
  note              text,
  -- The proof token for the DNS record and the .well-known file. Not a
  -- secret: it is published on the organiser's domain by design. A fresh one
  -- per request, so proof for one request never satisfies another.
  token             text not null default encode(extensions.gen_random_bytes(16), 'hex'),
  status            text not null default 'pending',
  proof_method      text,
  proof_verified_at timestamptz,
  proof_detail      text,
  last_checked_at   timestamptz,
  check_failures    integer not null default 0,
  decided_by        uuid references auth.users (id) on delete set null,
  decided_at        timestamptz,
  decision_reason   text,
  closed_by         uuid references auth.users (id) on delete set null,
  closed_at         timestamptz,
  close_reason      text,
  created_at        timestamptz not null default now(),
  constraint club_verification_requests_status_check
    check (status in ('pending', 'approved', 'rejected', 'revoked', 'lapsed', 'withdrawn')),
  constraint club_verification_requests_proof_method_check
    check (proof_method is null or proof_method in ('dns_txt', 'well_known', 'email', 'manual')),
  constraint club_verification_requests_organisation_len
    check (char_length(btrim(organisation)) between 1 and 120),
  constraint club_verification_requests_domain_len
    check (char_length(domain) between 4 and 253),
  constraint club_verification_requests_token_shape
    check (token ~ '^[0-9a-f]{32}$'),
  constraint club_verification_requests_note_len
    check (note is null or char_length(note) <= 1000),
  constraint club_verification_requests_proof_detail_len
    check (proof_detail is null or char_length(proof_detail) <= 500),
  constraint club_verification_requests_decision_reason_len
    check (decision_reason is null or char_length(decision_reason) <= 500),
  constraint club_verification_requests_close_reason_len
    check (close_reason is null or char_length(close_reason) <= 500),
  constraint club_verification_requests_failures_nonneg
    check (check_failures >= 0),
  -- Pending and withdrawn requests were never decided; every other status was.
  constraint club_verification_requests_decided
    check ((status in ('pending', 'withdrawn')) = (decided_at is null)),
  constraint club_verification_requests_closed
    check ((status in ('revoked', 'lapsed', 'withdrawn')) = (closed_at is not null))
);

-- One live request per club: a pending application or the approval in force.
create unique index club_verification_requests_one_live
  on club_verification_requests (club_id)
  where status in ('pending', 'approved');
create index club_verification_requests_club_idx
  on club_verification_requests (club_id, created_at desc);
create index club_verification_requests_pending_idx
  on club_verification_requests (created_at)
  where status = 'pending';
create index club_verification_requests_recheck_idx
  on club_verification_requests (last_checked_at)
  where status = 'approved' and proof_method in ('dns_txt', 'well_known');
create index club_verification_requests_submitted_by_idx
  on club_verification_requests (submitted_by);
create index club_verification_requests_decided_by_idx
  on club_verification_requests (decided_by);
create index club_verification_requests_closed_by_idx
  on club_verification_requests (closed_by);

alter table club_verification_requests enable row level security;

-- The club's owner and active admins read their club's requests (an admin
-- sees the status; only the owner can act). The submitter keeps reading the
-- request they made after they leave the club, which is what the data export
-- reads. Site admins read through the definer queue RPC below. Nothing is
-- written directly: every write is a definer RPC.
create policy "club admins read their club's verification requests"
  on club_verification_requests for select to authenticated
  using (
    submitted_by = (select auth.uid())
    or exists (
      select 1 from club_members m
      where m.club_id = club_verification_requests.club_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
        and m.role in ('owner', 'admin')
    )
  );

revoke all on public.club_verification_requests from anon, authenticated;
grant select on public.club_verification_requests to authenticated;
grant select, insert, update, delete on public.club_verification_requests to service_role;

-- The email proof's challenge. The token's SHA-256 only; the plaintext goes
-- out in the job payload and nowhere else. No policy and no client grant: it
-- is read and written by the definer RPCs alone.
create table club_verification_email_challenges (
  request_id  uuid primary key references club_verification_requests (id) on delete cascade,
  address     text not null,
  token_hash  bytea not null,
  expires_at  timestamptz not null,
  sent_at     timestamptz not null default now(),
  constraint club_verification_email_challenges_address_len
    check (char_length(address) between 6 and 320)
);

alter table club_verification_email_challenges enable row level security;
revoke all on public.club_verification_email_challenges from anon, authenticated;
grant select, insert, update, delete on public.club_verification_email_challenges to service_role;

-- The audit log. Append-only: no client writes, and a trigger refuses every
-- UPDATE but the foreign keys' own ON DELETE SET NULL, and every DELETE. The
-- club name is snapshotted, so the trail still reads after the club is gone.
create table club_verification_audit (
  id         bigint generated always as identity primary key,
  request_id uuid references club_verification_requests (id) on delete set null,
  club_id    uuid references clubs (id) on delete set null,
  club_name  text not null,
  actor_id   uuid references auth.users (id) on delete set null,
  action     text not null,
  detail     text,
  created_at timestamptz not null default now(),
  constraint club_verification_audit_action_check
    check (action in (
      'submit', 'withdraw', 'email_sent', 'proof_verified', 'proof_failed',
      'approve', 'reject', 'revoke', 'lapse'
    )),
  constraint club_verification_audit_detail_len
    check (detail is null or char_length(detail) <= 500),
  constraint club_verification_audit_club_name_len
    check (char_length(club_name) <= 200)
);

create index club_verification_audit_club_idx on club_verification_audit (club_id, created_at desc);
create index club_verification_audit_request_idx on club_verification_audit (request_id);
create index club_verification_audit_actor_idx on club_verification_audit (actor_id);
-- The email send limit counts a request's recent sends.
create index club_verification_audit_email_sent_idx
  on club_verification_audit (request_id, created_at)
  where action = 'email_sent';

alter table club_verification_audit enable row level security;

create policy "club admins and actors read verification audit"
  on club_verification_audit for select to authenticated
  using (
    actor_id = (select auth.uid())
    or exists (
      select 1 from club_members m
      where m.club_id = club_verification_audit.club_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
        and m.role in ('owner', 'admin')
    )
  );

revoke all on public.club_verification_audit from anon, authenticated;
grant select on public.club_verification_audit to authenticated;
grant select, insert on public.club_verification_audit to service_role;

create or replace function private.club_verification_audit_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'club_verification_audit is append-only' using errcode = '42501';
  end if;
  -- Only a foreign key's ON DELETE SET NULL may touch a row: each reference
  -- may go to null, and nothing else may change.
  if new.id is distinct from old.id
     or new.club_name is distinct from old.club_name
     or new.action is distinct from old.action
     or new.detail is distinct from old.detail
     or new.created_at is distinct from old.created_at
     or (new.request_id is distinct from old.request_id and new.request_id is not null)
     or (new.club_id is distinct from old.club_id and new.club_id is not null)
     or (new.actor_id is distinct from old.actor_id and new.actor_id is not null) then
    raise exception 'club_verification_audit is append-only' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger club_verification_audit_append_only
  before update or delete on club_verification_audit
  for each row execute function private.club_verification_audit_append_only();

-- ── 4. internal writers ─────────────────────────────────────────────────────

create or replace function private.club_verification_log(
  p_request_id uuid,
  p_club_id uuid,
  p_actor uuid,
  p_action text,
  p_detail text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.club_verification_audit (request_id, club_id, club_name, actor_id, action, detail)
  select p_request_id, c.id, c.name, p_actor, p_action, left(p_detail, 500)
  from public.clubs c
  where c.id = p_club_id;
$$;

-- The club's owner and active admins, told that the club's verification
-- changed. No actor: the reviewer is a site admin, and who reviewed is not
-- the club's to know.
create or replace function private.notify_club_verification(p_club_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, actor_id, kind, club_id)
  select r.recipient, null, 'club_verification', p_club_id
  from (
    select cm.user_id as recipient
    from public.club_members cm
    where cm.club_id = p_club_id
      and cm.status = 'active'
      and cm.role in ('owner', 'admin')
    union
    select c.owner_id from public.clubs c where c.id = p_club_id
  ) r
  where r.recipient is not null;
$$;

-- Marks the approval in force lapsed and logs and notifies. The caller drops
-- the badge: from the clubs trigger by editing NEW, elsewhere by an UPDATE.
create or replace function private.lapse_club_verification(
  p_club_id uuid,
  p_reason text,
  p_actor uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_id uuid;
begin
  update public.club_verification_requests
     set status = 'lapsed',
         closed_at = now(),
         closed_by = p_actor,
         close_reason = p_reason
   where club_id = p_club_id
     and status = 'approved'
  returning id into v_request_id;

  perform private.club_verification_log(v_request_id, p_club_id, p_actor, 'lapse', p_reason);
  perform private.notify_club_verification(p_club_id);
end;
$$;

revoke execute on function private.club_verification_log(uuid, uuid, uuid, text, text) from public, anon, authenticated;
revoke execute on function private.notify_club_verification(uuid) from public, anon, authenticated;
revoke execute on function private.lapse_club_verification(uuid, text, uuid) from public, anon, authenticated;

-- ── 5. the lock on a verified club ──────────────────────────────────────────

-- A verified club renamed, re-slugged or pointed at another website loses the
-- badge until it is reviewed again, whoever makes the edit. It runs after
-- `clubs_freeze_managed_columns` (trigger names fire in alphabetical order),
-- so a client's attempt to keep is_verified has already been reverted to the
-- stored value, which this then clears. A club verified before this flow
-- existed has no approved request and so no recorded domain; its name and
-- slug are still locked.
create or replace function private.clubs_verification_lock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_domain text;
  v_reason text;
begin
  if not (old.is_verified and new.is_verified) then
    return new;
  end if;

  select r.domain into v_domain
  from public.club_verification_requests r
  where r.club_id = new.id and r.status = 'approved';

  if new.name is distinct from old.name then
    v_reason := 'name_changed';
  elsif new.slug is distinct from old.slug then
    v_reason := 'slug_changed';
  elsif v_domain is not null
        and private.club_website_domain(new.website_url) is distinct from v_domain then
    v_reason := 'domain_changed';
  else
    return new;
  end if;

  new.is_verified := false;
  perform private.lapse_club_verification(new.id, v_reason, auth.uid());
  return new;
end;
$$;

revoke execute on function private.clubs_verification_lock() from public, anon, authenticated;

create trigger clubs_verification_lock
  before update on clubs
  for each row execute function private.clubs_verification_lock();

-- ── 6. the owner's RPCs ─────────────────────────────────────────────────────

create or replace function submit_club_verification(
  p_club_id uuid,
  p_organisation text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_club clubs%rowtype;
  v_domain text;
  v_id uuid;
begin
  select * into v_club from clubs where id = p_club_id;
  if v_uid is null or v_club.id is null or v_club.owner_id is distinct from v_uid then
    raise exception 'only the club owner can request verification' using errcode = '42501';
  end if;
  if v_club.is_verified then
    raise exception 'club_already_verified' using errcode = '22023';
  end if;
  v_domain := private.club_website_domain(v_club.website_url);
  if v_domain is null then
    raise exception 'club_website_required' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_organisation, ''))) not between 1 and 120 then
    raise exception 'organisation_required' using errcode = '22023';
  end if;
  if exists (select 1 from club_verification_requests where club_id = p_club_id and status = 'pending') then
    raise exception 'request_already_pending' using errcode = '22023';
  end if;

  insert into club_verification_requests (club_id, submitted_by, organisation, domain, note)
  values (p_club_id, v_uid, btrim(p_organisation), v_domain, nullif(btrim(coalesce(p_note, '')), ''))
  returning id into v_id;

  perform private.club_verification_log(v_id, p_club_id, v_uid, 'submit', v_domain);
  return v_id;
end;
$$;

create or replace function withdraw_club_verification(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_req club_verification_requests%rowtype;
begin
  select r.* into v_req
  from club_verification_requests r
  join clubs c on c.id = r.club_id
  where r.id = p_request_id and c.owner_id = v_uid;
  if v_uid is null or v_req.id is null then
    raise exception 'only the club owner can withdraw a verification request' using errcode = '42501';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = '22023';
  end if;

  update club_verification_requests
     set status = 'withdrawn', closed_at = now(), closed_by = v_uid
   where id = p_request_id;
  delete from club_verification_email_challenges where request_id = p_request_id;
  perform private.club_verification_log(p_request_id, v_req.club_id, v_uid, 'withdraw', null);
end;
$$;

-- Mails a single-use confirm link to <local part>@<the request's domain>.
-- Three sends a request a day, so the flow cannot be turned into a way of
-- mailing strangers. A new send replaces the previous challenge.
create or replace function send_club_verification_email(
  p_request_id uuid,
  p_local_part text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_req club_verification_requests%rowtype;
  v_club clubs%rowtype;
  v_local text := lower(btrim(coalesce(p_local_part, '')));
  v_address text;
  v_token text;
  v_locale text;
begin
  select r.* into v_req
  from club_verification_requests r
  join clubs c on c.id = r.club_id
  where r.id = p_request_id and c.owner_id = v_uid;
  if v_uid is null or v_req.id is null then
    raise exception 'only the club owner can send a verification email' using errcode = '42501';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = '22023';
  end if;
  if v_local !~ '^[a-z0-9]([a-z0-9._+-]{0,62}[a-z0-9])?$' or v_local like '%..%' then
    raise exception 'invalid_email_local_part' using errcode = '22023';
  end if;
  if (select count(*) from club_verification_audit
      where request_id = p_request_id and action = 'email_sent'
        and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'email_rate_limited' using errcode = '22023';
  end if;

  select * into v_club from clubs where id = v_req.club_id;
  v_address := v_local || '@' || v_req.domain;
  v_token := encode(extensions.gen_random_bytes(24), 'hex');
  select us.prefs->>'locale' into v_locale from user_settings us where us.user_id = v_uid;

  insert into club_verification_email_challenges (request_id, address, token_hash, expires_at, sent_at)
  values (p_request_id, v_address, sha256(convert_to(v_token, 'UTF8')), now() + interval '24 hours', now())
  on conflict (request_id) do update
    set address = excluded.address,
        token_hash = excluded.token_hash,
        expires_at = excluded.expires_at,
        sent_at = excluded.sent_at;

  insert into jobs (kind, payload)
  values (
    'club_verification_email',
    jsonb_build_object(
      'email', v_address,
      'locale', coalesce(v_locale, ''),
      'club_name', v_club.name,
      'organisation', v_req.organisation,
      'domain', v_req.domain,
      'token', v_token
    )
  );

  perform private.club_verification_log(p_request_id, v_req.club_id, v_uid, 'email_sent', v_address);
end;
$$;

-- The landing page of the mailed link calls this, signed in or not: the
-- token is the credential (192 random bits, single use, 24 hours). Every way
-- of not being a live challenge answers the same 'invalid'.
create or replace function confirm_club_verification_email(p_token text)
returns table (outcome text, club_name text, club_slug text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ch club_verification_email_challenges%rowtype;
  v_req club_verification_requests%rowtype;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{48}$' then
    return query select 'invalid'::text, null::text, null::text;
    return;
  end if;

  select * into v_ch
  from club_verification_email_challenges
  where token_hash = sha256(convert_to(p_token, 'UTF8'))
    and expires_at > now();
  if v_ch.request_id is null then
    return query select 'invalid'::text, null::text, null::text;
    return;
  end if;

  select * into v_req from club_verification_requests where id = v_ch.request_id;
  delete from club_verification_email_challenges where request_id = v_ch.request_id;
  if v_req.status <> 'pending' then
    return query select 'invalid'::text, null::text, null::text;
    return;
  end if;

  update club_verification_requests
     set proof_method = 'email',
         proof_verified_at = now(),
         proof_detail = v_ch.address
   where id = v_req.id;
  perform private.club_verification_log(v_req.id, v_req.club_id, null, 'proof_verified', 'email ' || v_ch.address);

  return query
    select 'confirmed'::text, c.name, c.slug from clubs c where c.id = v_req.club_id;
end;
$$;

revoke execute on function submit_club_verification(uuid, text, text) from public, anon;
revoke execute on function withdraw_club_verification(uuid) from public, anon;
revoke execute on function send_club_verification_email(uuid, text) from public, anon;
revoke execute on function confirm_club_verification_email(text) from public;
grant execute on function submit_club_verification(uuid, text, text) to authenticated;
grant execute on function withdraw_club_verification(uuid) to authenticated;
grant execute on function send_club_verification_email(uuid, text) to authenticated;
grant execute on function confirm_club_verification_email(text) to anon, authenticated;

-- ── 7. the Edge Function's writer (service_role) ────────────────────────────

-- One DNS / .well-known check result. On a pending request a pass records the
-- proof (a failure only stamps the time: the owner is still setting it up).
-- On an approval a pass resets the failure count, and a failure counts; the
-- third in a row lapses the approval and drops the badge.
create or replace function record_club_verification_check(
  p_request_id uuid,
  p_method text,
  p_ok boolean,
  p_detail text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req club_verification_requests%rowtype;
begin
  if p_method not in ('dns_txt', 'well_known') or p_ok is null then
    raise exception 'invalid check result' using errcode = '22023';
  end if;

  select * into v_req from club_verification_requests where id = p_request_id for update;
  if v_req.id is null or v_req.status not in ('pending', 'approved') then
    return 'not_live';
  end if;

  if v_req.status = 'pending' then
    if p_ok then
      update club_verification_requests
         set proof_method = p_method,
             proof_verified_at = now(),
             proof_detail = left(p_detail, 500),
             last_checked_at = now(),
             check_failures = 0
       where id = p_request_id;
      if v_req.proof_method is distinct from p_method then
        perform private.club_verification_log(p_request_id, v_req.club_id, null, 'proof_verified', p_method);
      end if;
      return 'verified';
    end if;
    update club_verification_requests set last_checked_at = now() where id = p_request_id;
    return 'not_found';
  end if;

  if p_ok then
    update club_verification_requests
       set last_checked_at = now(), check_failures = 0, proof_method = p_method
     where id = p_request_id;
    return 'verified';
  end if;

  update club_verification_requests
     set last_checked_at = now(), check_failures = check_failures + 1
   where id = p_request_id;
  perform private.club_verification_log(p_request_id, v_req.club_id, null, 'proof_failed', left(p_detail, 500));

  if v_req.check_failures + 1 >= 3 then
    perform private.lapse_club_verification(v_req.club_id, 'proof_missing', null);
    update clubs set is_verified = false where id = v_req.club_id;
    return 'lapsed';
  end if;
  return 'not_found';
end;
$$;

-- The approvals whose proof is due a re-check: proven by DNS or file, not
-- checked in the last 20 hours (so an hourly sweep reaches each about daily),
-- oldest first.
create or replace function club_verifications_due_for_recheck(p_limit integer default 10)
returns table (id uuid, domain text, token text)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.domain, r.token
  from club_verification_requests r
  where r.status = 'approved'
    and r.proof_method in ('dns_txt', 'well_known')
    and coalesce(r.last_checked_at, r.decided_at) < now() - interval '20 hours'
  order by coalesce(r.last_checked_at, r.decided_at)
  limit greatest(1, least(coalesce(p_limit, 10), 50));
$$;

revoke execute on function record_club_verification_check(uuid, text, boolean, text) from public, anon, authenticated;
revoke execute on function club_verifications_due_for_recheck(integer) from public, anon, authenticated;
grant execute on function record_club_verification_check(uuid, text, boolean, text) to service_role;
grant execute on function club_verifications_due_for_recheck(integer) to service_role;

-- ── 8. the site admin's RPCs ────────────────────────────────────────────────

create or replace function approve_club_verification(p_request_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_req club_verification_requests%rowtype;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not private.is_admin(v_uid) then
    raise exception 'approve_club_verification: not authorized' using errcode = '42501';
  end if;
  select * into v_req from club_verification_requests where id = p_request_id for update;
  if v_req.id is null or v_req.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = '22023';
  end if;
  if private.club_website_domain((select website_url from clubs where id = v_req.club_id))
       is distinct from v_req.domain then
    raise exception 'club_website_changed' using errcode = '22023';
  end if;
  if v_req.proof_verified_at is null and v_note is null then
    raise exception 'manual_review_note_required' using errcode = '22023';
  end if;
  if char_length(v_note) > 500 then
    raise exception 'note_too_long' using errcode = '22023';
  end if;

  update club_verification_requests
     set status = 'approved',
         decided_by = v_uid,
         decided_at = now(),
         decision_reason = v_note,
         proof_method = coalesce(proof_method, 'manual'),
         proof_verified_at = coalesce(proof_verified_at, now()),
         proof_detail = coalesce(proof_detail, v_note),
         check_failures = 0,
         last_checked_at = now()
   where id = p_request_id;
  update clubs set is_verified = true where id = v_req.club_id;

  perform private.club_verification_log(p_request_id, v_req.club_id, v_uid, 'approve', v_note);
  perform private.notify_club_verification(v_req.club_id);
end;
$$;

create or replace function reject_club_verification(p_request_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_req club_verification_requests%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not private.is_admin(v_uid) then
    raise exception 'reject_club_verification: not authorized' using errcode = '42501';
  end if;
  if v_reason is null or char_length(v_reason) > 500 then
    raise exception 'reason_required' using errcode = '22023';
  end if;
  select * into v_req from club_verification_requests where id = p_request_id for update;
  if v_req.id is null or v_req.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = '22023';
  end if;

  update club_verification_requests
     set status = 'rejected', decided_by = v_uid, decided_at = now(), decision_reason = v_reason
   where id = p_request_id;
  delete from club_verification_email_challenges where request_id = p_request_id;

  perform private.club_verification_log(p_request_id, v_req.club_id, v_uid, 'reject', v_reason);
  perform private.notify_club_verification(v_req.club_id);
end;
$$;

-- By club, not by request: a club verified before this flow existed has no
-- request to revoke, and still has a badge to take away.
create or replace function revoke_club_verification(p_club_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_request_id uuid;
begin
  if not private.is_admin(v_uid) then
    raise exception 'revoke_club_verification: not authorized' using errcode = '42501';
  end if;
  if v_reason is null or char_length(v_reason) > 500 then
    raise exception 'reason_required' using errcode = '22023';
  end if;
  if not exists (select 1 from clubs where id = p_club_id and is_verified) then
    raise exception 'club_not_verified' using errcode = '22023';
  end if;

  update club_verification_requests
     set status = 'revoked', closed_at = now(), closed_by = v_uid, close_reason = v_reason
   where club_id = p_club_id and status = 'approved'
  returning id into v_request_id;
  update clubs set is_verified = false where id = p_club_id;

  perform private.club_verification_log(v_request_id, p_club_id, v_uid, 'revoke', v_reason);
  perform private.notify_club_verification(p_club_id);
end;
$$;

-- The review queue. 'pending' is the requests awaiting a decision, 'verified'
-- every verified club (with its approval when it has one), 'closed' the
-- decided and closed requests of the last 180 days.
create or replace function club_verification_queue(p_view text default 'pending')
returns table (
  request_id        uuid,
  club_id           uuid,
  club_name         text,
  club_slug         text,
  club_website_url  text,
  club_is_verified  boolean,
  club_is_public    boolean,
  member_count      integer,
  owner_name        text,
  organisation      text,
  domain            text,
  note              text,
  status            text,
  proof_method      text,
  proof_verified_at timestamptz,
  proof_detail      text,
  last_checked_at   timestamptz,
  check_failures    integer,
  decision_reason   text,
  close_reason      text,
  created_at        timestamptz,
  decided_at        timestamptz,
  closed_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'club_verification_queue: not authorized' using errcode = '42501';
  end if;
  if p_view not in ('pending', 'verified', 'closed') then
    raise exception 'invalid view' using errcode = '22023';
  end if;

  if p_view = 'verified' then
    return query
      select r.id, c.id, c.name, c.slug, c.website_url, c.is_verified, coalesce(c.is_public, false),
             c.member_count, p.display_name, r.organisation, r.domain, r.note, r.status,
             r.proof_method, r.proof_verified_at, r.proof_detail, r.last_checked_at,
             r.check_failures, r.decision_reason, r.close_reason, r.created_at, r.decided_at, r.closed_at
      from clubs c
      left join club_verification_requests r on r.club_id = c.id and r.status = 'approved'
      left join user_profiles p on p.id = c.owner_id
      where c.is_verified
      order by c.name, c.id;
    return;
  end if;

  return query
    select r.id, c.id, c.name, c.slug, c.website_url, c.is_verified, coalesce(c.is_public, false),
           c.member_count, p.display_name, r.organisation, r.domain, r.note, r.status,
           r.proof_method, r.proof_verified_at, r.proof_detail, r.last_checked_at,
           r.check_failures, r.decision_reason, r.close_reason, r.created_at, r.decided_at, r.closed_at
    from club_verification_requests r
    join clubs c on c.id = r.club_id
    left join user_profiles p on p.id = c.owner_id
    where (p_view = 'pending' and r.status = 'pending')
       or (p_view = 'closed' and r.status in ('rejected', 'revoked', 'lapsed', 'withdrawn')
           and coalesce(r.closed_at, r.decided_at) > now() - interval '180 days')
    order by case when p_view = 'pending' then r.created_at end asc,
             coalesce(r.closed_at, r.decided_at) desc,
             r.id;
end;
$$;

create or replace function club_verification_audit_log(p_club_id uuid)
returns table (
  id         bigint,
  request_id uuid,
  club_name  text,
  actor_name text,
  action     text,
  detail     text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'club_verification_audit_log: not authorized' using errcode = '42501';
  end if;
  return query
    select a.id, a.request_id, a.club_name, p.display_name, a.action, a.detail, a.created_at
    from club_verification_audit a
    left join user_profiles p on p.id = a.actor_id
    where a.club_id = p_club_id
    order by a.created_at desc, a.id desc
    limit 200;
end;
$$;

revoke execute on function approve_club_verification(uuid, text) from public, anon;
revoke execute on function reject_club_verification(uuid, text) from public, anon;
revoke execute on function revoke_club_verification(uuid, text) from public, anon;
revoke execute on function club_verification_queue(text) from public, anon;
revoke execute on function club_verification_audit_log(uuid) from public, anon;
grant execute on function approve_club_verification(uuid, text) to authenticated;
grant execute on function reject_club_verification(uuid, text) to authenticated;
grant execute on function revoke_club_verification(uuid, text) to authenticated;
grant execute on function club_verification_queue(text) to authenticated;
grant execute on function club_verification_audit_log(uuid) to authenticated;

-- ── 9. the re-check schedule ────────────────────────────────────────────────

-- Hourly; each run re-checks at most ten due approvals, so a day covers 240.
-- Fails closed on configuration like invoke_race_listings_sweep: with either
-- Vault secret missing (`club_verification_recheck_url`, `cron_secret`) it
-- returns NULL and calls nothing. Arming is an operator step
-- (docs/ops/deployment.md).
create or replace function public.invoke_club_verification_recheck()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'club_verification_recheck_url';
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  return net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secret,
      'Content-Type', 'application/json'
    ),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function public.invoke_club_verification_recheck() from public, anon, authenticated;
grant execute on function public.invoke_club_verification_recheck() to service_role;

select cron.schedule(
  'club-verification-recheck',
  '17 * * * *',
  $$select public.invoke_club_verification_recheck()$$
);
