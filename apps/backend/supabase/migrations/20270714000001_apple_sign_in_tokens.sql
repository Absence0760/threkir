-- Sign in with Apple token revocation on account deletion (App Store
-- Guideline 5.1.1(v)). Apple requires an app that offers Sign in with Apple
-- to revoke the user's Apple tokens when the account is deleted, and the
-- only token it accepts for that is one we obtained ourselves: the native
-- flow hands the app a one-time authorization code, which the
-- apple-token-exchange Edge Function trades for a refresh token, and web's
-- OAuth callback carries the refresh token GoTrue received. Neither survives
-- long enough to be fetched at deletion time, so it is kept here until then.
--
-- The token is a live credential, so it lives in Vault exactly like the
-- integration tokens (20260603_001), and nothing but the service role can
-- reach the row or either function. Deleting the row, by any path, deletes
-- the secret.

create table public.apple_sign_in_tokens (
  user_id                 uuid primary key references auth.users(id) on delete cascade,
  -- The Apple client the token was issued to: the app's bundle id for the
  -- native flow, the Services ID for web. Revocation must name the same one.
  client_id               text not null check (client_id <> ''),
  refresh_token_secret_id uuid not null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table public.apple_sign_in_tokens is
  'Vault reference to the Sign in with Apple refresh token, kept only so '
  'delete-account can revoke it (Guideline 5.1.1(v)). Service-role only.';

alter table public.apple_sign_in_tokens enable row level security;
revoke all on table public.apple_sign_in_tokens from public, anon, authenticated;
grant select, insert, update, delete on table public.apple_sign_in_tokens to service_role;

create or replace function public.set_apple_refresh_token(
  p_user_id uuid,
  p_client_id text,
  p_refresh_token text
)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_existing uuid;
  v_secret_id uuid;
begin
  if p_refresh_token is null or p_refresh_token = '' then
    raise exception 'set_apple_refresh_token: empty token';
  end if;

  select refresh_token_secret_id into v_existing
    from apple_sign_in_tokens
    where user_id = p_user_id;

  -- Update in place so a re-sign-in replaces the credential rather than
  -- leaving the previous one behind in Vault.
  if v_existing is not null then
    perform vault.update_secret(v_existing, p_refresh_token);
    v_secret_id := v_existing;
  else
    v_secret_id := vault.create_secret(
      p_refresh_token,
      format('apple_refresh_%s', p_user_id),
      format('Sign in with Apple refresh token for user=%s', p_user_id)
    );
  end if;

  insert into apple_sign_in_tokens (user_id, client_id, refresh_token_secret_id)
    values (p_user_id, p_client_id, v_secret_id)
    on conflict (user_id) do update
      set client_id = excluded.client_id,
          refresh_token_secret_id = excluded.refresh_token_secret_id,
          updated_at = now();
end;
$$;

revoke execute on function public.set_apple_refresh_token(uuid, text, text) from public, anon, authenticated;
grant execute on function public.set_apple_refresh_token(uuid, text, text) to service_role;

-- Read-only on purpose. delete-account revokes just before it deletes the
-- auth user, and the row goes with that cascade, so a deletion that aborts
-- earlier keeps the token for its retry. An Apple call that fails does not
-- abort the erasure (no third-party failure does): it is recorded as
-- 'failed' and the token goes with the account. A row whose Vault secret is
-- gone raises, so the caller records a failure rather than "nothing to
-- revoke".
create or replace function public.get_apple_refresh_token(p_user_id uuid)
returns table (client_id text, refresh_token text)
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_client_id text;
  v_secret_id uuid;
  v_token text;
begin
  select t.client_id, t.refresh_token_secret_id into v_client_id, v_secret_id
    from apple_sign_in_tokens t
    where t.user_id = p_user_id;
  if not found then
    return;
  end if;

  select decrypted_secret into v_token
    from vault.decrypted_secrets
    where id = v_secret_id;
  if v_token is null then
    raise exception 'get_apple_refresh_token: Vault secret % missing for user %', v_secret_id, p_user_id;
  end if;

  return query select v_client_id, v_token;
end;
$$;

revoke execute on function public.get_apple_refresh_token(uuid) from public, anon, authenticated;
grant execute on function public.get_apple_refresh_token(uuid) to service_role;

-- However the row goes, the secret goes with it: the auth.users cascade at
-- the end of delete-account, an operator deleting a user from the dashboard,
-- or a direct delete. Without this the cascade would orphan the credential
-- in Vault, which nothing else sweeps.
create or replace function public.apple_sign_in_tokens_drop_secret()
returns trigger
language plpgsql
security definer
set search_path = public, vault
as $$
begin
  delete from vault.secrets where id = old.refresh_token_secret_id;
  return old;
end;
$$;

revoke execute on function public.apple_sign_in_tokens_drop_secret() from public, anon, authenticated;

create trigger apple_sign_in_tokens_drop_secret
  after delete on public.apple_sign_in_tokens
  for each row execute function public.apple_sign_in_tokens_drop_secret();

-- The audit column's documented vocabulary predates the Apple revoke.
comment on column public.deletion_audit_log.third_party_outcomes is
  'Structured per-third-party cleanup outcomes recorded by delete-account. '
  'Keys: strava_deauth, garmin_deauth, revenuecat_delete, fcm_remove, '
  'stripe_connect_delete, apple_revoke. Values: ok | skipped | failed, and '
  'not_reached for apple_revoke on a deletion that aborted before it ran. '
  'Evidence trail for GDPR Art 17(2).';
