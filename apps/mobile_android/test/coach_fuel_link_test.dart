import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/coach_screen.dart';

// The Coach's fuelling handoff (decisions § 1975) links to the web-only
// /nutrition/fuel page. The phone opens it on the configured web host,
// carrying only the four fuelling parameters; the page validates each value.
void main() {
  const base = 'https://preview.threkir.com';

  test('a fuelling link opens the web page with its parameters', () {
    expect(
      coachFuelLinkWebUrl('/nutrition/fuel?duration=9000&carbs=70&heat=1',
          webBase: base),
      'https://preview.threkir.com/nutrition/fuel?duration=9000&carbs=70&heat=1',
    );
  });

  test('parameters the page does not read are dropped', () {
    expect(
      coachFuelLinkWebUrl(
          '/nutrition/fuel?duration=3600&redirect=https://evil.example&fluid=500',
          webBase: base),
      'https://preview.threkir.com/nutrition/fuel?duration=3600&fluid=500',
    );
  });

  test('a bare fuelling link opens the bare page', () {
    expect(coachFuelLinkWebUrl('/nutrition/fuel', webBase: '$base/'),
        'https://preview.threkir.com/nutrition/fuel');
  });

  test('an absolute or protocol-relative URL is never treated as the handoff',
      () {
    expect(
        coachFuelLinkWebUrl('https://evil.example/nutrition/fuel?duration=1',
            webBase: base),
        isNull);
    expect(
        coachFuelLinkWebUrl('//evil.example/nutrition/fuel', webBase: base),
        isNull);
  });

  test('any other in-app path is not the fuelling link', () {
    expect(coachFuelLinkWebUrl('/plans/new?describe=x', webBase: base),
        isNull);
    expect(coachFuelLinkWebUrl('/nutrition', webBase: base), isNull);
    expect(coachFuelLinkWebUrl('/runs/abc', webBase: base), isNull);
  });

  test('an empty host falls back to production', () {
    expect(coachFuelLinkWebUrl('/nutrition/fuel?duration=3600', webBase: ''),
        'https://threkir.com/nutrition/fuel?duration=3600');
  });
}
