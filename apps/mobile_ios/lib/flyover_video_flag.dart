import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'env_flag.dart';

/// The dart-define / dotenv key the gate reads. Web spells the same flag
/// `PUBLIC_FLYOVER_VIDEO_MAPTILER_ENABLED` (`apps/web/src/lib/routes/flyover_video_flag.ts`);
/// mobile drops the web-only `PUBLIC_` prefix.
const String kFlyoverVideoEnvKey = 'FLYOVER_VIDEO_MAPTILER_ENABLED';

/// Pure parse of the flyover video deploy flag, delegating to the one
/// canonical [isTruthyFlagValue] (decisions § 709).
bool flyoverVideoEnabled(String? raw) => isTruthyFlagValue(raw);

/// Whether the run share sheet offers its Video style (decisions § 2271).
///
/// The style opens the web flyover export, which threkir.com offers only with
/// a basemap a published video may record (§ 2270): in production that is
/// MapTiler under the same flag. Off, the style would open a page with no
/// export, so it is not offered. The read is guarded because `dotenv.env`
/// throws until something has loaded it; an unreadable dotenv reads off.
bool get flyoverVideoGate {
  try {
    return flyoverVideoEnabled(dotenv.env[kFlyoverVideoEnvKey]);
  } catch (_) {
    return false;
  }
}
