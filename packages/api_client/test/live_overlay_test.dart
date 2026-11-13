import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a full get_live_overlay row decodes every field', () {
    final o = LiveOverlay.fromRow({
      'token': 'tok',
      'delay_s': 120,
      'show_map': true,
      'show_heart_rate': true,
      'created_at': '2026-11-03T10:00:00Z',
      'heart_rate_consent': true,
    });
    expect(o.token, 'tok');
    expect(o.delaySeconds, 120);
    expect(o.showMap, isTrue);
    expect(o.showHeartRate, isTrue);
    expect(o.createdAt, DateTime.utc(2026, 11, 3, 10));
    expect(o.heartRateConsent, isTrue);
  });

  test('a partial row never reads as more than was chosen', () {
    final o = LiveOverlay.fromRow({'token': 'tok'});
    expect(o.delaySeconds, 60);
    expect(o.showMap, isFalse);
    expect(o.showHeartRate, isFalse);
    expect(o.createdAt, isNull);
    expect(o.heartRateConsent, isFalse);
  });

  test('copyWith replaces only what it is given and keeps the consent', () {
    const o = LiveOverlay(
        token: 'a',
        delaySeconds: 60,
        showMap: true,
        showHeartRate: false,
        heartRateConsent: true);
    final c = o.copyWith(delaySeconds: 0);
    expect(c.token, 'a');
    expect(c.delaySeconds, 0);
    expect(c.showMap, isTrue);
    expect(c.heartRateConsent, isTrue);
    final m = o.copyWith(showMap: false, showHeartRate: true);
    expect(m.showMap, isFalse);
    expect(m.showHeartRate, isTrue);
    expect(m.delaySeconds, 60);
  });
}
