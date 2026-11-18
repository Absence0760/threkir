import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

// Host-side entry for the store capture (store_screenshots_capture.dart).
// The suite sends its captures in its report data (store_capture_kit.dart);
// this writes them to `$STORE_SCREENSHOTS_DIR`, or `build/store_screenshots/`
// from the app directory when the variable is unset:
//
//   <name>.png    one per capture the panels crop
//   bounds.json   where each section sits in each capture
//   numbers.json  what the screens say, for the captions
//
// assets/store/README.md documents both JSON files. A run that fails writes
// nothing, so a half-finished set never reaches the renderer.
Future<void> main() async {
  final dir = Directory(
      Platform.environment['STORE_SCREENSHOTS_DIR'] ?? 'build/store_screenshots');
  await integrationDriver(
    responseDataCallback: (data) async {
      final files = data?['store_files'] as Map<String, dynamic>?;
      if (files == null || files.isEmpty) {
        throw StateError('the capture suite reported no store captures');
      }
      await dir.create(recursive: true);
      for (final e in files.entries) {
        await File('${dir.path}/${e.key}')
            .writeAsBytes(base64Decode(e.value as String));
        stdout.writeln('store capture: ${dir.path}/${e.key}');
      }
      const pretty = JsonEncoder.withIndent(' ');
      for (final (key, file) in const [
        ('store_bounds', 'bounds.json'),
        ('store_numbers', 'numbers.json'),
      ]) {
        await File('${dir.path}/$file')
            .writeAsString('${pretty.convert(data![key])}\n');
        stdout.writeln('store capture: ${dir.path}/$file');
      }
    },
  );
}
