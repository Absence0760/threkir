import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Google sign-in configuration gate.
///
/// Android resolves the native half of the flow from the installed package
/// name plus signing certificate, so `GOOGLE_WEB_CLIENT_ID` — the audience
/// Supabase validates the ID token against — is the whole configuration.
/// iOS has no such registry: `google_sign_in_ios` builds its
/// `GIDConfiguration` from an `initialize(clientId:)` argument or from a
/// bundled `GoogleService-Info.plist`, and with neither it leaves
/// `GIDSignIn.configuration` nil. `authenticate()` then raises an NSException
/// the plugin rethrows as an opaque `PlatformException`, so the button could
/// never succeed and failed with a raw error rather than the coming-soon
/// notice the same unconfigured state gets on Android.
///
/// Platform dispatch uses `defaultTargetPlatform` rather than
/// `Platform.isIOS` so widget tests (host-run, which report
/// `TargetPlatform.android`) exercise the Android gate, matching
/// `apple_auth.dart`.

String? _env(String key) {
  final value = dotenv.isInitialized ? dotenv.maybeGet(key) : null;
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// The web client id the ID token is minted for, or null while unconfigured.
String? googleWebClientId() => _env('GOOGLE_WEB_CLIENT_ID');

/// Whether the Google button can reach a working flow on this build.
bool googleSignInAvailable() {
  if (googleWebClientId() == null) return false;
  if (defaultTargetPlatform != TargetPlatform.iOS) return true;
  return _googleServiceInfoBundled;
}

/// Whether the iOS bundle carries a `GoogleService-Info.plist`, the only place
/// `google_sign_in_ios` can find an iOS OAuth client id given this app passes
/// none. Read through `Firebase.apps`, which is non-empty exactly when
/// `initFirebaseForPush` found and parsed that same file.
bool get _googleServiceInfoBundled {
  try {
    return Firebase.apps.isNotEmpty;
  } catch (_) {
    return false;
  }
}
