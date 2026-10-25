-- Pins migration 20271023000001 — the sign-up consent stamp lands when the
-- account is confirmed (issue #1229).
--
-- Behaviour pinned:
--
--   1. An unconfirmed sign-up with consent metadata gets no stamp yet.
--   2. Confirming it (GoTrue sets email_confirmed_at) stamps both
--      columns with the metadata timestamps, and seeds preferred_unit.
--   3. A sign-up that is confirmed at insert (confirmation off) is stamped.
--   4. No metadata (OAuth, a direct GoTrue call) leaves no stamp.
--   5. An existing stamp is not overwritten (first stamp wins).
--   6. Malformed, partial, future or long-before-sign-up metadata leaves
--      the columns NULL, so the gate still asks.
--   7. Writing metadata after confirmation stamps nothing: only the
--      confirmation transition reads it.
--   8. With the signup_consent_from_metadata flag off (no row, the prod
--      default until sign-off) nothing is stamped.

begin;
select plan(17);

select has_function(
  'private', 'stamp_signup_consent', ARRAY[]::text[],
  'private.stamp_signup_consent() must exist'
);

-- (8) first, with the gate closed.
delete from private.feature_flags where name = 'signup_consent_from_metadata';
insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role, raw_user_meta_data, created_at)
  values ('88888888-8888-8888-8888-888888888800', 'signup-consent-closed@example.com',
          '', now(), '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', jsonb_build_object(
            'age_confirmed_at', (now() - interval '1 minute')::text,
            'terms_accepted_at', (now() - interval '1 minute')::text), now());
select is(
  (select count(*)::int from public.user_profiles
    where id = '88888888-8888-8888-8888-888888888800'),
  0,
  'with the flag off, a confirmed sign-up is not stamped from metadata'
);
insert into private.feature_flags (name, enabled)
  values ('signup_consent_from_metadata', true);

-- Fixtures. Each user's metadata is built relative to now() so the window
-- check sees a stamp taken just before sign-up.
create temp table t_users (label text primary key, id uuid);
insert into t_users values
  ('pending',   '88888888-8888-8888-8888-888888888801'),
  ('autoconf',  '88888888-8888-8888-8888-888888888802'),
  ('nometa',    '88888888-8888-8888-8888-888888888803'),
  ('stamped',   '88888888-8888-8888-8888-888888888804'),
  ('garbage',   '88888888-8888-8888-8888-888888888805'),
  ('partial',   '88888888-8888-8888-8888-888888888806'),
  ('future',    '88888888-8888-8888-8888-888888888807'),
  ('ancient',   '88888888-8888-8888-8888-888888888808'),
  ('late',      '88888888-8888-8888-8888-888888888809'),
  ('badzone',   '88888888-8888-8888-8888-888888888810'),
  ('badoffset', '88888888-8888-8888-8888-888888888811');

create function pg_temp.mk(p_label text, p_meta jsonb, p_confirmed boolean)
returns void language sql as $$
  insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                          instance_id, aud, role, raw_user_meta_data, created_at)
  select id, 'signup-consent-' || p_label || '@example.com', '',
         case when p_confirmed then now() end,
         '00000000-0000-0000-0000-000000000000', 'authenticated',
         'authenticated', p_meta, now()
    from t_users where label = p_label;
$$;

create function pg_temp.stamp(p_label text)
returns timestamptz language sql as $$
  select p.age_confirmed_at from public.user_profiles p
    join t_users u on u.id = p.id where u.label = p_label;
$$;

select pg_temp.mk('pending', jsonb_build_object(
  'age_confirmed_at', (now() - interval '2 minutes')::text,
  'terms_accepted_at', (now() - interval '2 minutes')::text,
  'preferred_unit', 'mi'), false);
select pg_temp.mk('autoconf', jsonb_build_object(
  'age_confirmed_at', (now() - interval '1 minute')::text,
  'terms_accepted_at', (now() - interval '1 minute')::text), true);
select pg_temp.mk('nometa', '{}'::jsonb, false);
select pg_temp.mk('stamped', jsonb_build_object(
  'age_confirmed_at', (now() - interval '1 minute')::text,
  'terms_accepted_at', (now() - interval '1 minute')::text), false);
select pg_temp.mk('garbage', jsonb_build_object(
  'age_confirmed_at', 'yesterday-ish',
  'terms_accepted_at', 'not a date'), false);
select pg_temp.mk('partial', jsonb_build_object(
  'age_confirmed_at', (now() - interval '1 minute')::text), false);
select pg_temp.mk('future', jsonb_build_object(
  'age_confirmed_at', (now() + interval '3 hours')::text,
  'terms_accepted_at', (now() + interval '3 hours')::text), false);
select pg_temp.mk('ancient', jsonb_build_object(
  'age_confirmed_at', (now() - interval '30 days')::text,
  'terms_accepted_at', (now() - interval '30 days')::text), false);
select pg_temp.mk('late', '{}'::jsonb, false);
-- An unknown zone name (22023) and an out-of-range offset (22009) raise
-- outside the datetime-format codes; they must leave no stamp, not abort.
select pg_temp.mk('badzone', jsonb_build_object(
  'age_confirmed_at', '2026-01-01 00:00 Foo/Bar',
  'terms_accepted_at', '2026-01-01 00:00 Foo/Bar'), false);
select pg_temp.mk('badoffset', jsonb_build_object(
  'age_confirmed_at', '2026-01-01 00:00 +99:00',
  'terms_accepted_at', '2026-01-01 00:00 +99:00'), false);

-- An earlier stamp already on record for 'stamped'.
insert into public.user_profiles (id, age_confirmed_at, terms_accepted_at,
                                  preferred_unit, subscription_tier)
  select id, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 'km', 'free'
    from t_users where label = 'stamped';

-- (1)
select is(
  (select count(*)::int from public.user_profiles p join t_users u on u.id = p.id
    where u.label = 'pending'),
  0,
  'an unconfirmed sign-up has no stamp yet'
);

-- (3)
select isnt(pg_temp.stamp('autoconf'), null,
  'a sign-up confirmed at insert is stamped from its metadata');

-- Confirm everyone still pending, as GoTrue's verify does.
update auth.users set email_confirmed_at = now()
  where id in (select id from t_users) and email_confirmed_at is null;

-- (2)
select is(
  pg_temp.stamp('pending'),
  (select (raw_user_meta_data->>'age_confirmed_at')::timestamptz
     from auth.users where id = '88888888-8888-8888-8888-888888888801'),
  'confirming stamps the age affirmation with the metadata timestamp'
);
select isnt(
  (select terms_accepted_at from public.user_profiles
    where id = '88888888-8888-8888-8888-888888888801'),
  null,
  'confirming stamps the terms acceptance'
);
select is(
  (select preferred_unit from public.user_profiles
    where id = '88888888-8888-8888-8888-888888888801'),
  'mi',
  'the row the trigger creates takes the sign-up unit'
);

-- (4)
select is(
  (select count(*)::int from public.user_profiles p join t_users u on u.id = p.id
    where u.label = 'nometa'),
  0,
  'no metadata, no stamp'
);

-- (5)
select is(pg_temp.stamp('stamped'), '2026-01-01T00:00:00Z'::timestamptz,
  'an existing stamp is not overwritten');

-- (6)
select is(pg_temp.stamp('garbage'), null, 'malformed metadata leaves no stamp');
select is(pg_temp.stamp('partial'), null, 'age without terms leaves no stamp');
select is(pg_temp.stamp('badzone'), null,
  'an unknown zone name leaves no stamp and does not block confirmation');
select is(
  (select email_confirmed_at is not null from auth.users
    where id = '88888888-8888-8888-8888-888888888811'),
  true,
  'an out-of-range offset still lets the account confirm');
select is(pg_temp.stamp('future'), null, 'a future stamp is not trusted');
select is(pg_temp.stamp('ancient'), null,
  'a stamp long before sign-up is not trusted');

-- (7)
update auth.users
   set raw_user_meta_data = jsonb_build_object(
     'age_confirmed_at', now()::text, 'terms_accepted_at', now()::text)
 where id = '88888888-8888-8888-8888-888888888809';
select is(pg_temp.stamp('late'), null,
  'metadata written after confirmation stamps nothing');

-- The gate beneath still holds for the unstamped: no row, no writes.
select is(
  (select count(*)::int from public.user_profiles p join t_users u on u.id = p.id
    where u.label in ('nometa', 'late') and p.age_confirmed_at is not null),
  0,
  'accounts without a trusted stamp still meet the consent gate'
);

select * from finish();
rollback;
