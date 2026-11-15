import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Decisions § 2542: the database refuses a settings-bag weight without
/// health-data consent (42501). A change queued offline can replay after
/// consent was withdrawn on another device; it must land without the gated
/// value, and a refused entry must never block the queue behind it.
/// Mirrors `apps/web/src/lib/settings/settings_write.test.ts`.
const _consentRefused = PostgrestException(
  message: 'user_settings: body_weight_kg needs health-data consent',
  code: '42501',
);
const _checkViolation = PostgrestException(message: 'check', code: '23514');
final _offline = Exception('SocketException: Failed host lookup');

void main() {
  test('a change refused for want of consent lands again without its gated '
      'values', () async {
    final pushed = <Map<String, dynamic>>[];
    await pushWithoutRefusedHealthPrefs(
      {'body_weight_kg': 81.5, 'weight_unit': 'kg'},
      (c) async {
        pushed.add(c);
        if (c.containsKey('body_weight_kg')) throw _consentRefused;
      },
    );
    expect(pushed, [
      {'body_weight_kg': 81.5, 'weight_unit': 'kg'},
      {'weight_unit': 'kg'},
    ]);
  });

  test('the consent retry drains through, so the change behind it is not '
      'blocked', () async {
    final sent = <Map<String, dynamic>>[];
    Future<void> push(Map<String, dynamic> c) async {
      if (c['body_weight_kg'] != null) throw _consentRefused;
      sent.add(c);
    }

    final unsent = await drainSettingsQueue<Map<String, dynamic>>(
      [
        {'body_weight_kg': 81.5},
        {'locale': 'de'},
      ],
      (c) => pushWithoutRefusedHealthPrefs(c, push),
    );
    expect(sent, [
      <String, dynamic>{},
      {'locale': 'de'},
    ]);
    expect(unsent, isEmpty);
  });

  test('a 42501 with no gated value to remove is rethrown, not retried',
      () async {
    var calls = 0;
    await expectLater(
      pushWithoutRefusedHealthPrefs({'privacy_default': 'public'}, (_) async {
        calls++;
        throw _consentRefused;
      }),
      throwsA(isA<PostgrestException>()),
    );
    expect(calls, 1);
  });

  test('another refusal, or a transport failure, is not retried', () async {
    for (final failure in <Object>[_checkViolation, _offline]) {
      var calls = 0;
      await expectLater(
        pushWithoutRefusedHealthPrefs({'body_weight_kg': 81.5}, (_) async {
          calls++;
          throw failure;
        }),
        throwsA(anything),
      );
      expect(calls, 1);
    }
  });

  test('a refused entry is dropped so it cannot block the queue', () async {
    final sent = <String>[];
    final unsent = await drainSettingsQueue<String>(['a', 'b', 'c'],
        (c) async {
      if (c == 'b') throw _checkViolation;
      sent.add(c);
    });
    expect(sent, ['a', 'c']);
    expect(unsent, isEmpty);
  });

  test('a transport failure keeps that entry and the rest, in order',
      () async {
    final sent = <String>[];
    final unsent = await drainSettingsQueue<String>(['a', 'b', 'c'],
        (c) async {
      if (c == 'b') throw _offline;
      sent.add(c);
    });
    expect(sent, ['a']);
    expect(unsent, ['b', 'c']);
  });

  test('a gated key set to null is kept: removing a value is never refused',
      () {
    expect(withoutHealthConsentPrefs({'body_weight_kg': null, 'locale': 'de'}),
        isNull);
    expect(
      withoutHealthConsentPrefs(
          {'body_weight_kg': 70, 'hr_medication_affected': null}),
      {'hr_medication_affected': null},
    );
  });
}
