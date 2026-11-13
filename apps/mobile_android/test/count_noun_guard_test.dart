// A count written into English as `{n} days` renders "1 days" for one, and
// every translation copies the same shape. The count belongs in an ICU plural
// (`{n, plural, one{{n} day} other{{n} days}}`), which gen-l10n resolves with
// the reader's locale rules (decisions § 2497, § 2507). `plansMetaWeeks`
// pluralised the weeks and left "{days} days/week" outside the plural, and
// the backup restore said "Restored 1 runs". This fails a numeric placeholder
// standing before an English plural noun outside its own plural. The web twin
// is apps/web/src/lib/i18n/count_noun_guard.test.ts.
//
// Not counts: a String or DateTime placeholder; a number used as a label
// ("Week {n} runs again", "Race {n} needs"); a word ending in s that is not a
// plural noun.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _notANoun = {
  'is', 'has', 'was', 'as', 'across', 'says', 'wants', 'sees', 'asks', //
  'falls', 'ends', 'becomes', 'needs', 'crowns', 'scores', 'ms',
};
final _labelBefore = RegExp(r'\b(Week|Race|Step|Lap|Loop|Stage|Day)\s*$');

/// A placeholder that can never hold 1: a fixed limit above 1, named with
/// its constant, or a message shown only for two or more. The map may only
/// shrink.
const _neverOne = <String, String>{
  'authErrorPasswordTooShort minLength': 'kPasswordMinLength, 8',
  'authErrorWeakPassword minLength': 'kPasswordMinLength, 8',
  'signUpErrorPasswordTooShort min': 'minPasswordLength (kPasswordMinLength), 8',
  'coachShareTooLong max': 'kCoachShareMaxChars, 4000',
  'manualDurationErrorTooLong hours': 'kMaxRunDurationS ~/ 3600, 240',
  'runDetailBlockedDurationTooLong hours': 'kMaxRunDurationS ~/ 3600, 240',
  'watchScreensCount max': 'kMaxWatchScreens, 4',
  'watchScreensFull max': 'kMaxWatchScreens, 4',
  'routesImportedMany count': 'shown only for two or more; one import is routesImported, which names the route',
};

/// Counts still written into English. Each is owed an ICU plural in all
/// seven ARBs; the set may only shrink.
const _owed = <String>{
  'billingDaysAgo count',
  'challengesUnitDays n',
  'clubDetailRoutineExerciseCount n',
  'coachDailyLimitError limit',
  'coachingAthleteAssignAfterMany count',
  'comebackLayoff weeks',
  'fundraiserDonorCount count',
  'heatmapRoutesStartHere count',
  'historySetCount n',
  'importStatusImported count',
  'importStatusImportedWithErrors count',
  'intensityWindow days',
  'nutritionRecipeMeta n',
  'nutritionRecipeMeta servings',
  'nutritionTargetsAgeYears n',
  'nutritionTemplateItems n',
  'nutritionTemplateLogged n',
  'nutritionWeekProtein total',
  'planDetailSectionWeeksHint n',
  'planNewDaysOption count',
  'planNewReturnBody weeks',
  'planNewSessions count',
  'planNudgeRestBody total',
  'planNudgeUnderBody total',
  'profileNotifAndOthers count',
  'profileNotifNameAndOthers count',
  'racesEmptyRecent days',
  'racesWhenHint days',
  'recapShareBestStreak days',
  'recapShareTotals count',
  'routeDetailAppleWatchRouteSent points',
  'routeDetailAppleWatchRouteSimplified source',
  'routeDetailStatReviews count',
  'routeDetailWatchCourseAndScheduleSent checkpoints',
  'routeDetailWatchCourseAndScheduleSent points',
  'routeDetailWatchCourseSent points',
  'routeDetailWatchCourseSentMarkersFailed points',
  'routeDetailWatchCourseSimplified source',
  'routeDetailWatchScheduleClockCutoffs checkpoints',
  'routeDetailWatchScheduleThinned checkpoints',
  'routeDetailWatchScheduleThinned points',
  'routeDetailWatchScheduleTooManyCutoffs points',
  'runDetailBlockedTrackTooLarge waypoints',
  'runDetailRouteSaved kept',
  'sessionStepReps reps',
  'settingsAccountBackupPartial total',
  'settingsAccountBackupPartialNotice total',
  'settingsAccountExportRateLimited seconds',
  'settingsAccountExportReadyBanner count',
  'shareCardSplitsHeading count',
  'simWatchCoursePushed points',
  'simWatchRoadbookPushed checkpoints',
  'simWatchWorkoutPushed steps',
  'trainingLoadSubtitleHr days',
  'ttsDistanceMetres value',
  'ttsDistanceYards value',
  'ttsDurationMinutesSeconds sec',
  'ttsDurationSeconds sec',
  'ttsPaceAlertSlowDownByKm sec',
  'ttsPaceAlertSlowDownByMi sec',
  'ttsPaceAlertSpeedUpByKm sec',
  'ttsPaceAlertSpeedUpByMi sec',
  'ttsPaceDriftAheadKm delta',
  'ttsPaceDriftAheadMi delta',
  'ttsPaceDriftBehindKm delta',
  'ttsPaceDriftBehindMi delta',
  'ttsPaceKm min',
  'ttsPaceKm sec',
  'ttsPaceMi min',
  'ttsPaceMi sec',
  'ttsRunComplete mins',
  'ttsStepPaceKm min',
  'ttsStepPaceKm sec',
  'ttsStepPaceKmWhole min',
  'ttsStepPaceMi min',
  'ttsStepPaceMi sec',
  'ttsStepPaceMiWhole min',
  'upcomingEventInDays count',
};

/// The span and argument of every plural / select block in [s]. Inside one,
/// its own argument agrees with the branch; any other placeholder is still a
/// bare count.
List<(String, int, int)> _blocks(String s) {
  final out = <(String, int, int)>[];
  for (final m
      in RegExp(r'\{(\w+),\s*(?:plural|select|selectordinal),').allMatches(s)) {
    var depth = 0;
    var j = m.start;
    do {
      if (s[j] == '{') depth++;
      if (s[j] == '}') depth--;
      j++;
    } while (j < s.length && depth > 0);
    out.add((m.group(1)!, m.start, j));
  }
  return out;
}

/// `key placeholder` for each count placeholder of [message] standing before
/// a plural noun. [types] maps a placeholder to its declared type.
Set<String> countsBeforeNouns(
  String key,
  String message,
  Map<String, String?> types,
) {
  final spans = _blocks(message);
  final hits = <String>{};
  for (final m in RegExp(r'\{(\w+)\}\s+([a-z]+(?:s\b|\(s\)))').allMatches(message)) {
    final arg = m.group(1)!;
    final type = types[arg];
    if (type == 'String' || type == 'DateTime') continue;
    if (_notANoun.contains(m.group(2))) continue;
    if (spans.any((b) => b.$1 == arg && b.$2 < m.start && m.start < b.$3)) {
      continue;
    }
    if (_labelBefore.hasMatch(message.substring(0, m.start))) continue;
    hits.add('$key $arg');
  }
  return hits;
}

void main() {
  test('the scan reads a count before a plural noun, outside its plural', () {
    expect(countsBeforeNouns('k', 'Restored {runs} runs', {'runs': 'int'}),
        {'k runs'});
    expect(countsBeforeNouns('k', 'Pushed {count} screen(s)', {'count': 'int'}),
        {'k count'});
    expect(
        countsBeforeNouns(
            'k',
            '{weeks, plural, one{{weeks} week · {days} days/week} '
                'other{{weeks} weeks · {days} days/week}}',
            {'weeks': 'int', 'days': 'int'}),
        {'k days'});
    for (final ok in [
      '{n, plural, one{{n} day} other{{n} days}}',
      'Week {n} runs again from {start}.',
      'Race {n} needs a name',
      '{name} sees this',
      '{count} km',
      'a median {ms} ms',
    ]) {
      expect(
          countsBeforeNouns('k', ok,
              {'n': 'int', 'name': 'String', 'count': 'int', 'ms': 'int'}),
          isEmpty,
          reason: ok);
    }
  });

  final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
      as Map<String, dynamic>;
  final found = <String>{};
  for (final entry in arb.entries) {
    if (entry.key.startsWith('@') || entry.value is! String) continue;
    final meta = arb['@${entry.key}'];
    final placeholders = meta is Map ? meta['placeholders'] : null;
    final types = <String, String?>{
      if (placeholders is Map)
        for (final p in placeholders.entries)
          p.key as String: (p.value is Map ? p.value['type'] : null) as String?,
    };
    found.addAll(countsBeforeNouns(entry.key, entry.value as String, types));
  }

  test('no English message writes a count before a plural noun', () {
    final offenders = found
        .where((h) => !_owed.contains(h) && !_neverOne.containsKey(h))
        .toList()
      ..sort();
    expect(offenders, isEmpty,
        reason: 'a count belongs in an ICU plural '
            '({n, plural, one{{n} day} other{{n} days}}) in all seven ARBs');
  });

  test('every _owed and _neverOne entry is still needed', () {
    for (final h in _owed) {
      expect(found, contains(h),
          reason: '$h is no longer a bare count; drop it from _owed');
    }
    for (final e in _neverOne.entries) {
      expect(e.value.trim(), isNotEmpty, reason: '${e.key}: name the constant');
      expect(found, contains(e.key),
          reason: '${e.key} is no longer a bare count; drop it from _neverOne');
      expect(_owed, isNot(contains(e.key)), reason: '${e.key} is listed twice');
    }
  });
}
