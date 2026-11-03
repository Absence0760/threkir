// parseChallengeLink reads a creator's challenge invite (or a public
// challenge's share page) out of a link the OS opens the app with, and
// ChallengeLinkService hands each link to HomeScreen once (decisions § 2261).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/challenge_invite_link.dart';

void main() {
  const token = 'Ab3_dEf-Gh1jKl2mNo3pQr4s';
  const id = '5f1c7e2a-0000-4000-8000-000000000001';

  group('parseChallengeLink', () {
    test('the web invite link yields its token', () {
      expect(parseChallengeLink(Uri.parse('https://threkir.com/challenges/join/$token')),
          const ChallengeInviteLink(token));
    });

    test('a preview host, a trailing slash and a query still parse', () {
      expect(
          parseChallengeLink(
              Uri.parse('https://preview.threkir.com/challenges/join/$token/?utm=ig')),
          const ChallengeInviteLink(token));
    });

    test('the app scheme invite link yields its token', () {
      expect(parseChallengeLink(Uri.parse('com.threkir.app://challenges/join/$token')),
          const ChallengeInviteLink(token));
    });

    test('the public share page yields the challenge id, lower-cased', () {
      expect(
          parseChallengeLink(
              Uri.parse('https://threkir.com/share/challenge/${id.toUpperCase()}')),
          const ChallengeShareLink(id));
    });

    test("the share page keeps a well-formed creator's ref and drops anything else", () {
      expect(
          parseChallengeLink(
              Uri.parse('https://threkir.com/share/challenge/$id?ref=a1b2c3d4e5')),
          const ChallengeShareLink(id, shareRef: 'a1b2c3d4e5'));
      expect(
          parseChallengeLink(
              Uri.parse('https://threkir.com/share/challenge/$id?ref=<script>')),
          const ChallengeShareLink(id));
    });

    test('anything else is not a challenge link', () {
      for (final s in [
        'https://evil.example/challenges/join/$token',
        'https://threkir.com/challenges/$id',
        'https://threkir.com/challenges/join/',
        'https://threkir.com/challenges/join/bad token!',
        'https://threkir.com/share/challenge/not-a-uuid',
        'https://threkir.com/clubs/join/$token',
        'http://threkir.com/challenges/join/$token',
      ]) {
        expect(parseChallengeLink(Uri.parse(s)), isNull, reason: s);
      }
    });

    test('the paths it builds are the paths it parses', () {
      expect(
          parseChallengeLink(Uri.parse('https://threkir.com${challengeInvitePath(token)}')),
          const ChallengeInviteLink(token));
      expect(parseChallengeLink(Uri.parse('https://threkir.com${challengeSharePath(id)}')),
          const ChallengeShareLink(id));
    });
  });

  group('ChallengeLinkService', () {
    tearDown(() => pendingChallengeLink.value = null);

    test('hands a cold-start link to HomeScreen once, not twice', () async {
      final links = StreamController<Uri>();
      final uri = Uri.parse('https://threkir.com/challenges/join/$token');
      final service = ChallengeLinkService(
        links: links.stream,
        initialLink: () async => uri,
      )..start();
      await service.processInitial();
      expect(pendingChallengeLink.value, const ChallengeInviteLink(token));
      pendingChallengeLink.value = null;
      links.add(uri);
      await Future<void>.delayed(Duration.zero);
      expect(pendingChallengeLink.value, isNull);
      await service.dispose();
      await links.close();
    });

    test('the same link opened again after it was consumed opens again',
        () async {
      final links = StreamController<Uri>();
      final uri = Uri.parse('https://threkir.com/challenges/join/$token');
      final service = ChallengeLinkService(
        links: links.stream,
        initialLink: () async => uri,
      )..start();
      await service.processInitial();
      pendingChallengeLink.value = null;
      links.add(uri);
      await Future<void>.delayed(Duration.zero);
      expect(pendingChallengeLink.value, isNull);
      for (var i = 0; i < 2; i++) {
        links.add(uri);
        await Future<void>.delayed(Duration.zero);
        expect(pendingChallengeLink.value, const ChallengeInviteLink(token));
        pendingChallengeLink.value = null;
      }
      await service.dispose();
      await links.close();
    });

    test('ignores a link that is not a challenge', () async {
      final service = ChallengeLinkService(
        links: const Stream.empty(),
        initialLink: () async => Uri.parse('https://threkir.com/runs/$id'),
      );
      await service.processInitial();
      expect(pendingChallengeLink.value, isNull);
    });
  });
}
