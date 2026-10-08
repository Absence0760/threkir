-- Seven SECURITY DEFINER reads carried the default VOLATILE although none of
-- them writes, so the web's RPC transport guard (decisions § 1735) kept them
-- on POST, where the local stack's Kong keep-alive race answers 502 and
-- nothing replays the request (§ 1703). Declaring each STABLE lets them go out
-- as GETs, which PostgREST runs in a READ ONLY transaction.
--
-- Each body was re-read at its live definition, including every function it
-- calls; none inserts, updates, deletes, performs or sets anything:
--   am_i_admin                  20270105_001  -> private.is_admin (select exists)
--   clip_route_for_viewer       20270329_001  -> private.is_club_member (select
--                                                exists), clip_track_for_user
--                                                (reads privacy_zones, builds jsonb)
--   fetch_checkpoint_crossings_for_organiser
--                               20270201_001  -> private.is_event_organiser
--   fetch_pending_reports       20270218_001  -> private.is_admin
--   fetch_reports_for_target    20270105_001  -> private.is_admin
--   get_event_meet_point        20261027_001  -> private.is_club_member
--   my_pending_safety_requests  20270410_001  (plain select over auth.users)
-- auth.uid() is itself STABLE. A function that later gains a write must be
-- re-declared VOLATILE in the same migration, and its web call site moved back
-- to POST; the guard fails until both agree.
--
-- Locks: ALTER FUNCTION is a catalogue-only change to pg_proc; no table lock,
-- no scan, no rewrite.

alter function public.am_i_admin() stable;
alter function public.clip_route_for_viewer(uuid) stable;
alter function public.fetch_checkpoint_crossings_for_organiser(uuid, timestamptz) stable;
alter function public.fetch_pending_reports() stable;
alter function public.fetch_reports_for_target(text, uuid) stable;
alter function public.get_event_meet_point(uuid) stable;
alter function public.my_pending_safety_requests() stable;
