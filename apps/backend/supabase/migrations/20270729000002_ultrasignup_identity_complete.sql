-- An UltraSignup identity row must carry the whole identity (decisions
-- § 1853, following § 1841).
--
-- integrations_ultrasignup_identity_chk (20270726000003) read
--
--   provider <> 'ultrasignup'
--   or (external_id ~ '^[0-9]{1,12}$' and external_first_name is not null)
--
-- and a CHECK passes when its expression is NULL. With external_id NULL the
-- regex match is NULL, the AND is NULL, and the OR is NULL — so an UltraSignup
-- row with no person id at all was accepted, the one shape the constraint was
-- written to refuse. It also admitted `0` and zero-padded ids (the feed's
-- zero means "none", and race-results-import canonicalises `0138805` to
-- `138805`), and a blank name, which cannot be fetched with.
--
-- The replacement states every half explicitly and is NULL-proof: the id is
-- present and a canonical positive integer of at most 12 digits, and both
-- names are present and not blank. The pair and length checks are unchanged.
--
-- Lock profile (migration_locks.md): integrations is one row per user per
-- provider and UltraSignup rows exist only behind ULTRASIGNUP_RESULTS_ENABLED,
-- so the DROP + ADD NOT VALID + VALIDATE runs in one file, as
-- 20270726000003's own swap on this table did.

alter table public.integrations
  drop constraint integrations_ultrasignup_identity_chk;

alter table public.integrations
  add constraint integrations_ultrasignup_identity_chk
    check (
      provider <> 'ultrasignup'
      or (
        external_id is not null
        and external_id ~ '^[1-9][0-9]{0,11}$'
        and external_first_name is not null
        and external_last_name is not null
        and btrim(external_first_name) <> ''
        and btrim(external_last_name) <> ''
      )
    ) not valid;

alter table public.integrations
  validate constraint integrations_ultrasignup_identity_chk;
