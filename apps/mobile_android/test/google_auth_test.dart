import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/google_auth.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('googleSignInAvailable (Android)', () {
    test('fails closed when the web client id is unset', () {
      dotenv.loadFromString(envString: '', isOptional: true);
      expect(googleWebClientId(), isNull);
      expect(googleSignInAvailable(), isFalse);
    });

    test('fails closed when the web client id is whitespace-only', () {
      dotenv.loadFromString(
          envString: 'GOOGLE_WEB_CLIENT_ID=   ', isOptional: true);
      expect(googleWebClientId(), isNull);
      expect(googleSignInAvailable(), isFalse);
    });

    test('available once the web client id is provisioned', () {
      dotenv.loadFromString(
          envString: 'GOOGLE_WEB_CLIENT_ID=web.apps.googleusercontent.com',
          isOptional: true);
      expect(googleWebClientId(), 'web.apps.googleusercontent.com');
      expect(googleSignInAvailable(), isTrue);
    });
  });

  group('iOS', () {
    test('fails closed with no GoogleService-Info.plist, however the web '
        'client id is set', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      dotenv.loadFromString(
          envString: 'GOOGLE_WEB_CLIENT_ID=web.apps.googleusercontent.com',
          isOptional: true);
      expect(googleWebClientId(), 'web.apps.googleusercontent.com');
      expect(googleSignInAvailable(), isFalse);
    });

    test('no Firebase platform on the host reads as no iOS client id', () {
      expect(iosOauthClientId(), isNull);
    });
  });

  // The decision over values. `googleSignInAvailable` can only ever be
  // observed false on a host runner — no bundle, so no GoogleService-Info.plist
  // and no iOS client id — which left the branch that turns the button ON
  // untested. These drive it directly.
  group('googleSignInAvailableFor', () {
    test('Android ignores the iOS client id entirely', () {
      expect(
          googleSignInAvailableFor(
              webClientId: 'web.apps.googleusercontent.com',
              isIos: false,
              iosClientId: null),
          isTrue);
    });

    test('no web client id fails closed on either platform', () {
      for (final isIos in [true, false]) {
        expect(
            googleSignInAvailableFor(
                webClientId: null,
                isIos: isIos,
                iosClientId: 'ios.apps.googleusercontent.com'),
            isFalse,
            reason: 'isIos=$isIos');
      }
    });

    test('iOS needs the iOS client id as well as the web one', () {
      expect(
          googleSignInAvailableFor(
              webClientId: 'web.apps.googleusercontent.com',
              isIos: true,
              iosClientId: null),
          isFalse);
    });

    test('iOS is available once both client ids are present', () {
      expect(
          googleSignInAvailableFor(
              webClientId: 'web.apps.googleusercontent.com',
              isIos: true,
              iosClientId: 'ios.apps.googleusercontent.com'),
          isTrue);
    });
  });

  // decisions § 1700: rendering is a separate question from the tap gate.
  group('googleSignInOffered', () {
    test('Android shows the button unconfigured; the tap says coming soon', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      dotenv.loadFromString(envString: '', isOptional: true);
      expect(googleSignInOffered(), isTrue);
    });

    test('iOS renders no button while the flow cannot work', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      dotenv.loadFromString(
          envString: 'GOOGLE_WEB_CLIENT_ID=web.apps.googleusercontent.com',
          isOptional: true);
      expect(googleSignInAvailable(), isFalse);
      expect(googleSignInOffered(), isFalse);
    });
  });
}
