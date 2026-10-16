import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'l10n/gen/app_localizations.dart';
import 'plan_request_client.dart';
import 'season_types.dart';

/// Network glue for the season planner's "Describe your season" box: posts
/// the runner's description to `/api/coach/season-request` and resolves to
/// the races found in it, for the runner to confirm before anything is
/// generated. The AI is the interface, never the planner (decisions.md §12).
///
/// Same transport as the plan assistant ([postPlanAssistantRequest]): the
/// body shape, the status-to-kind mapping and the single refresh-and-replay
/// match web's `season_request_transport.ts`. Every failure throws a typed
/// [PlanRequestError], so the caller can fall back to entering races by hand.

/// The assumption keys the server may send. Mirrors
/// `SEASON_REQUEST_ASSUMPTIONS` in web's `season_request/races.ts`; each one
/// renders through [seasonAssumptionLabel].
const List<String> kSeasonRequestAssumptions = [
  'race_dropped_invalid',
  'race_dropped_date',
  'race_dropped_distance',
  'race_date_next_year',
  'goal_time_dropped',
  'race_duplicate_merged',
  'races_capped',
  'priority_default',
  'priority_a_assigned',
];

const int kMaxSeasonRaces = 12;
const double kMinSeasonRaceDistanceM = 5000;
const double kMaxSeasonRaceDistanceM = 400000;

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

const Map<String, SeasonRacePriority> _priorities = {
  'A': SeasonRacePriority.a,
  'B': SeasonRacePriority.b,
  'C': SeasonRacePriority.c,
};

SeasonRace? _parseRace(Object? raw) {
  if (raw is! Map) return null;
  final name = raw['name'];
  final date = raw['date'];
  final distance = raw['distanceM'];
  final priority = _priorities[raw['priority']];
  final goal = raw['goalTimeSec'];
  if (name is! String || name.trim().isEmpty) return null;
  if (date is! String || !_isoDate.hasMatch(date)) return null;
  if (distance is! num ||
      !distance.isFinite ||
      distance < kMinSeasonRaceDistanceM ||
      distance > kMaxSeasonRaceDistanceM) {
    return null;
  }
  if (priority == null) return null;
  if (!raw.containsKey('goalTimeSec')) return null;
  int? goalTimeSec;
  if (goal != null) {
    if (goal is! num || goal != goal.roundToDouble() || goal <= 0) return null;
    goalTimeSec = goal.toInt();
  }
  return SeasonRace(
    name: name,
    date: date,
    distanceM: distance.toDouble(),
    priority: priority,
    goalTimeSec: goalTimeSec,
  );
}

/// Parse the endpoint's 200 body. The server already validates every race,
/// so anything outside that contract — a malformed race, more races than the
/// cap, an assumption this build cannot explain — means the two halves
/// disagree, and the whole answer is refused rather than partly shown.
@visibleForTesting
SeasonRequestResult? parseSeasonRequestResult(Object? raw) {
  if (raw is! Map) return null;
  final races = raw['races'];
  final assumptions = raw['assumptions'];
  if (races is! List || races.length > kMaxSeasonRaces) return null;
  if (assumptions is! List) return null;
  final parsed = <SeasonRace>[];
  for (final r in races) {
    final race = _parseRace(r);
    if (race == null) return null;
    parsed.add(race);
  }
  final keys = <String>[];
  for (final a in assumptions) {
    if (a is! String || !kSeasonRequestAssumptions.contains(a)) return null;
    keys.add(a);
  }
  return SeasonRequestResult(races: parsed, assumptions: keys);
}

/// Extract the races from a plain-English season description. [todayIso] is
/// the runner's calendar day, so relative and year-less dates resolve
/// against it.
Future<SeasonRequestResult> requestSeasonRaces(
  String request,
  String todayIso, {
  PlanRequestPoster? post,
  Future<String?> Function()? currentToken,
  Future<String?> Function()? refreshToken,
  String? baseUrl,
}) async {
  final json = await postPlanAssistantRequest(
    '/api/coach/season-request',
    jsonEncode({'request': request, 'today': todayIso}),
    post: post,
    currentToken: currentToken,
    refreshToken: refreshToken,
    baseUrl: baseUrl,
  );
  final result = parseSeasonRequestResult(json);
  if (result == null) {
    throw const PlanRequestError(PlanRequestErrorKind.unavailable);
  }
  return result;
}

/// The localized line for one assumption key the season request returned,
/// or null for a key this build does not know (which [requestSeasonRaces]
/// already refuses). Mirrors web's `seasonAssumptionMessageKey`.
String? seasonAssumptionLabel(AppLocalizations l10n, String assumption) =>
    switch (assumption) {
      'race_dropped_invalid' => l10n.planNewSeasonAssumptionRaceDroppedInvalid,
      'race_dropped_date' => l10n.planNewSeasonAssumptionRaceDroppedDate,
      'race_dropped_distance' =>
        l10n.planNewSeasonAssumptionRaceDroppedDistance,
      'race_date_next_year' => l10n.planNewSeasonAssumptionRaceDateNextYear,
      'goal_time_dropped' => l10n.planNewSeasonAssumptionGoalTimeDropped,
      'race_duplicate_merged' =>
        l10n.planNewSeasonAssumptionRaceDuplicateMerged,
      'races_capped' => l10n.planNewSeasonAssumptionRacesCapped,
      'priority_default' => l10n.planNewSeasonAssumptionPriorityDefault,
      'priority_a_assigned' => l10n.planNewSeasonAssumptionPriorityAAssigned,
      _ => null,
    };
