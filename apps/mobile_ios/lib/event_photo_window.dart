/// Which of a runner's runs may join an occurrence's photo gallery.
///
/// The database refuses an attendee photo whose run did not START inside
/// [occurrence − 2 h, occurrence + 24 h) (`run_photos_event_integrity`,
/// migration 20270807000001, decisions § 1904), so the run picker offers only
/// the runs that will be accepted rather than letting the upload fail. Dart
/// twin of web's `apps/web/src/lib/social/event_photo_window.ts` — keep the two
/// in lockstep. Web parses two ISO strings; here both sides are already
/// `DateTime`s, so a missing or unparseable value arrives as null.

const Duration kEventPhotoWindowBefore = Duration(hours: 2);
const Duration kEventPhotoWindowAfter = Duration(hours: 24);

/// True when a run that started at [runStartedAt] may be attached to the
/// occurrence at [instanceStart]. Missing input is outside the window.
bool isRunInEventPhotoWindow(DateTime? runStartedAt, DateTime? instanceStart) {
  if (runStartedAt == null || instanceStart == null) return false;
  final opens = instanceStart.subtract(kEventPhotoWindowBefore);
  final closes = instanceStart.add(kEventPhotoWindowAfter);
  return !runStartedAt.isBefore(opens) && runStartedAt.isBefore(closes);
}

/// True when a steward may already post run-less photos for the occurrence:
/// from two hours before it starts (set-up shots) onwards.
bool hasEventPhotoWindowOpened(DateTime? instanceStart, DateTime now) {
  if (instanceStart == null) return false;
  return !now.isBefore(instanceStart.subtract(kEventPhotoWindowBefore));
}
