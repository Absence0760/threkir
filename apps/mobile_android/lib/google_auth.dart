import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
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

/// The iOS OAuth client id this bundle carries, or null when it carries none.
///
/// Read off the `GoogleService-Info.plist` that `initFirebaseForPush` parsed,
/// which is the only place `google_sign_in_ios` looks given this app passes no
/// `clientId` to `initialize()` — `FirebaseOptions.iosClientId` is that file's
/// `CLIENT_ID` key, the one the plugin reads.
///
/// Probing the id rather than `Firebase.apps.isNotEmpty` is the point: a
/// Firebase iOS app with Google Sign-In switched off in the console ships a
/// plist with no `CLIENT_ID`, so Firebase initialises for push and the plugin
/// still has nothing to build a `GIDConfiguration` from. The same absence
/// leaves out `REVERSED_CLIENT_ID`, so the Runner build phase registers no
/// redirect scheme either — this gate and the redirect turn on together.
String? iosOauthClientId() {
  try {
    final apps = Firebase.apps;
    if (apps.isEmpty) return null;
    final id = apps.first.options.iosClientId?.trim();
    return (id == null || id.isEmpty) ? null : id;
  } catch (_) {
    return null;
  }
}

/// The gate's decision, over values rather than over the platform and Firebase
/// reads that supply them. Factored out because the case that matters most —
/// an iOS build that IS configured — needs a bundled `GoogleService-Info.plist`
/// that no host test can produce, so [googleSignInAvailable] could only ever be
/// tested on its false branch.
@visibleForTesting
bool googleSignInAvailableFor({
  required String? webClientId,
  required bool isIos,
  required String? iosClientId,
}) {
  if (webClientId == null) return false;
  if (!isIos) return true;
  return iosClientId != null;
}

/// Whether the Google button can reach a working flow on this build.
bool googleSignInAvailable() => googleSignInAvailableFor(
      webClientId: googleWebClientId(),
      isIos: defaultTargetPlatform == TargetPlatform.iOS,
      iosClientId: iosOauthClientId(),
    );

/// Whether the Google button is shown at all.
///
/// Android always shows it: an unconfigured build answers a tap with the
/// coming-soon notice. iOS shows it only when [googleSignInAvailable], because
/// a sign-in button that cannot work is an App Review rejection (Guideline
/// 2.1), so there it is absent rather than "coming soon" (decisions § 1700).
/// Sign in with Apple and email cover sign-in on iOS either way.
bool googleSignInOffered() =>
    defaultTargetPlatform != TargetPlatform.iOS || googleSignInAvailable();
