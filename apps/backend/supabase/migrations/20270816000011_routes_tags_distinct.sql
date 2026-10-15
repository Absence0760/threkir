-- A route's tags are a set: no tag is stored twice.
--
-- `routes.tags` is a `text[]` with nothing behind it but the web tag editor's
-- own `includes()` check. Every other writer stores whatever it is handed: the
-- web and mobile backup restores copy the archived array verbatim, mobile's
-- `saveRoute` round-trips `Route.tags`, and any signed-in owner can PATCH the
-- column through PostgREST directly. The web renders the array in two keyed
-- `{#each … (t)}` blocks (route detail, route explorer card), so one duplicate
-- throws Svelte's each_key_duplicate and takes the page into the 500 boundary.
-- A per-writer dedupe can only cover the writers this repo owns, so the set
-- invariant belongs to the column.
--
--   1. `private.distinct_text_array` — the canonical form: NULL elements
--      dropped, each value kept at its FIRST position. Exact (byte) equality,
--      no case folding or trimming: the tag editor already lower-cases what it
--      writes, and a set rule is not the place to redefine what a tag is.
--   2. `routes_tags_distinct` — a BEFORE trigger that rewrites `new.tags` into
--      that form on every insert and every write of the column. It normalises
--      rather than refuses, so a restore or an older client that hands over a
--      duplicate still saves, with the duplicate gone.
--   3. `routes_tags_distinct_check` — the floor under the trigger, for a write
--      that bypasses triggers (`session_replication_role = replica`, a
--      pg_restore). Added NOT VALID here; validated in 20270816000012, in its
--      own transaction, per migration_locks.md.
--
-- The function is a pure array transform that reads no table, so EXECUTE is
-- left to PUBLIC and stated as such: a CHECK naming a function ACL-checks it
-- against the role performing the write (20270623000001 records that trap), and
-- every role that can write `routes` must be able to evaluate it. `private` is
-- not a PostgREST-exposed schema, so this grant exposes no RPC.
--
-- Lock profile: CREATE FUNCTION locks no table. CREATE TRIGGER takes SHARE ROW
-- EXCLUSIVE on routes (readers proceed; writers wait) and that lock is held
-- through the backfill below, which is why the trigger comes first — a write
-- that commits between a backfill and a later trigger would escape both and
-- fail the VALIDATE. `routes` is not one of the high-volume tables, and the
-- backfill is scoped to rows that actually carry a duplicate and batched by
-- primary key. ADD CONSTRAINT … NOT VALID is a metadata flip with no scan, and
-- goes last so its ACCESS EXCLUSIVE is held for the shortest span.

create or replace function private.distinct_text_array(p_values text[])
returns text[]
language sql
immutable
parallel safe
returns null on null input
set search_path = ''
as $$
  select coalesce(array_agg(firsts.v order by firsts.first_at), '{}'::text[])
  from (
    select u.v, min(u.ord) as first_at
    from unnest(p_values) with ordinality as u(v, ord)
    where u.v is not null
    group by u.v
  ) as firsts;
$$;

comment on function private.distinct_text_array(text[]) is
  'Canonical set form of a text[]: NULL elements dropped, each value kept at its first position, exact equality. Backs the routes.tags set invariant (trigger routes_tags_distinct + CHECK routes_tags_distinct_check).';

grant execute on function private.distinct_text_array(text[]) to public;

create or replace function private.routes_tags_distinct()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.tags := private.distinct_text_array(new.tags);
  return new;
end;
$$;

create trigger routes_tags_distinct
  before insert or update of tags on public.routes
  for each row execute function private.routes_tags_distinct();

do $$
declare
  batch_size constant integer := 1000;
  touched integer;
begin
  loop
    with candidates as (
      select id
      from public.routes
      where tags is distinct from private.distinct_text_array(tags)
      order by id
      limit batch_size
    )
    update public.routes r
    set tags = private.distinct_text_array(r.tags)
    from candidates c
    where r.id = c.id;
    get diagnostics touched = row_count;
    exit when touched = 0;
  end loop;
end;
$$;

alter table public.routes
  add constraint routes_tags_distinct_check
  check (tags = private.distinct_text_array(tags))
  not valid;
