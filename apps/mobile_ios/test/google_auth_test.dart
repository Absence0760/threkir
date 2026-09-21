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
