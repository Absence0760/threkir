import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/disclosure_state.dart';

const DisclosureState _defaults = {
  'progress': true,
  'calendar': false,
  'weeks': true,
};

/// A store whose every read and write throws, standing in for a platform
/// channel that refuses the call.
class _RefusingPrefs implements SharedPreferences {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('store unavailable');
}

Future<SharedPreferences> _refusing() async => _RefusingPrefs();

Future<SharedPreferences> _absent() async =>
    throw StateError('no platform store');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the storage key is scoped to both the screen and the account', () {
    expect(
      disclosureStorageKey('plan_detail', 'u-1'),
      'run_app.disclosure_v1:plan_detail:u-1',
    );
    expect(
      disclosureStorageKey('plan_detail', 'u-1'),
      isNot(disclosureStorageKey('plan_detail', 'u-2')),
    );
    expect(
      disclosureStorageKey('plan_detail', 'u-1'),
      isNot(disclosureStorageKey('run_detail', 'u-1')),
    );
  });

  test('a signed-out viewer gets a key of its own rather than the last '
      'account key', () {
    expect(
      disclosureStorageKey('plan_detail', null),
      'run_app.disclosure_v1:plan_detail:anon',
    );
  });

  test('merging keeps the defaults for anything the blob does not carry', () {
    expect(mergeDisclosureState(_defaults, {'calendar': true}), {
      'progress': true,
      'calendar': true,
      'weeks': true,
    });
  });

  test('merging drops a key the screen no longer declares', () {
    final merged = mergeDisclosureState(_defaults, {
      'calendar': true,
      'retired': false,
    });
    expect(merged.keys.toList()..sort(), ['calendar', 'progress', 'weeks']);
  });

  test('merging ignores a non-boolean value rather than coercing it', () {
    expect(
      mergeDisclosureState(_defaults, {
        'progress': 'no',
        'weeks': 0,
        'calendar': true,
      }),
      {'progress': true, 'calendar': true, 'weeks': true},
    );
  });

  test('merging a blob that is not an object falls back to the defaults', () {
    for (final stored in <Object?>[
      null,
      42,
      'open',
      ['weeks'],
      true,
    ]) {
      expect(
        mergeDisclosureState(_defaults, stored),
        _defaults,
        reason: 'stored=$stored',
      );
    }
  });

  test('merging never mutates the defaults it was handed', () {
    final defaults = Map<String, bool>.of(_defaults);
    mergeDisclosureState(defaults, {'calendar': true});
    expect(defaults, _defaults);
  });

  test('a written state reads back for the same account', () async {
    await writeDisclosureState('plan_detail', 'u-1', {
      ..._defaults,
      'calendar': true,
    });
    expect(await readDisclosureState('plan_detail', 'u-1', _defaults), {
      'progress': true,
      'calendar': true,
      'weeks': true,
    });
  });

  test(
    'one account does not read another account state on a shared device',
    () async {
      await writeDisclosureState('plan_detail', 'u-1', {
        ..._defaults,
        'weeks': false,
      });
      expect(
        await readDisclosureState('plan_detail', 'u-2', _defaults),
        _defaults,
      );
    },
  );

  test('a cold read with nothing stored returns the defaults', () async {
    expect(
      await readDisclosureState('plan_detail', 'u-1', _defaults),
      _defaults,
    );
  });

  test('a corrupt blob returns the defaults instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      disclosureStorageKey('plan_detail', 'u-1'): '{not json',
    });
    expect(
      await readDisclosureState('plan_detail', 'u-1', _defaults),
      _defaults,
    );
  });

  test('a store that refuses the read returns the defaults', () async {
    expect(
      await readDisclosureState(
        'plan_detail',
        'u-1',
        _defaults,
        prefs: _refusing,
      ),
      _defaults,
    );
  });

  test(
    'a store that refuses the write does not throw at the call site',
    () async {
      await expectLater(
        writeDisclosureState('plan_detail', 'u-1', _defaults, prefs: _refusing),
        completes,
      );
    },
  );

  test('no store at all reads defaults and writes silently', () async {
    expect(
      await readDisclosureState(
        'plan_detail',
        'u-1',
        _defaults,
        prefs: _absent,
      ),
      _defaults,
    );
    await expectLater(
      writeDisclosureState('plan_detail', 'u-1', _defaults, prefs: _absent),
      completes,
    );
  });
}
