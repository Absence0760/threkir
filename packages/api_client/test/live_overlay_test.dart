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
    });
    expect(o.token, 'tok');
    expect(o.delaySeconds, 120);
    expect(o.showMap, isTrue);
    expect(o.showHeartRate, isTrue);
    expect(o.createdAt, DateTime.utc(2026, 11, 3, 10));
  });

  test('a partial row never reads as more than was chosen', () {
    final o = LiveOverlay.fromRow({'token': 'tok'});
    expect(o.delaySeconds, 60);
    expect(o.showMap, isFalse);
    expect(o.showHeartRate, isFalse);
    expect(o.createdAt, isNull);
  });

  test('copyWith replaces only the token and delay', () {
    const o = LiveOverlay(
        token: 'a', delaySeconds: 60, showMap: true, showHeartRate: false);
    final c = o.copyWith(delaySeconds: 0);
    expect(c.token, 'a');
    expect(c.delaySeconds, 0);
    expect(c.showMap, isTrue);
  });
}
