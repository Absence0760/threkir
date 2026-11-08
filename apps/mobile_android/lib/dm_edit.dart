/// Editing a sent direct message (issue #1216, migration 20271114000210). The
/// server decides: `edit_direct_message` refuses a message that is not the
/// caller's, is unsent, is past the window or sits between a blocked pair.
/// This only decides whether to offer Edit. Web twin:
/// `apps/web/src/lib/social/dm_edit.ts`.
library;

import 'package:core_models/core_models.dart';

/// Must equal `c_window` in edit_direct_message; dm_edit_test.dart reads the
/// migration.
const Duration kDmEditWindow = Duration(minutes: 15);

/// Whether the viewer may still edit [m] at [now]: their own live message,
/// sent no more than the window ago. A `createdAt` ahead of the local clock
/// (skew) counts as just sent; the server's clock is the one that decides.
bool canEditDm(DirectMessageRow m, String? viewerId, DateTime now) {
  if (viewerId == null || m.senderId != viewerId) return false;
  if (m.unsentAt != null || m.body == null) return false;
  return now.difference(m.createdAt) <= kDmEditWindow;
}
