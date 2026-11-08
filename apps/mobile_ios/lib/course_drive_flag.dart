import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'env_flag.dart';

/// The dart-define / dotenv key the gate reads. Web spells the same flag
/// `PUBLIC_COURSE_DRIVE_ENABLED` (`apps/web/src/lib/routes/course_drive_flag.ts`);
/// mobile drops the web-only `PUBLIC_` prefix.
const String kCourseDriveEnvKey = 'COURSE_DRIVE_ENABLED';

/// Pure parse of the Drive this course deploy flag, delegating to the one
/// canonical [isTruthyFlagValue] (decisions § 709).
bool courseDriveEnabled(String? raw) => isTruthyFlagValue(raw);

/// Whether the route and race screens offer Drive this course
/// (docs/features/course_drive.md, decisions § 2380). Off until counsel signs
/// off on the safety notice (§ 150). The read is guarded because `dotenv.env`
/// throws until something has loaded it; an unreadable dotenv reads off.
bool get courseDriveGate {
  try {
    return courseDriveEnabled(dotenv.env[kCourseDriveEnvKey]);
  } catch (_) {
    return false;
  }
}
