-- Audience sharing, part 2: named-person grants on a run or a route.
--
-- One row = "the owner lets this one person read this one run (or route)".
-- A grant never makes anything public and never reaches a feed, a
-- notification or a listing: those surfaces all key on `is_public`, which a
-- grant does not touch. What the recipient reads is decided at READ time by
-- private.is_run_visible_to / is_route_visible_to and the shared_* views
-- (20270802000003), so a revoke ends access on the next request.
--
-- Revocation is a hard DELETE, not a `revoked_at` stamp (§ 1876). Access
-- is the row's existence, so a stamped row would need every one of the read
-- paths to remember a second predicate, and the only thing a tombstone keeps
-- is a record of who the owner once shared with — personal data with no
-- reader. Re-sharing is a fresh insert.
--
-- Who may be named mirrors the direct_messages INSERT gate (20261026_001) and
-- the picker that already serves it (social/dm_recipients.ts): a follow edge
-- in either direction and no block either way. A grant to a stranger is
-- refused here rather than only hidden by the picker, because "you may only
-- share with people you are connected to" is an invariant of the rail, not of
-- the one dialog that writes it today (§ 772's reasoning).
--
-- `owner_id` duplicates runs.user_id / routes.user_id on purpose: the Art 20
-- export filters each table by a column (`owner_id=eq.<uid>`), and the owner
-- policies compare against it without a join. The INSERT policy pins it to
-- the entity's real owner, and no UPDATE grant exists, so it cannot drift.
--
-- All three FKs cascade: deleting the run / route, the owner's account, or
-- the recipient's account removes the grant (Art 17 needs nothing extra).

create table public.run_shares (
  id           uuid primary key default gen_random_uuid(),
  run_id       uuid not null references public.runs(id) on delete cascade,
  owner_id     uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now(),
  constraint run_shares_not_self check (recipient_id <> owner_id),
  constraint run_shares_run_recipient_key unique (run_id, recipient_id)
);

create index run_shares_owner_id_idx on public.run_shares (owner_id);
create index run_shares_recipient_id_idx on public.run_shares (recipient_id);

create table public.route_shares (
  id           uuid primary key default gen_random_uuid(),
  route_id     uuid not null references public.routes(id) on delete cascade,
  owner_id     uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now(),
  constraint route_shares_not_self check (recipient_id <> owner_id),
  constraint route_shares_route_recipient_key unique (route_id, recipient_id)
);

create index route_shares_owner_id_idx on public.route_shares (owner_id);
create index route_shares_recipient_id_idx on public.route_shares (recipient_id);

comment on table public.run_shares is
  'Named-person read grants on a private run (decisions § 1876). Revoke = delete.';
comment on table public.route_shares is
  'Named-person read grants on a private route (decisions § 1876). Revoke = delete.';

-- The connection test both INSERT policies share. A definer because
-- user_blocks is owner-read only: an RLS-visible subquery would see only the
-- caller's own blocks and miss a block the recipient placed on the owner.
create or replace function private.can_share_with(p_owner uuid, p_recipient uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_owner is not null
     and p_recipient is not null
     and p_owner <> p_recipient
     and exists (
       select 1 from user_follows f
        where (f.follower_id = p_owner and f.followee_id = p_recipient)
           or (f.follower_id = p_recipient and f.followee_id = p_owner)
     )
     and not exists (
       select 1 from user_blocks b
        where (b.blocker_id = p_owner and b.blocked_id = p_recipient)
           or (b.blocker_id = p_recipient and b.blocked_id = p_owner)
     );
$$;

revoke execute on function private.can_share_with(uuid, uuid) from public, anon;
grant execute on function private.can_share_with(uuid, uuid) to authenticated, service_role;

alter table public.run_shares enable row level security;
alter table public.route_shares enable row level security;

create policy "owner and recipient read run shares"
  on public.run_shares for select
  to authenticated
  using (owner_id = (select auth.uid()) or recipient_id = (select auth.uid()));

create policy "owner shares own run with a connection"
  on public.run_shares for insert
  to authenticated
  with check (
    owner_id = (select auth.uid())
    and (select private.audience_sharing_enabled())
    and exists (
      select 1 from runs r
       where r.id = run_shares.run_id
         and r.user_id = (select auth.uid())
    )
    and private.can_share_with(owner_id, recipient_id)
  );

create policy "owner revokes run shares"
  on public.run_shares for delete
  to authenticated
  using (owner_id = (select auth.uid()));

create policy "owner and recipient read route shares"
  on public.route_shares for select
  to authenticated
  using (owner_id = (select auth.uid()) or recipient_id = (select auth.uid()));

create policy "owner shares own route with a connection"
  on public.route_shares for insert
  to authenticated
  with check (
    owner_id = (select auth.uid())
    and (select private.audience_sharing_enabled())
    and exists (
      select 1 from routes r
       where r.id = route_shares.route_id
         and r.user_id = (select auth.uid())
    )
    and private.can_share_with(owner_id, recipient_id)
  );

create policy "owner revokes route shares"
  on public.route_shares for delete
  to authenticated
  using (owner_id = (select auth.uid()));

revoke all on table public.run_shares from public, anon, authenticated;
revoke all on table public.route_shares from public, anon, authenticated;
grant select, insert, delete on table public.run_shares to authenticated;
grant select, insert, delete on table public.route_shares to authenticated;
grant select, insert, update, delete on table public.run_shares to service_role;
grant select, insert, update, delete on table public.route_shares to service_role;
