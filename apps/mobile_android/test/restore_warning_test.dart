import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/backup.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/restore_warning.dart';

class _PostgrestShaped implements Exception {
  @override
  String toString() =>
      'PostgrestException(message: new row for relation "runs" violates '
      'check constraint "runs_hr_series_url_path_shape", code: 23514)';
}

void main() {
  // One warning of every kind, each carrying a raw failure whose text must
  // never reach the sentence. Iterating the enum means a new kind is covered
  // the moment it exists.
  List<RestoreWarning> everyKind() => [
        for (final kind in RestoreWarningKind.values)
          RestoreWarning(
            kind,
            itemId: 'run-abc',
            index: 4,
            columns: const ['legacy_pace'],
            error: _PostgrestShaped(),
          ),
      ];

  for (final locale in AppLocalizations.supportedLocales) {
    final l10n = lookupAppLocalizations(locale);

    test('$locale: no warning renders the caught failure as text', () {
      for (final w in everyKind()) {
        final text = restoreWarningText(l10n, w);
        expect(text, isNotEmpty, reason: w.kind.name);
        expect(text, isNot(contains('runs_hr_series_url_path_shape')),
            reason: w.kind.name);
        expect(text, isNot(contains('PostgrestException')),
            reason: w.kind.name);
      }
    });
  }

  final l10n = lookupAppLocalizations(const Locale('en'));

  test('a failure reads as its classified reason', () {
    final text = restoreWarningText(
      l10n,
      RestoreWarning(RestoreWarningKind.run,
          itemId: 'run-abc', error: _PostgrestShaped()),
    );
    expect(text, l10n.importRestoreWarnRun('run-abc', l10n.authErrorGeneric));
  });

  test('a row with no id is named by its 1-based position', () {
    expect(
      restoreWarningText(
          l10n, const RestoreWarning(RestoreWarningKind.runNoId, index: 0)),
      l10n.importRestoreWarnRunNoId(1),
    );
    expect(
      restoreWarningText(l10n,
          const RestoreWarning(RestoreWarningKind.route, index: 2)),
      l10n.importRestoreWarnRoute('#3', l10n.authErrorGeneric),
    );
  });

  test('the raw failure stays in the log line', () {
    final w = RestoreWarning(RestoreWarningKind.track,
        itemId: 'run-abc', error: _PostgrestShaped());
    expect('$w', contains('runs_hr_series_url_path_shape'));
    expect('$w', contains('run-abc'));
  });

  test('an incomplete archive leads the list', () {
    final result = RestoreResult()
      ..warn(const RestoreWarning(RestoreWarningKind.runNoId, index: 0));
    BackupService.noteIncompleteArchive(
        {'complete': false, 'incomplete': ['tracks']}, result);
    expect(result.warnings.map((w) => w.kind), [
      RestoreWarningKind.archiveIncomplete,
      RestoreWarningKind.runNoId,
    ]);
    expect(result.archiveIncompleteSections, ['tracks']);
  });
}
