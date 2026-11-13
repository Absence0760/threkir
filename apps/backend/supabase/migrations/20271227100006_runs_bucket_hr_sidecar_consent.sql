-- The heart-rate sidecar in the runs bucket follows health-data consent
-- (decisions § 2514).
--
-- {user_id}/{run_id}.hr.json.gz is a run's heart-rate series when the track
-- has no per-point bpm (decisions § 116). The owner-folder policies
-- (20260410_001 / 20260816_001) let its owner write and read it at any time.
-- These RESTRICTIVE policies add one term to each: a .hr.json.gz object in
-- the runs bucket can be uploaded, overwritten or downloaded only while the
-- caller has health-data consent. A sidecar stored before the gate stays in
-- the bucket, unreadable, until consent is given or a withdrawal erases it:
-- the erasure runs in the job worker as the service role
-- (health_hr_erase, 20271227100008), which these policies do not reach.
--
-- Every other bucket and every other object in this one short-circuits on
-- the first term.
--
-- Lock: policies on storage.objects, a catalogue change.

create policy "runs hr sidecar read needs health consent"
  on storage.objects
  as restrictive
  for select
  to authenticated
  using (
    bucket_id <> 'runs'
    or name not like '%.hr.json.gz'
    or private.health_data_consented((select auth.uid()))
  );

create policy "runs hr sidecar upload needs health consent"
  on storage.objects
  as restrictive
  for insert
  to authenticated
  with check (
    bucket_id <> 'runs'
    or name not like '%.hr.json.gz'
    or private.health_data_consented((select auth.uid()))
  );

create policy "runs hr sidecar overwrite needs health consent"
  on storage.objects
  as restrictive
  for update
  to authenticated
  using (
    bucket_id <> 'runs'
    or name not like '%.hr.json.gz'
    or private.health_data_consented((select auth.uid()))
  )
  with check (
    bucket_id <> 'runs'
    or name not like '%.hr.json.gz'
    or private.health_data_consented((select auth.uid()))
  );
