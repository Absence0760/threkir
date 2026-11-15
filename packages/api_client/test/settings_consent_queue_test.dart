import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Decisions § 2542: the database refuses a settings-bag weight without
/// health-data consent (42501). A change queued offline can replay after
/// consent was withdrawn on another device; it must land without the gated
/// value, and a refused entry must never block the queue behind it. Online, a
/// refused write is undone and surfaced rather than queued to be dropped
/// later, while a transient failure (offline, a 5xx) stays queued.
/// Mirrors `apps/web/src/lib/settings/settings_write.test.ts`.
const _consentRefused = PostgrestException(
  message: 'user_settings: body_weight_kg needs health-data consent',
  code: '42501',
);
const _checkViolation = PostgrestException(message: 'check', code: '23514');
final _offline = Exception('SocketException: Failed host lookup');

/// The http boundary: answers `merge_my_settings` with [status] and [body]
/// (a raw string is sent as-is, anything else JSON-encoded), or throws
/// [transportError] as an offline request would.
class _FakeHttp extends http.BaseClient {
  int status = 200;
  Object? body = <String, dynamic>{};
  Object? transportError;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final err = transportError;
    if (err != null) throw err;
    final raw = body is String ? body as String : jsonEncode(body);
    return http.StreamedResponse(
      Stream.value(utf8.encode(raw)),
      status,
      headers: {
        'content-type': body is String ? 'text/html' : 'application/json',
      },
      request: request,
    );
  }
}

class _MemoryCache implements SettingsCache {
  Map<String, dynamic>? universal;
  Map<String, dynamic>? device;
  final List<PendingSettingsChange> pending = [];

  @override
  Map<String, dynamic>? readUniversal(String userId) => universal;
  @override
  Map<String, dynamic>? readDevice(String userId, String deviceId) => device;
  @override
  Future<void> writeUniversal(String userId, Map<String, dynamic> p) async =>
      universal = Map.of(p);
  @override
  Future<void> writeDevice(
          String userId, String deviceId, Map<String, dynamic> p) async =>
      device = Map.of(p);
  @override
  List<PendingSettingsChange> readPending(String userId, String deviceId) =>
      List.of(pending);
  @override
  Future<void> appendPending(String userId, String deviceId,
          PendingSettingsChange change) async =>
      pending.add(change);
  @override
  Future<void> clearPending(String userId, String deviceId) async =>
      pending.clear();
  @override
  Future<void> dropUser(String userId) async {}
}

Future<(SettingsService, _FakeHttp, _MemoryCache)> _service() async {
  final fake = _FakeHttp();
  final cache = _MemoryCache();
  final client = SupabaseClient(
    'http://127.0.0.1:24321',
    'test-anon-key',
    httpClient: fake,
  );
  await client.auth.setInitialSession(jsonEncode({
    'access_token': 'fake-token',
    'token_type': 'bearer',
    'user': {
      'id': 'user-1',
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  }));
  final service = SettingsService.withClient(
    client,
    deviceId: 'device-1',
    platform: 'android',
    cache: cache,
  );
  return (service, fake, cache);
}

void main() {
  group('an online universal write', () {
    test('a refusal is undone, rethrown for the caller to show, and not '
        'queued', () async {
      final (service, fake, cache) = await _service();
      fake
        ..status = 403
        ..body = {'code': '42501', 'message': 'needs health-data consent'};
      await expectLater(
        service.updateUniversal({'body_weight_kg': 81.5}),
        throwsA(isA<PostgrestException>()
            .having((e) => e.code, 'code', '42501')),
      );
      expect(service.universal.containsKey('body_weight_kg'), isFalse);
      expect(cache.universal?.containsKey('body_weight_kg'), isFalse);
      expect(cache.pending, isEmpty);
      expect(fake.calls, 1, reason: 'the online write is not retried stripped');
    });

    test('a CHECK refusal is surfaced the same way', () async {
      final (service, fake, cache) = await _service();
      fake
        ..status = 400
        ..body = {'code': '23514', 'message': 'check violation'};
      await expectLater(
        service.updateUniversal({'privacy_default': 'nobody'}),
        throwsA(isA<PostgrestException>()),
      );
      expect(service.universal, isEmpty);
      expect(cache.pending, isEmpty);
    });

    test('offline, the change stays local and is queued', () async {
      final (service, fake, cache) = await _service();
      fake.transportError = http.ClientException('Failed host lookup');
      await service.updateUniversal({'locale': 'de'});
      expect(service.universal['locale'], 'de');
      expect(cache.pending.single.changes, {'locale': 'de'});
    });

    test('a 5xx with an unreadable body stays queued', () async {
      final (service, fake, cache) = await _service();
      fake
        ..status = 503
        ..body = '<html>Service Unavailable</html>';
      await service.updateUniversal({'locale': 'de'});
      expect(service.universal['locale'], 'de');
      expect(cache.pending.single.changes, {'locale': 'de'});
    });

    test('a device write that is refused is undone and surfaced too',
        () async {
      final (service, fake, cache) = await _service();
      fake
        ..status = 403
        ..body = {'code': '42501', 'message': 'denied'};
      await expectLater(
        service.updateDevice({'keep_screen_on': true}),
        throwsA(isA<PostgrestException>()),
      );
      expect(service.device, isEmpty);
      expect(cache.pending, isEmpty);
    });
  });

  test('transient codes are not refusals; constraint and permission codes '
      'are', () {
    for (final code in ['503', '502', 'PGRST000', 'PGRST003', '08006',
        '40001', '40P01', '53300', '57014', '55P03']) {
      expect(
          settingsWriteRejected(PostgrestException(message: 'x', code: code)),
          isFalse,
          reason: code);
    }
    for (final code in ['42501', '23514', '23502', '22023', 'PGRST204', '400',
        '401']) {
      expect(
          settingsWriteRejected(PostgrestException(message: 'x', code: code)),
          isTrue,
          reason: code);
    }
    expect(settingsWriteRejected(http.ClientException('offline')), isFalse);
  });

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
