import 'dart:io' show SocketException;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/import_refusal.dart';
import '../lib/l10n/gen/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('each refusal reads as its own catalogue copy, never its message', () {
    const english = 'English log sentence';
    final cases = {
      const ImportRefused(ImportRefusalKind.tooLarge, english,
          sizeMb: 612, limitMb: 500): l10n.importRefusedTooLarge(612, 500),
      const ImportRefused(ImportRefusalKind.notStravaExport, english):
          l10n.importRefusedNotStravaExport,
      const ImportRefused(ImportRefusalKind.stravaColumnsMissing, english):
          l10n.importRefusedColumnsMissing,
      const ImportRefused(ImportRefusalKind.notBackup, english):
          l10n.importRefusedNotBackup,
      const ImportRefused(ImportRefusalKind.backupTooNew, english):
          l10n.importRefusedBackupTooNew,
    };
    expect(cases.keys.map((e) => e.kind).toSet(),
        ImportRefusalKind.values.toSet());
    for (final MapEntry(key: error, value: copy) in cases.entries) {
      expect(importErrorText(l10n, error), copy);
      expect(importErrorText(l10n, error), isNot(contains(english)));
    }
  });

  test('a refusal is still a FormatException carrying the log sentence', () {
    const e = ImportRefused(ImportRefusalKind.notBackup, 'Not a valid backup');
    expect(e, isA<FormatException>());
    expect('$e', contains('Not a valid backup'));
  });

  test('any other FormatException is an unreadable file', () {
    expect(importErrorText(l10n, const FormatException('bad byte at 12')),
        l10n.importFileUnreadable);
  });

  test('everything else reads as the classified copy', () {
    expect(importErrorText(l10n, const SocketException('Failed host lookup')),
        l10n.authErrorOffline);
    expect(importErrorText(l10n, StateError('boom')), l10n.authErrorGeneric);
  });
}
