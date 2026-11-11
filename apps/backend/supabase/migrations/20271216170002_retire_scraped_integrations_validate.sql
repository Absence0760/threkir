-- Validate the provider vocabularies 20271216170001 narrowed, in a transaction
-- of its own so the scans run under SHARE UPDATE EXCLUSIVE rather than inside
-- the previous file's ACCESS EXCLUSIVE (migration_locks.md). Every row already
-- satisfies them: that file deleted the only rows that did not.

alter table public.integrations validate constraint integrations_provider_check;

alter table public.race_listings validate constraint race_listings_provider_check;
