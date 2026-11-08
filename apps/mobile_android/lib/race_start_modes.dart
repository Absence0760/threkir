/// Race start modes (#1306, decisions § 2400-§ 2401), spec
/// `race_start_modes v1`: a session's status on the server clock, the
/// scheduled-GO countdown and its voice marks, offsets from the occurrence as
/// wall times, and what a Self-timed banner offers. Pure: no Flutter, no I/O.
///
/// Web twin: `apps/web/src/lib/races/race_start_modes.ts` (the `race_start_modes`
/// pair in `docs/architecture/parity_pairs.md`). Both read
/// `fixtures/race_start_modes_cases.json`.
library;

import 'course_gates.dart';

enum RaceStatus { armed, running, finished, cancelled }

RaceStatus? raceStatusFromWire(String? s) => switch (s) {
      'armed' => RaceStatus.armed,
      'running' => RaceStatus.running,
      'finished' => RaceStatus.finished,
      'cancelled' => RaceStatus.cancelled,
      _ => null,
    };

SessionStartMode sessionStartModeFromWire(String? s) => switch (s) {
      'scheduled' => SessionStartMode.scheduled,
      'self_timed' => SessionStartMode.selfTimed,
      _ => SessionStartMode.hostGo,
    };

class StartModeSession {
  const StartModeSession({
    required this.status,
    required this.startMode,
    this.scheduledStartAt,
    this.windowOpensAt,
    this.windowClosesAt,
  });

  final RaceStatus status;
  final SessionStartMode startMode;
  final DateTime? scheduledStartAt;
  final DateTime? windowOpensAt;
  final DateTime? windowClosesAt;
}

/// The longest a self-timed window (or a scheduled race's auto-end) lasts.
const int kRaceWindowMaxS = 7 * 24 * 3600;

/// The seconds-left marks the run screen speaks during a scheduled countdown.
const List<int> kVoiceCountdownMarksS = [10, 5, 3, 2, 1];

/// The status a session is in on the server clock.
RaceStatus effectiveRaceStatus(StartModeSession s, DateTime serverNow) {
  if (s.status == RaceStatus.finished || s.status == RaceStatus.cancelled) {
    return s.status;
  }
  if (s.startMode == SessionStartMode.hostGo) return s.status;
  final start = s.scheduledStartAt ?? s.windowOpensAt;
  final close = s.windowClosesAt;
  final startPassed = start != null && !start.isAfter(serverNow);
  if (close != null &&
      !close.isAfter(serverNow) &&
      (s.status == RaceStatus.running || startPassed)) {
    return RaceStatus.finished;
  }
  if (s.status == RaceStatus.armed && startPassed) return RaceStatus.running;
  return s.status;
}

/// The instant a session's clock starts: the scheduled GO or the window's
/// opening; null for Host GO.
DateTime? raceStartInstant(StartModeSession s) => switch (s.startMode) {
      SessionStartMode.scheduled => s.scheduledStartAt,
      SessionStartMode.selfTimed => s.windowOpensAt,
      SessionStartMode.hostGo => null,
    };

/// Whole seconds until [target] on the server clock, never negative; null
/// without a target.
int? raceCountdownS(DateTime? target, DateTime deviceNow, int serverOffsetMs) {
  if (target == null) return null;
  final ms = target.millisecondsSinceEpoch -
      (deviceNow.millisecondsSinceEpoch + serverOffsetMs);
  final s = (ms / 1000).ceil();
  return s < 0 ? 0 : s;
}

/// The mark to speak when a countdown moves from [previousS] to [currentS]
/// seconds left, or null. A tick that skips a mark speaks nothing late.
int? voiceCountdownCue(int? previousS, int? currentS) {
  if (previousS == null || currentS == null || currentS >= previousS) {
    return null;
  }
  for (final mark in kVoiceCountdownMarksS) {
    if (currentS == mark && previousS == mark + 1) return mark;
  }
  return null;
}

class LocalStartOffset {
  const LocalStartOffset({required this.dayOffset, required this.minuteOfDay});

  /// Whole days after the occurrence's start date (negative: before).
  final int dayOffset;

  /// Minutes after midnight on that day, 0-1439.
  final int minuteOfDay;

  @override
  bool operator ==(Object other) =>
      other is LocalStartOffset &&
      other.dayOffset == dayOffset &&
      other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => Object.hash(dayOffset, minuteOfDay);

  @override
  String toString() => 'LocalStartOffset($dayOffset, $minuteOfDay)';
}

/// The offset (seconds) from an occurrence starting at [startMinuteOfDay] to
/// a wall time [local].dayOffset days later at [local].minuteOfDay.
int startOffsetFromLocal(int startMinuteOfDay, LocalStartOffset local) =>
    (local.dayOffset * 1440 + local.minuteOfDay - startMinuteOfDay) * 60;

/// The inverse of [startOffsetFromLocal], whole minutes.
LocalStartOffset localFromStartOffset(int startMinuteOfDay, int offsetS) {
  final total = startMinuteOfDay + (offsetS / 60).round();
  final day = (total / 1440).floor();
  return LocalStartOffset(dayOffset: day, minuteOfDay: total - day * 1440);
}

enum SelfTimedAttemptState { notOpen, join, chooseCourse, attempt, closed }

/// What a Self-timed banner offers: join (RSVP) when not going, then a course
/// when the race has several and none is chosen, then the attempt.
SelfTimedAttemptState selfTimedAttemptState({
  required RaceStatus effectiveStatus,
  required bool going,
  required int courseCount,
  required bool courseChosen,
}) {
  if (effectiveStatus == RaceStatus.armed) return SelfTimedAttemptState.notOpen;
  if (effectiveStatus != RaceStatus.running) {
    return SelfTimedAttemptState.closed;
  }
  if (!going) return SelfTimedAttemptState.join;
  if (courseCount > 1 && !courseChosen) {
    return SelfTimedAttemptState.chooseCourse;
  }
  return SelfTimedAttemptState.attempt;
}

class StartSettings {
  const StartSettings({
    required this.mode,
    this.scheduledOffsetS,
    this.windowOpenOffsetS,
    this.windowLengthS,
  });

  final SessionStartMode mode;
  final int? scheduledOffsetS;
  final int? windowOpenOffsetS;
  final int? windowLengthS;
}

/// The events CHECKs, in the order the editor reports them, as wire codes.
/// Mobile does not edit events (decisions § 24); the twin keeps the rule in
/// one table so the race director's read-only summary agrees with web's.
List<String> validateStartSettings(StartSettings s) {
  final out = <String>[];
  if (s.mode == SessionStartMode.hostGo) return out;
  if (s.mode == SessionStartMode.scheduled) {
    final o = s.scheduledOffsetS;
    if (o == null) {
      out.add('scheduled_offset_required');
    } else if (o.abs() > 24 * 3600) {
      out.add('scheduled_offset_range');
    }
  } else {
    final o = s.windowOpenOffsetS;
    if (o == null) {
      out.add('window_open_required');
    } else if (o < -24 * 3600 || o > 7 * 24 * 3600) {
      out.add('window_open_range');
    }
  }
  final len = s.windowLengthS;
  if (len == null) {
    out.add('window_length_required');
  } else if (len < 60 || len > kRaceWindowMaxS) {
    out.add('window_length_range');
  }
  return out;
}
