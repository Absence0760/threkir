import 'package:flutter_test/flutter_test.dart';

import '../lib/runner_handle.dart';

String _en(String? id) =>
    runnerHandle(id, handle: (slug) => 'Runner #$slug', anonymous: 'Runner');

void main() {
  // Persona-hunt Round 3 finding Privacy #5. Dart twin of
  // `apps/web/src/lib/social/runner_handle.test.ts` — keep in lockstep.
  group('runnerHandle', () {
    test(
      'returns Runner #ABCD for a v4 uuid (first 4 hex chars, uppercased)',
      () {
        expect(_en('a1b2c3d4-e5f6-7890-abcd-ef1234567890'), 'Runner #A1B2');
        expect(_en('00000000-0000-0000-0000-000000000bad'), 'Runner #0000');
      },
    );

    test('drops hyphens from the uuid before taking the slice', () {
      expect(_en('aaa-b2c3-...'), 'Runner #AAAB');
    });

    test('returns plain "Runner" for null / empty / too-short input', () {
      expect(_en(null), 'Runner');
      expect(_en(''), 'Runner');
      expect(_en('a-1'), 'Runner');
    });

    test('deterministic — same uuid produces same handle on every call', () {
      const id = 'b2c3d4e5-f6a7-8901-bcde-f23456789012';
      expect(_en(id), _en(id));
    });

    test("wraps the slug in the caller's localised labels", () {
      String pt(String? id) => runnerHandle(
        id,
        handle: (slug) => 'Corredor #$slug',
        anonymous: 'Corredor',
      );
      expect(pt('a1b2c3d4-e5f6-7890-abcd-ef1234567890'), 'Corredor #A1B2');
      expect(pt(null), 'Corredor');
    });
  });

  group('shouldRevealDisplayName', () {
    test('anon viewer → false', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: null,
          runnerUserId: 'r-1',
          viewerFollowsRunner: false,
          runnerFollowsViewer: false,
        ),
        false,
      );
    });

    test('missing runnerUserId → false (defensive)', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'v-1',
          runnerUserId: null,
          viewerFollowsRunner: false,
          runnerFollowsViewer: false,
        ),
        false,
      );
    });

    test('self-view → true', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'same-id',
          runnerUserId: 'same-id',
          viewerFollowsRunner: false,
          runnerFollowsViewer: false,
        ),
        true,
      );
    });

    test('viewer follows runner → true', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'v',
          runnerUserId: 'r',
          viewerFollowsRunner: true,
          runnerFollowsViewer: false,
        ),
        true,
      );
    });

    test('runner follows viewer → true', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'v',
          runnerUserId: 'r',
          viewerFollowsRunner: false,
          runnerFollowsViewer: true,
        ),
        true,
      );
    });

    test('signed-in stranger with no follow edge → false', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'stranger',
          runnerUserId: 'runner',
          viewerFollowsRunner: false,
          runnerFollowsViewer: false,
        ),
        false,
      );
    });
  });
}
