-- The Sign in with Apple refresh token kept for revocation on account
-- deletion (20270714000001). It is a live credential, so the properties
-- that matter are who can reach it and that nothing survives the account:
-- reading it is not consuming it (a deletion that aborts can retry), a
-- re-store replaces rather than accumulates, the auth.users cascade takes
-- the Vault secret with the row, and no client role can read, write or
-- read back a token.

begin;
select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a991e000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'apple-owner@siwa.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select lives_ok(
  $$select public.set_apple_refresh_token('a991e000-0000-0000-0000-000000000001', 'com.threkir.app', 'r.first')$$,
  'the service role can store a token'
);
select lives_ok(
  $$select public.set_apple_refresh_token('a991e000-0000-0000-0000-000000000001', 'com.threkir.app', 'r.second')$$,
  'a re-sign-in stores again'
);
select is(
  (select count(*)::int from vault.secrets where name = 'apple_refresh_a991e000-0000-0000-0000-000000000001'),
  1,
  'the re-store replaced the secret rather than adding a second'
);
select throws_ok(
  $$select public.set_apple_refresh_token('a991e000-0000-0000-0000-000000000001', 'com.threkir.app', '')$$,
  'P0001',
  'set_apple_refresh_token: empty token',
  'an empty token is refused'
);

reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a991e000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$select * from public.get_apple_refresh_token('a991e000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'the owner cannot read their own token back: only delete-account may'
);
select throws_ok(
  $$select public.set_apple_refresh_token('a991e000-0000-0000-0000-000000000001', 'x', 'forged')$$,
  '42501',
  null,
  'a client cannot plant a token'
);
select throws_ok(
  $$select * from public.apple_sign_in_tokens$$,
  '42501',
  null,
  'a client cannot read the table'
);

reset role;
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$select * from public.get_apple_refresh_token('a991e000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'anon cannot read a token'
);

reset role;
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select results_eq(
  $$select client_id, refresh_token from public.get_apple_refresh_token('a991e000-0000-0000-0000-000000000001')$$,
  $$values ('com.threkir.app'::text, 'r.second'::text)$$,
  'the latest token and its client come back'
);
select results_eq(
  $$select client_id, refresh_token from public.get_apple_refresh_token('a991e000-0000-0000-0000-000000000001')$$,
  $$values ('com.threkir.app'::text, 'r.second'::text)$$,
  'reading does not consume it, so an aborted deletion can retry the revoke'
);
select is_empty(
  $$select * from public.get_apple_refresh_token('a991e000-0000-0000-0000-0000000000ff')$$,
  'an account that never signed in with Apple has nothing to read'
);

reset role;
-- A row whose secret has vanished must not read as "nothing to revoke".
delete from vault.secrets where name = 'apple_refresh_a991e000-0000-0000-0000-000000000001';
select throws_ok(
  $$select * from public.get_apple_refresh_token('a991e000-0000-0000-0000-000000000001')$$,
  'P0001',
  null,
  'a row with no secret raises, so the deletion records a failure'
);

select public.set_apple_refresh_token('a991e000-0000-0000-0000-000000000001', 'com.threkir.app', 'r.third');
delete from auth.users where id = 'a991e000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.apple_sign_in_tokens where user_id = 'a991e000-0000-0000-0000-000000000001'),
  0,
  'the auth.users cascade removes the row'
);
select is(
  (select count(*)::int from vault.secrets where name = 'apple_refresh_a991e000-0000-0000-0000-000000000001'),
  0,
  'and the trigger removes the Vault secret with it, so no credential outlives the account'
);

select * from finish();
rollback;
