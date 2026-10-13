// parseClubInviteToken reads the invite token out of whatever a runner
// pastes into the Join-with-code field or the OS opens the app with, and
// ClubInviteLinkService hands each link's token to HomeScreen once.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/club_invite_link.dart';

void main() {
  group('parseClubInviteToken', () {
    const token = 'c3fr13nd50fj4r3dc1ubtoken000000';

    test('a bare code passes through trimmed', () {
      expect(parseClubInviteToken('  $token  '), token);
    });

    test('the full web link yields its token', () {
      expect(
        parseClubInviteToken('https://threkir.com/clubs/join/$token'),
        token,
      );
    });

    test('a link without a scheme yields its token', () {
      expect(parseClubInviteToken('threkir.com/clubs/join/$token'), token);
      expect(parseClubInviteToken('www.threkir.com/clubs/join/$token'), token);
    });

    test('a trailing slash, query or fragment is dropped', () {
      expect(
        parseClubInviteToken('https://threkir.com/clubs/join/$token/'),
        token,
      );
      expect(
        parseClubInviteToken(
            'https://threkir.com/clubs/join/$token?utm_source=whatsapp'),
        token,
      );
      expect(
        parseClubInviteToken('https://threkir.com/clubs/join/$token#top'),
        token,
      );
    });

    test('a link pasted inside a message yields its token', () {
      expect(
        parseClubInviteToken(
            'Join us! https://threkir.com/clubs/join/$token see you Saturday'),
        token,
      );
    });

    test('the app scheme link yields its token', () {
      expect(
        parseClubInviteToken('com.threkir.app://clubs/join/$token'),
        token,
      );
    });

    test('a preview host link yields its token', () {
      expect(
        parseClubInviteToken('https://preview.threkir.com/clubs/join/$token'),
        token,
      );
    });

    test('blank input is null', () {
      expect(parseClubInviteToken(''), isNull);
      expect(parseClubInviteToken('   '), isNull);
    });

    test('an invite path with no token is null', () {
      expect(parseClubInviteToken('https://threkir.com/clubs/join/'), isNull);
      expect(parseClubInviteToken('https://threkir.com/clubs/join/?x=1'),
          isNull);
    });

    test('a link that is not an invite is null, not a token', () {
      expect(parseClubInviteToken('https://threkir.com/clubs/track-club'),
          isNull);
      expect(parseClubInviteToken('threkir.com/clubs/join'), isNull);
      expect(
        parseClubInviteToken('com.threkir.app://login-callback?code=abc'),
        isNull,
      );
    });
  });

  group('ClubInviteLinkService', () {
    tearDown(() => pendingClubInviteToken.value = null);

    test('an invite link sets the pending token', () {
      ClubInviteLinkService(
        links: const Stream<Uri>.empty(),
        initialLink: () async => null,
      ).handle(Uri.parse('https://threkir.com/clubs/join/abc123'));
      expect(pendingClubInviteToken.value, 'abc123');
    });

    test('a non-invite link leaves the pending token alone', () {
      ClubInviteLinkService(
        links: const Stream<Uri>.empty(),
        initialLink: () async => null,
      ).handle(Uri.parse('com.threkir.app://login-callback?code=xyz'));
      expect(pendingClubInviteToken.value, isNull);
    });

    test('the cold-start link delivered twice is handed off once', () async {
      final links = StreamController<Uri>();
      final uri = Uri.parse('com.threkir.app://clubs/join/abc123');
      final service = ClubInviteLinkService(
        links: links.stream,
        initialLink: () async => uri,
      )..start();
      await service.processInitial();
      expect(pendingClubInviteToken.value, 'abc123');

      pendingClubInviteToken.value = null;
      links.add(uri);
      await Future<void>.delayed(Duration.zero);
      expect(pendingClubInviteToken.value, isNull);

      links.add(Uri.parse('https://threkir.com/clubs/join/def456'));
      await Future<void>.delayed(Duration.zero);
      expect(pendingClubInviteToken.value, 'def456');

      await service.dispose();
      await links.close();
    });

    test('the platform registers the link shapes the parser reads', () {
      // Each twin carries one native project: Android pins the intent
      // filters, iOS the URL scheme. Flutter's own deep-link routing is off
      // on both, or it would push the invite path as an undefined route.
      final manifest = File('android/app/src/main/AndroidManifest.xml');
      if (manifest.existsSync()) {
        final body = manifest.readAsStringSync();
        expect(
          body,
          contains('android:scheme="com.threkir.app" android:host="clubs" '
              'android:pathPrefix="/join/"'),
        );
        expect(
          body,
          contains('android:scheme="https" android:host="threkir.com" '
              'android:pathPrefix="/clubs/join/"'),
        );
        expect(
          body,
          matches(RegExp(
              r'flutter_deeplinking_enabled"\s+android:value="false"')),
        );
      }
      final plist = File('ios/Runner/Info.plist');
      if (plist.existsSync()) {
        final body = plist.readAsStringSync();
        expect(body, contains('<string>com.threkir.app</string>'));
        expect(
          body,
          matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>')),
        );
      }
    });

    test('a failing initial-link read does not throw', () async {
      final service = ClubInviteLinkService(
        links: const Stream<Uri>.empty(),
        initialLink: () async => throw StateError('no channel'),
      );
      await service.processInitial();
      expect(pendingClubInviteToken.value, isNull);
    });
  });
}
