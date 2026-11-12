// ignore_for_file: avoid_relative_lib_imports
// Mirrors apps/web/src/lib/social/dm_image.test.ts case-for-case.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_image.dart';

String _sql() => Directory('../backend/supabase/migrations')
    .listSync()
    .whereType<File>()
    .firstWhere((f) => f.path.endsWith('_dm_images.sql'))
    .readAsStringSync();

void main() {
  test('the limits are the bucket and size CHECK the migration sets', () {
    final sql = _sql();
    final bucket = RegExp(
      r"values \('dm-images', 'dm-images', false, (\d+), array\['([^']+)'\]\)",
    ).firstMatch(sql);
    expect(bucket, isNotNull, reason: 'the dm-images bucket insert was not found');
    expect(kDmImageMaxBytes, int.parse(bucket!.group(1)!));
    expect(kDmImageContentType, bucket.group(2));
    expect(sql, contains('width between 1 and $kDmImageMaxEdge'));
    expect(sql, contains('height between 1 and $kDmImageMaxEdge'));
  });

  test('the statuses are the ones the CHECK admits', () {
    final m = RegExp(r'check \(status in \(([^)]*)\)\)').firstMatch(_sql());
    expect(m, isNotNull);
    expect(
      RegExp(r"'([a-z_]+)'").allMatches(m!.group(1)!).map((x) => x.group(1)),
      kDmImageStatuses,
    );
    expect(parseDmImageStatus('ready'), 'ready');
    expect(parseDmImageStatus('rejected'), 'rejected');
    expect(parseDmImageStatus('weird'), 'pending');
  });

  test(
      'a pending photo is checked fast for about three minutes, then slowly '
      'for good', () {
    expect(dmImageRecheckDelay(1), const Duration(seconds: 4));
    expect(dmImageRecheckDelay(44), const Duration(seconds: 4));
    expect(dmImageRecheckDelay(45), const Duration(seconds: 30));
    expect(dmImageRecheckDelay(1000), const Duration(seconds: 30));
    expect(dmImageRecheckDelay(1) * 44, const Duration(seconds: 176));
  });

  test('a photo is scaled down to the long edge and never up', () {
    expect(dmImageFit(4032, 3024), (width: 2048, height: 1536));
    expect(dmImageFit(3024, 4032), (width: 1536, height: 2048));
    expect(dmImageFit(800, 600), (width: 800, height: 600));
    expect(dmImageFit(2048, 2048), (width: 2048, height: 2048));
    expect(dmImageFit(100000, 10), (width: 2048, height: 1));
    expect(dmImageFit(0, 10), (width: 0, height: 0));
    expect(dmImageFit(double.nan, 10), (width: 0, height: 0));
  });
}
