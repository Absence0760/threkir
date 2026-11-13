import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Speaks [message] once through TalkBack / VoiceOver, in the reading
/// direction of [context].
///
/// A screen reader is a status-message channel (WCAG 4.1.3) that a
/// `Semantics(liveRegion: true)` around changing text abuses when the text
/// changes faster than a sentence can be read: TalkBack queues every change,
/// and a per-second clock talks over the whole screen. A clock announces
/// here at the marks [countdownAnnouncementDue] picks instead.
///
/// Best-effort: an announcer failure never reaches the caller (L4).
void announceForAccessibility(BuildContext context, String message) {
  try {
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    SemanticsService.sendAnnouncement(View.of(context), message, direction);
  } catch (e) {
    debugPrint('SemanticsService.announce failed: $e');
  }
}

/// Whether a countdown at [secondsLeft] is a mark worth a spoken update:
/// every hour, every ten minutes inside the last hour, every minute inside
/// the last ten, and 30, 10 and 5 seconds. Coarse on purpose: a runner
/// arming a race hours early hears it a handful of times, not every second.
bool isCountdownAnnouncementMark(int secondsLeft) {
  if (secondsLeft <= 0) return false;
  if (secondsLeft == 30 || secondsLeft == 10 || secondsLeft == 5) return true;
  if (secondsLeft % 3600 == 0) return true;
  if (secondsLeft < 3600 && secondsLeft % 600 == 0) return true;
  return secondsLeft <= 600 && secondsLeft % 60 == 0;
}

/// Whether the countdown moving from [previousS] to [currentS] crossed an
/// announcement mark, or started (no previous value). A tick that skips
/// seconds (the app was backgrounded) still announces the mark it passed,
/// but only once.
bool countdownAnnouncementDue(int? previousS, int? currentS) {
  if (currentS == null || currentS <= 0) return false;
  if (previousS == null) return true;
  if (currentS >= previousS) return false;
  // Any span of an hour or more holds an hour mark.
  if (previousS - currentS >= 3600) return true;
  for (var s = previousS - 1; s >= currentS; s--) {
    if (isCountdownAnnouncementMark(s)) return true;
  }
  return false;
}
