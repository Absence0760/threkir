-- Pins 20271224000100 (audit of PR #1359, Low): anon holds no SELECT on any
-- column of direct_message_reactions or direct_message_images, while
-- authenticated keeps the reads its policies serve.

begin;
select plan(4);

select is(
  (select coalesce(string_agg(a.attname, ', ' order by a.attname), '')
     from pg_attribute a
    where a.attrelid = 'public.direct_message_reactions'::regclass
      and a.attnum > 0 and not a.attisdropped
      and has_column_privilege('anon', a.attrelid, a.attnum, 'SELECT')),
  '',
  'anon selects no column of direct_message_reactions');

select is(
  (select coalesce(string_agg(a.attname, ', ' order by a.attname), '')
     from pg_attribute a
    where a.attrelid = 'public.direct_message_images'::regclass
      and a.attnum > 0 and not a.attisdropped
      and has_column_privilege('anon', a.attrelid, a.attnum, 'SELECT')),
  '',
  'anon selects no column of direct_message_images');

select ok(
  has_table_privilege('authenticated', 'public.direct_message_reactions', 'SELECT'),
  'authenticated still reads direct_message_reactions');

select ok(
  has_column_privilege('authenticated', 'public.direct_message_images', 'storage_path', 'SELECT')
    and not has_column_privilege('authenticated', 'public.direct_message_images', 'upload_path', 'SELECT'),
  'authenticated keeps its column grant on direct_message_images, upload_path still withheld');

select * from finish();
rollback;
