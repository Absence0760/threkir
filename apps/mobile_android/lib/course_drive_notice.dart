import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local flag: the driver safety notice for Drive this course
/// (docs/features/course_drive.md, gotcha 8) has been acknowledged on this
/// phone. The notice is about how the phone in hand is used in a car, so it
/// lives in raw SharedPreferences and never roams through the settings bags.
const kCourseDriveNoticeAckKey = 'course_drive_notice_ack';

/// Whether this device has acknowledged the notice. A storage failure reads
/// as not acknowledged: showing a safety notice twice costs a tap, skipping
/// it costs the notice.
Future<bool> courseDriveNoticeAcknowledged() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kCourseDriveNoticeAckKey) ?? false;
  } catch (e) {
    debugPrint('course drive notice: reading the acknowledgement failed: $e');
    return false;
  }
}

/// Records the acknowledgement. Never throws: the drive starts either way.
Future<void> acknowledgeCourseDriveNotice() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kCourseDriveNoticeAckKey, true);
  } catch (e) {
    debugPrint('course drive notice: saving the acknowledgement failed: $e');
  }
}
