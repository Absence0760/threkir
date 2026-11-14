import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// Host-side entry for the store capture (store_screenshots_capture.dart):
// writes each `binding.takeScreenshot(name)` to `$STORE_SCREENSHOTS_DIR/
// <name>.png`, or `build/store_screenshots/` from the app directory when the
// variable is unset. `driver.dart` beside the suites keeps no screenshots,
// which is why this one is separate.
Future<void> main() async {
  final dir = Directory(
      Platform.environment['STORE_SCREENSHOTS_DIR'] ?? 'build/store_screenshots');
  await dir.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
      stdout.writeln('store screenshot: ${dir.path}/$name.png');
      return true;
    },
  );
}
