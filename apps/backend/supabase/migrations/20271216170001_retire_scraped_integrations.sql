-- Retire the integrations that scraped a third party's website (decisions
-- § 2465): the parkrun results import, the parkrun upcoming-events feed
-- and the UltraSignup results import. Their code is gone; this removes what
-- they stored and narrows the two provider vocabularies so nothing can write
-- those values again.
--
--   1. `integrations` rows with provider `parkrun` or `ultrasignup` are
--      deleted. A `parkrun` row was a placeholder the old Settings card wrote
--      (no token, no identifier). An `ultrasignup` row held the runner's
--      UltraSignup person id and the name it was found under
--      (`external_first_name` / `external_last_name`), which existed only to
--      query the scraped feed. With the import gone neither has a use, so
--      keeping them is retention without purpose (GDPR Art 5(1)(c), (e)).
--      Runs already imported are the runner's own and are untouched.
--   2. `race_listings` rows with provider `parkrun` are deleted: only the
--      parkrun events leg wrote them, and it stayed off pending parkrun's
--      permission. `runs.race_listing_id` and `training_plans.race_listing_id`
--      are ON DELETE SET NULL. `course_alerts`, `race_course_suggestions` and
--      `race_listing_audit` rows on such a listing cascade: an alert or
--      suggestion about a listing that no longer exists has nothing left to
--      point at. The leg never ran in production, so none are expected.
--   3. `integrations_ultrasignup_identity_chk` is dropped: it constrained a
--      provider value the narrowed vocabulary no longer admits. The
--      `external_first_name` / `external_last_name` columns stay until the
--      job worker and web releases that stop selecting them are live; they are
--      NULL on every row after (1). Dropping them is a later migration
--      (followups.md).
--   4. `integrations_provider_check` loses `parkrun` and `ultrasignup`;
--      `race_listings_provider_check` loses `parkrun`. Each is added NOT VALID
--      here and validated in 20271216170002, in its own transaction
--      (migration_locks.md).
--
-- `user_profiles.parkrun_number` stays: the parkrun barcode reads it, and it
-- holds only the runner's own number.
--
-- Lock profile: `integrations` (one row per user per provider) and
-- `race_listings` are small tables, not on the high-volume list. The deletes
-- take ROW EXCLUSIVE; the constraint swaps take ACCESS EXCLUSIVE for a
-- metadata change only.

delete from public.integrations where provider in ('parkrun', 'ultrasignup');

delete from public.race_listings where provider = 'parkrun';

alter table public.integrations
  drop constraint integrations_ultrasignup_identity_chk;

alter table public.integrations
  drop constraint integrations_provider_check,
  add constraint integrations_provider_check
    check (provider in ('strava', 'garmin', 'runsignup')) not valid;

alter table public.race_listings
  drop constraint race_listings_provider_check,
  add constraint race_listings_provider_check
    check (provider in ('runsignup', 'manual', 'chronotrack', 'raceresult', 'ultrasignup')) not valid;
