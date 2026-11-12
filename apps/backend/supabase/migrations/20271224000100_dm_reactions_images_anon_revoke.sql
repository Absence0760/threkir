-- anon held SELECT on direct_message_reactions (table-wide, 20271213121602)
-- and on nine columns of direct_message_images (20271213121604), though every
-- policy on both is `to authenticated` and no signed-out surface reads either.
-- Nothing leaks today, because RLS admits no anon row; a later policy written
-- without a `to` clause would. The grant is withdrawn so the role, not only
-- the policy set, keeps a signed-out caller out (audit of PR #1359, Low).
--
-- A table-level REVOKE also clears the column-level grants, so one statement
-- per table empties anon's ACL on it. authenticated keeps exactly what it had.
--
-- Locks: REVOKE takes no table lock beyond the catalog row update.

revoke select on direct_message_reactions from anon;
revoke select on direct_message_images from anon;
