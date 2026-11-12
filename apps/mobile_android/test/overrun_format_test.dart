import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/overrun_format.dart';
import '../lib/preferences.dart';

// "Done · +3 km": whole units unless a tenth says something, decided in the
// runner's own unit. Web twin: fmtOverrun in units.svelte.ts.
void main() {
  tearDown(resetActivePreferencesForTest);

  test('kilometres: whole when the tenth is zero, one decimal otherwise', () {
    expect(fmtOverrun(3000), '3 km');
    expect(fmtOverrun(2500), '2.5 km');
    expect(fmtOverrun(400), '0.4 km');
    // 2.96 km rounds to 3.0 at a tenth, so it reads whole.
    expect(fmtOverrun(2960), '3 km');
  });

  test('ten units or more is always whole', () {
    expect(fmtOverrun(12345), '12 km');
    expect(fmtOverrun(10000), '10 km');
  });

  test('miles decide the decimal in miles, not kilometres', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'use_miles': true});
    final prefs = Preferences();
    await prefs.init();
    registerActivePreferences(prefs);

    expect(fmtOverrun(4828.032), '3 mi'); // 3.0 mi
    expect(fmtOverrun(4023.36), '2.5 mi');
    // 5 km is whole in km but 3.107 mi in miles, so it keeps its tenth.
    expect(fmtOverrun(5000), '3.1 mi');
  });
}
