-- The Sign in with Apple refresh token kept for revocation on account
-- deletion (20270714000001). It is a live credential, so the properties
-- that matter are who can reach it and that taking it leaves nothing behind:
-- no Vault secret survives a take, a re-store replaces rather than
-- accumulates, and no client role can read, write or take one.

begin;
select plan(13);

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
  $$select * from public.take_apple_refresh_token('a991e000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'the owner cannot take their own token: only delete-account may'
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
  $$select * from public.take_apple_refresh_token('a991e000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'anon cannot take a token'
);

reset role;
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select results_eq(
  $$select client_id, refresh_token from public.take_apple_refresh_token('a991e000-0000-0000-0000-000000000001')$$,
  $$values ('com.threkir.app'::text, 'r.second'::text)$$,
  'take returns the latest token and its client'
);
select is(
  (select count(*)::int from public.apple_sign_in_tokens where user_id = 'a991e000-0000-0000-0000-000000000001'),
  0,
  'take deletes the row'
);
select is(
  (select count(*)::int from vault.secrets where name = 'apple_refresh_a991e000-0000-0000-0000-000000000001'),
  0,
  'take deletes the Vault secret, so a deletion leaves no credential behind'
);
select is_empty(
  $$select * from public.take_apple_refresh_token('a991e000-0000-0000-0000-000000000001')$$,
  'a second take finds nothing'
);
select is_empty(
  $$select * from public.take_apple_refresh_token('a991e000-0000-0000-0000-0000000000ff')$$,
  'an account that never signed in with Apple has nothing to take'
);

select * from finish();
rollback;
