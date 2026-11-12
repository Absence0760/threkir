import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Apple sign-in configuration gate.
///
/// iOS uses the native flow and needs no configuration. On Android,
/// `sign_in_with_apple` 8.x hard-requires `webAuthenticationOptions`
/// (an Apple Services ID + an allow-listed return URL) — calling
/// `getAppleIDCredential` without them throws before any UI opens, so
/// the button could never succeed. Both values are env-provisioned
/// (`APPLE_SERVICE_CLIENT_ID` + `APPLE_REDIRECT_URI`, see
/// `local_testing.md`); until the operator provisions the Apple
/// Developer Services ID the button fails closed with the same
/// coming-soon treatment as the Google `GOOGLE_WEB_CLIENT_ID` gate.
///
/// Platform dispatch uses `defaultTargetPlatform` rather than
/// `Platform.isIOS` so widget tests (host-run, which report
/// `TargetPlatform.android`) exercise the Android gate.

String? _env(String key) {
  final value = dotenv.isInitialized ? dotenv.maybeGet(key) : null;
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// True where Apple's native flow runs, which issues credentials to the
/// app's bundle id; elsewhere they go to the Services ID.
bool appleUsesNativeFlow() => defaultTargetPlatform == TargetPlatform.iOS;

bool appleSignInAvailable() {
  if (appleUsesNativeFlow()) return true;
  return _env('APPLE_SERVICE_CLIENT_ID') != null &&
      _env('APPLE_REDIRECT_URI') != null;
}

/// Options for the Android web-fallback flow; null on iOS (native
/// flow) or while unconfigured (callers gate on [appleSignInAvailable]
/// first).
WebAuthenticationOptions? appleWebAuthOptions() {
  if (appleUsesNativeFlow()) return null;
  final clientId = _env('APPLE_SERVICE_CLIENT_ID');
  final redirectUri = _env('APPLE_REDIRECT_URI');
  if (clientId == null || redirectUri == null) return null;
  return WebAuthenticationOptions(
    clientId: clientId,
    redirectUri: Uri.parse(redirectUri),
  );
}
