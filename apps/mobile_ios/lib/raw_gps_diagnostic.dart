import 'package:flutter/foundation.dart';

import 'dev_auto_login.dart' show isLocalSupabaseUrl;

/// Whether the developer "raw GPS provider" switch exists on this build
/// (#1090 item 6: record the same course on the fused provider and on raw
/// `GPS_PROVIDER` to compare them). Android only, since iOS has one provider.
/// A release build shows it only against a loopback backend, the same rail as
/// the rest of the developer section; a debug or profile build shows it
/// against any backend, so the owner can record a corpus run into a real
/// account and export it. The run screen reads the stored switch through this
/// same gate, so a value left set can never reach a release build's runs.
bool rawGpsDiagnosticAvailable({
  required String? backendUrl,
  bool releaseBuild = kReleaseMode,
  TargetPlatform? platform,
}) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.android &&
    (!releaseBuild || isLocalSupabaseUrl(backendUrl));
