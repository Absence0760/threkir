-- Pins the indexes behind the roster keyset orders (migration
-- 20270817000021): the club roster pages `where club_id = $1 order by
-- joined_at, user_id` and an occurrence's attendees `where event_id = $1 and
-- instance_start = $2 order by joined_at, user_id`, both ascending with nulls
-- last. Asserted by key columns in order, with no expression and no
-- predicate, so a rename survives but a reordered, partial or missing index
-- fails — and with it the access path that lets the LIMIT end the scan
-- instead of sorting the whole club or occurrence on every page. Also pins
-- that the left-prefix (event_id, instance_start) index stays dropped.

begin;

select plan(5);

create or replace function pg_temp.has_key_index(tbl text, cols text[])
returns boolean language sql stable as $fn$
  select exists (
    select 1
    from pg_index ix
    join pg_class t on t.oid = ix.indrelid
    join pg_class i on i.oid = ix.indexrelid
    join pg_am am on am.oid = i.relam
    where t.relnamespace = 'public'::regnamespace
      and t.relname = tbl
      and am.amname = 'btree'
      and ix.indpred is null
      and ix.indexprs is null
      and ix.indnkeyatts = cardinality(cols)
      and (
        select array_agg(a.attname::text order by k.ord)
        from unnest(ix.indkey::int2[]) with ordinality as k(attnum, ord)
        join pg_attribute a on a.attrelid = t.oid and a.attnum = k.attnum
        where k.ord <= ix.indnkeyatts
      ) = cols
      -- every key ascending, nulls last: indoption bit 1 = DESC, bit 2 = NULLS FIRST
      and not exists (
        select 1 from unnest(ix.indoption::int2[]) as o(opt) where o.opt <> 0
      )
  );
$fn$;

select ok(
  pg_temp.has_key_index('club_members', array['club_id', 'joined_at', 'user_id']),
  'club_members has a plain btree on (club_id, joined_at, user_id), all asc nulls last'
);

select ok(
  pg_temp.has_key_index(
    'event_attendees',
    array['event_id', 'instance_start', 'joined_at', 'user_id']
  ),
  'event_attendees has a plain btree on (event_id, instance_start, joined_at, user_id), all asc nulls last'
);

select has_index(
  'public', 'event_attendees', 'event_attendees_instance_roster',
  'event_attendees_instance_roster exists'
);

select ok(
  not exists (
    select 1 from pg_class i
    join pg_namespace n on n.oid = i.relnamespace
    where n.nspname = 'public' and i.relname = 'event_attendees_event_instance'
  ),
  'the left-prefix event_attendees_event_instance index is dropped'
);

select ok(
  pg_temp.has_key_index('event_attendees', array['event_id', 'instance_start'])
    = false,
  'no plain (event_id, instance_start) btree remains beside the roster index'
);

select * from finish();

rollback;
