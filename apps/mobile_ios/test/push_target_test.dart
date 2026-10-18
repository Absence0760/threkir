import 'package:flutter_test/flutter_test.dart';

import '../lib/push_target.dart';

const _base = 'https://threkir.com';

void main() {
  group('pushTargetFromUrl — every target pathForKind can stamp', () {
    test('event family → /events/{id}', () {
      expect(pushTargetFromUrl('$_base/events/evt-1'),
          const PushTarget(PushTargetKind.event, 'evt-1'));
    });

    test('event/club with no id → the clubs hub', () {
      // eventPath + clubPath both fall back to a bare /clubs when the row
      // carries no id (mailer.go).
      expect(pushTargetFromUrl('$_base/clubs'),
          const PushTarget(PushTargetKind.clubs));
      expect(pushTargetFromUrl('$_base/clubs/'),
          const PushTarget(PushTargetKind.clubs));
    });

    test('club_post → /clubs/{id}', () {
      expect(pushTargetFromUrl('$_base/clubs/club-7'),
          const PushTarget(PushTargetKind.club, 'club-7'));
    });

    test('plan_update + plan_assigned → /plans', () {
      expect(pushTargetFromUrl('$_base/plans'),
          const PushTarget(PushTargetKind.plans));
    });

    test('message → /messages opens the conversation list', () {
      expect(pushTargetFromUrl('$_base/messages'),
          const PushTarget(PushTargetKind.messages));
    });

    test('/messages/{id} opens that conversation', () {
      expect(pushTargetFromUrl('$_base/messages/user-4'),
          const PushTarget(PushTargetKind.messages, 'user-4'));
    });

    test('run family → /runs/{id}', () {
      expect(pushTargetFromUrl('$_base/runs/run-9'),
          const PushTarget(PushTargetKind.run, 'run-9'));
    });

    test('follow → /u/{id}', () {
      expect(pushTargetFromUrl('$_base/u/user-3'),
          const PushTarget(PushTargetKind.profile, 'user-3'));
    });

    test('challenge_complete → /challenges', () {
      expect(pushTargetFromUrl('$_base/challenges'),
          const PushTarget(PushTargetKind.challenges));
    });

    test('achievement + any future kind → /notifications', () {
      expect(pushTargetFromUrl('$_base/notifications'), PushTarget.inbox);
    });

    test('data_export_ready → /settings/account', () {
      // The archive is collected from Settings → Account, which mints the
      // signed download URL at the tap. A push landing on the inbox instead
      // would leave the runner one screen short of the thing the
      // notification is about (decisions §729).
      expect(pushTargetFromUrl('$_base/settings/account'),
          const PushTarget(PushTargetKind.settingsAccount));
    });

    test('any other /settings path degrades to the inbox', () {
      expect(pushTargetFromUrl('$_base/settings'), PushTarget.inbox);
      expect(pushTargetFromUrl('$_base/settings/preferences'), PushTarget.inbox);
    });
  });

  group('pushTargetFromUrl — tolerates a hostile payload', () {
    test('null and blank degrade to the inbox', () {
      expect(pushTargetFromUrl(null), PushTarget.inbox);
      expect(pushTargetFromUrl(''), PushTarget.inbox);
      expect(pushTargetFromUrl('   '), PushTarget.inbox);
    });

    test('any base host resolves the same target', () {
      // The same build receives links stamped with whichever APP_BASE_URL the
      // environment runs (prod / preview / a local worker).
      for (final base in [
        'https://threkir.com',
        'https://preview.threkir.com',
        'http://localhost:7777',
      ]) {
        expect(pushTargetFromUrl('$base/runs/r1'),
            const PushTarget(PushTargetKind.run, 'r1'));
      }
    });

    test('a relative path resolves identically to an absolute URL', () {
      expect(pushTargetFromUrl('/runs/r1'),
          const PushTarget(PushTargetKind.run, 'r1'));
      expect(pushTargetFromUrl('runs/r1'),
          const PushTarget(PushTargetKind.run, 'r1'));
    });

    test('trailing slash, doubled separators, query and fragment are ignored',
        () {
      expect(pushTargetFromUrl('$_base/runs/r1/'),
          const PushTarget(PushTargetKind.run, 'r1'));
      expect(pushTargetFromUrl('$_base//runs//r1'),
          const PushTarget(PushTargetKind.run, 'r1'));
      expect(pushTargetFromUrl('$_base/runs/r1?utm_source=push#top'),
          const PushTarget(PushTargetKind.run, 'r1'));
      expect(pushTargetFromUrl('  $_base/runs/r1  '),
          const PushTarget(PushTargetKind.run, 'r1'));
    });

    test('an id-bearing path with the id missing degrades, never yields ""',
        () {
      expect(pushTargetFromUrl('$_base/runs/'), PushTarget.inbox);
      expect(pushTargetFromUrl('$_base/u'), PushTarget.inbox);
      expect(pushTargetFromUrl('$_base/events'),
          const PushTarget(PushTargetKind.clubs));
    });

    test('a percent-encoded id is decoded once', () {
      expect(pushTargetFromUrl('$_base/clubs/a%20b'),
          const PushTarget(PushTargetKind.club, 'a b'));
    });

    test('an unknown or malformed path degrades to the inbox, never throws',
        () {
      for (final url in [
        '$_base/does-not-exist',
        '$_base/settings/preferences',
        '$_base',
        '$_base/',
        'not a url at all',
        '::::',
        '%%%',
      ]) {
        expect(pushTargetFromUrl(url), PushTarget.inbox, reason: url);
      }
    });

    test('an invalid percent escape in the id is passed through, not thrown',
        () {
      // Dart's Uri leaves a malformed escape as-is rather than throwing, so
      // the id survives verbatim and the screen's own fetch reports the miss.
      // Pinned so a future switch to a stricter parser is a deliberate change.
      expect(pushTargetFromUrl('$_base/runs/%ZZ'),
          const PushTarget(PushTargetKind.run, '%ZZ'));
    });
  });

  test('PushTarget is a value type', () {
    expect(const PushTarget(PushTargetKind.run, 'a'),
        const PushTarget(PushTargetKind.run, 'a'));
    expect(const PushTarget(PushTargetKind.run, 'a'),
        isNot(const PushTarget(PushTargetKind.run, 'b')));
    expect(const PushTarget(PushTargetKind.run, 'a').hashCode,
        const PushTarget(PushTargetKind.run, 'a').hashCode);
  });

  group('plan paths', () {
    const plan = '0b6f2f4e-8c1d-4a7e-9f3b-2d5c6a7b8c9d';
    const wo = '1c7a3f5e-9d2e-4b8f-8a4c-3e6d7b8c9d0e';

    test('a plan push opens that plan', () {
      expect(pushTargetFromUrl('$_base/plans/$plan'),
          const PushTarget(PushTargetKind.plan, plan));
    });

    test('a workout path opens that workout of its plan', () {
      expect(pushTargetFromUrl('$_base/plans/$plan/workouts/$wo'),
          const PushTarget(PushTargetKind.planWorkout, plan, wo));
    });

    test('an upper-case id is normalised', () {
      expect(pushTargetFromUrl('$_base/plans/${plan.toUpperCase()}'),
          const PushTarget(PushTargetKind.plan, plan));
    });

    test('other plan pages degrade to the list, or to the plan they name',
        () {
      for (final path in ['plans/new', 'plans/season', 'plans/library/x']) {
        expect(pushTargetFromUrl('$_base/$path'),
            const PushTarget(PushTargetKind.plans),
            reason: path);
      }
      expect(pushTargetFromUrl('$_base/plans/$plan/workouts'),
          const PushTarget(PushTargetKind.plan, plan));
      expect(pushTargetFromUrl('$_base/plans/$plan/workouts/not-a-uuid'),
          const PushTarget(PushTargetKind.plan, plan));
    });

    test('the workout id is part of equality', () {
      expect(const PushTarget(PushTargetKind.planWorkout, plan, wo),
          isNot(const PushTarget(PushTargetKind.planWorkout, plan, plan)));
    });
  });
}
