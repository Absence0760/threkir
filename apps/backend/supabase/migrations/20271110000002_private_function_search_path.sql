-- Pin search_path on the two private-schema constants the prod security
-- advisor flags as "Function Search Path Mutable" (decisions § 2351).
--
-- private.event_waitlist_claim_window() (20270726000002) and
-- private.share_link_daily_cap() (20271104000004) are `language sql
-- immutable` one-liners returning a literal, so neither references an object
-- a hostile search_path could shadow. They slipped through because
-- function_search_path_test.sql read only the public schema; it now reads
-- private too, and these were the only two unpinned functions there.
--
-- An empty search_path is the strictest pin and is exact for a body that
-- names nothing. ALTER, not create or replace, for the reason § 244 gives:
-- a later bare re-emission resets proconfig, while an ALTER leaves the body
-- alone and cannot strip anything else.

alter function private.event_waitlist_claim_window() set search_path = '';
alter function private.share_link_daily_cap() set search_path = '';
