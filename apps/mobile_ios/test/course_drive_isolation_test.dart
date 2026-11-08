import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A drive can never become a run (docs/features/course_drive.md, gotcha 1):
/// no `runs` row, no PR, no live-tracking session, no challenge or plan
/// credit. The drive files hold a distance along the course and nothing
/// else, so none of them may reach the recorder, the run store, sync, live
/// tracking or the credit paths — not by import and not by name.
void main() {
  const files = [
    'lib/course_drive.dart',
    'lib/course_drive_check.dart',
    'lib/course_drive_location.dart',
    'lib/course_drive_notice.dart',
    'lib/course_drive_speech.dart',
    'lib/course_drive_tracker.dart',
    'lib/screens/course_drive_screen.dart',
  ];
  final forbiddenImports = RegExp(
    r"""import\s+'(package:run_recorder/[^']*|[^']*(local_run_store|run_sync|background_sync|offline_sync_store|live_[a-z_]+|challenge_[a-z_]+|plan_[a-z_]+|training_service|api_client)[^']*)'""",
  );
  final forbiddenNames = RegExp(
    r'\b(RunRecorder|LocalRunStore|saveRun|saveRunsBatch|LiveBroadcaster|LiveBroadcast|RunSnapshot)\b',
  );

  for (final path in files) {
    test(
      '$path reaches nothing that records, syncs, broadcasts or credits',
      () {
        final src = File(path).readAsStringSync();
        expect(
          forbiddenImports.allMatches(src).map((m) => m.group(1)),
          isEmpty,
        );
        final code = src
            .split('\n')
            .where(
              (l) =>
                  !l.trimLeft().startsWith('///') &&
                  !l.trimLeft().startsWith('//'),
            )
            .join('\n');
        expect(forbiddenNames.allMatches(code).map((m) => m.group(0)), isEmpty);
      },
    );
  }

  test('the guarded list is every drive file in lib/', () {
    final onDisk = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            RegExp(r'course_drive[a-z_]*\.dart$').hasMatch(f.path) &&
            !f.path.endsWith('course_drive_flag.dart'))
          f.path.replaceAll(r'\', '/'),
    ]..sort();
    expect(onDisk, [...files]..sort());
  });
}
