// parseEntityLink reads the run or route out of a link the OS opens the app
// with, and EntityLinkService hands each one to HomeScreen once.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/entity_link.dart';

void main() {
  const id = '0b6f2f4e-8c1d-4a7e-9f3b-2d5c6a7b8c9d';

  group('parseEntityLink', () {
    EntityLink? parse(String s) => parseEntityLink(Uri.parse(s));

    test('the web run and route links', () {
      expect(parse('https://threkir.com/runs/$id'),
          const EntityLink(EntityLinkKind.run, id));
      expect(parse('https://threkir.com/routes/$id'),
          const EntityLink(EntityLinkKind.route, id));
    });

    test('a preview host, trailing slash, query or fragment', () {
      expect(parse('https://preview.threkir.com/runs/$id'),
          const EntityLink(EntityLinkKind.run, id));
      expect(parse('https://threkir.com/routes/$id/'),
          const EntityLink(EntityLinkKind.route, id));
      expect(parse('https://threkir.com/runs/$id?utm_source=whatsapp#top'),
          const EntityLink(EntityLinkKind.run, id));
    });

    test('the app scheme links', () {
      expect(parse('com.threkir.app://runs/$id'),
          const EntityLink(EntityLinkKind.run, id));
      expect(parse('com.threkir.app://routes/$id'),
          const EntityLink(EntityLinkKind.route, id));
    });

    test('an upper-case id is normalised', () {
      expect(parse('https://threkir.com/runs/${id.toUpperCase()}'),
          const EntityLink(EntityLinkKind.run, id));
    });

    test('other web pages under /runs and /routes are not links', () {
      expect(parse('https://threkir.com/runs/new'), isNull);
      expect(parse('https://threkir.com/runs/heatmap'), isNull);
      expect(parse('https://threkir.com/routes/heatmap'), isNull);
      expect(parse('https://threkir.com/routes/$id/roadbook'), isNull);
      expect(parse('https://threkir.com/runs'), isNull);
    });

    test('the public share pages and other hosts are not links', () {
      expect(parse('https://threkir.com/share/run/$id'), isNull);
      expect(parse('https://example.com/runs/$id'), isNull);
      expect(parse('https://threkir.com.evil.example/runs/$id'), isNull);
      expect(parse('http://threkir.com/runs/$id'), isNull);
      expect(parse('com.threkir.app://login-callback?code=abc'), isNull);
      expect(parse('com.threkir.app://clubs/join/abc123'), isNull);
    });
  });

  group('EntityLinkService', () {
    tearDown(() => pendingEntityLink.value = null);

    test('a run link sets the pending link', () {
      EntityLinkService(
        links: const Stream<Uri>.empty(),
        initialLink: () async => null,
      ).handle(Uri.parse('https://threkir.com/runs/$id'));
      expect(pendingEntityLink.value, const EntityLink(EntityLinkKind.run, id));
    });

    test('a club invite link leaves the pending link alone', () {
      EntityLinkService(
        links: const Stream<Uri>.empty(),
        initialLink: () async => null,
      ).handle(Uri.parse('https://threkir.com/clubs/join/abc123'));
      expect(pendingEntityLink.value, isNull);
    });

    test('the cold-start link delivered twice is handed off once', () async {
      final links = StreamController<Uri>();
      final uri = Uri.parse('com.threkir.app://routes/$id');
      final service = EntityLinkService(
        links: links.stream,
        initialLink: () async => uri,
      )..start();
      await service.processInitial();
      expect(
          pendingEntityLink.value, const EntityLink(EntityLinkKind.route, id));

      pendingEntityLink.value = null;
      links.add(uri);
      await Future<void>.delayed(Duration.zero);
      expect(pendingEntityLink.value, isNull);

      await service.dispose();
      await links.close();
    });

    test('a failing initial-link read does not throw', () async {
      final service = EntityLinkService(
        links: const Stream<Uri>.empty(),
        initialLink: () async => throw StateError('no channel'),
      );
      await service.processInitial();
      expect(pendingEntityLink.value, isNull);
    });

    test('the Android manifest registers the link shapes the parser reads',
        () {
      // Only mobile_android carries android/; the twin copy skips.
      final manifest = File('android/app/src/main/AndroidManifest.xml');
      if (!manifest.existsSync()) return;
      final body = manifest.readAsStringSync();
      const uuid = '........-....-....-....-............';
      expect(body,
          contains('android:scheme="com.threkir.app" android:host="runs"'));
      expect(body,
          contains('android:scheme="com.threkir.app" android:host="routes"'));
      expect(
        body,
        contains('android:scheme="https" android:host="threkir.com" '
            'android:pathPattern="/runs/$uuid"'),
      );
      expect(
        body,
        contains('android:scheme="https" android:host="threkir.com" '
            'android:pathPattern="/routes/$uuid"'),
      );
    });
  });
}
