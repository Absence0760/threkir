import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_disclosure.dart';
import 'payload_hash.dart';
import 'training.dart';

/// Network glue for the plan wizard's "Describe the plan you want" box. It
/// posts the runner's description to `/api/coach/plan-request` and resolves
/// to validated [PlanRequestInputs] the wizard fills its own fields from. The
/// AI is the interface, never the planner: the generator builds the plan from
/// those fields exactly as it does for a hand-filled form.
///
/// The manual wizard is the fallback, so every failure throws a typed
/// [PlanRequestError] and the caller keeps the form working. Refreshes the
/// JWT once on a 401. Twin of web's `training/plan_request_client.ts` — keep
/// the body shape, the status-to-kind mapping and the single refresh-and-
/// replay in lockstep.

enum PlanRequestErrorKind {
  notAuthenticated,
  consent,
  dailyLimit,
  invalid,
  notUnderstood,
  unavailable,
}

class PlanRequestError implements Exception {
  final PlanRequestErrorKind kind;
  const PlanRequestError(this.kind);

  @override
  String toString() => 'PlanRequestError(${kind.name})';
}

PlanRequestErrorKind planRequestErrorKind(int status, String? code) {
  if (status == 401) return PlanRequestErrorKind.notAuthenticated;
  if (status == 403 && code == kAiDisclosureError) {
    return PlanRequestErrorKind.consent;
  }
  if (status == 429) return PlanRequestErrorKind.dailyLimit;
  if (status == 400) return PlanRequestErrorKind.invalid;
  if (status == 422) return PlanRequestErrorKind.notUnderstood;
  return PlanRequestErrorKind.unavailable;
}

/// Why a field holds what it holds when it is not simply what the runner
/// asked for. Mirrors `PLAN_REQUEST_ASSUMPTIONS` in web's
/// `plan_request/inputs.ts`; each one is rendered as a localized line.
enum PlanRequestAssumption {
  goalEventDefault('goal_event_default'),
  daysPerWeekDefault('days_per_week_default'),
  daysPerWeekClamped('days_per_week_clamped'),
  weeksClamped('weeks_clamped'),
  raceDateDropped('race_date_dropped'),
  goalTimeDropped('goal_time_dropped'),
  recent5kDropped('recent_5k_dropped'),
  beginner5k('beginner_5k');

  final String wire;
  const PlanRequestAssumption(this.wire);
}

class PlanRequestInputs {
  final GoalEvent goalEvent;

  /// ISO `yyyy-mm-dd`; the server only sends a future date within two years.
  final String? raceDate;
  final int? goalTimeSec;
  final int? recent5kSec;
  final int daysPerWeek;
  final int? weeks;
  final bool beginnerWalkRun;
  final String? planName;
  final List<PlanRequestAssumption> assumptions;

  const PlanRequestInputs({
    required this.goalEvent,
    required this.raceDate,
    required this.goalTimeSec,
    required this.recent5kSec,
    required this.daysPerWeek,
    required this.weeks,
    required this.beginnerWalkRun,
    required this.planName,
    required this.assumptions,
  });
}

const Map<String, GoalEvent> _goalEvents = {
  'distance_5k': GoalEvent.distance5k,
  'distance_10k': GoalEvent.distance10k,
  'distance_half': GoalEvent.distanceHalf,
  'distance_full': GoalEvent.distanceFull,
};

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

class _Malformed implements Exception {
  const _Malformed();
}

int? _optInt(Object? v, int min, int max) {
  if (v == null) return null;
  return _reqInt(v, min, max);
}

int _reqInt(Object? v, int min, int max) {
  if (v is! num || !v.isFinite || v != v.roundToDouble()) {
    throw const _Malformed();
  }
  final n = v.toInt();
  if (n < min || n > max) throw const _Malformed();
  return n;
}

/// Parse the endpoint's `inputs` object. The server already validates and
/// clamps every field, so anything outside that contract — an unknown goal,
/// an out-of-range number, an assumption this build cannot explain — means
/// the two halves disagree, and the whole answer is refused rather than
/// partly applied. Returns null on any such mismatch.
@visibleForTesting
PlanRequestInputs? parsePlanRequestInputs(Object? raw) {
  if (raw is! Map) return null;
  try {
    final goal = _goalEvents[raw['goalEvent']];
    if (goal == null) return null;

    final raceDate = raw['raceDate'];
    if (raceDate != null &&
        (raceDate is! String || !_isoDate.hasMatch(raceDate))) {
      return null;
    }

    final beginner = raw['beginnerWalkRun'];
    if (beginner is! bool) return null;

    final planName = raw['planName'];
    if (planName != null && planName is! String) return null;

    final rawAssumptions = raw['assumptions'];
    if (rawAssumptions is! List) return null;
    final assumptions = <PlanRequestAssumption>[];
    for (final a in rawAssumptions) {
      final match =
          PlanRequestAssumption.values.where((v) => v.wire == a).firstOrNull;
      if (match == null) return null;
      assumptions.add(match);
    }

    return PlanRequestInputs(
      goalEvent: goal,
      raceDate: raceDate as String?,
      goalTimeSec: _optInt(raw['goalTimeSec'], 1, 10 * 3600 - 1),
      recent5kSec: _optInt(raw['recent5kSec'], 12 * 60, 60 * 60 - 1),
      daysPerWeek: _reqInt(raw['daysPerWeek'], 3, 7),
      weeks: _optInt(raw['weeks'], 4, 24),
      beginnerWalkRun: beginner,
      planName: planName as String?,
      assumptions: assumptions,
    );
  } on _Malformed {
    return null;
  }
}

class PlanRequestHttpResponse {
  final int statusCode;
  final String body;
  const PlanRequestHttpResponse(this.statusCode, this.body);
}

/// One POST. Tests inject a fake; production uses dart:io's [HttpClient].
typedef PlanRequestPoster = Future<PlanRequestHttpResponse> Function(
  Uri url,
  Map<String, String> headers,
  String body,
);

Future<PlanRequestHttpResponse> _defaultPost(
  Uri url,
  Map<String, String> headers,
  String body,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    headers.forEach(req.headers.set);
    req.add(utf8.encode(body));
    final res = await req.close();
    final raw = await res.transform(utf8.decoder).join();
    return PlanRequestHttpResponse(res.statusCode, raw);
  } finally {
    client.close(force: true);
  }
}

String _webBase() =>
    ((dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null) ??
            'https://threkir.com')
        .replaceAll(RegExp(r'/$'), '');

Future<String?> _currentToken() async =>
    Supabase.instance.client.auth.currentSession?.accessToken;

Future<String?> _refreshToken() async =>
    (await Supabase.instance.client.auth.refreshSession())
        .session
        ?.accessToken;

/// Extract plan-wizard inputs from a plain-English description. [todayIso] is
/// the runner's calendar day, so relative dates resolve against it.
Future<PlanRequestInputs> requestPlanInputs(
  String request,
  String todayIso, {
  PlanRequestPoster? post,
  Future<String?> Function()? currentToken,
  Future<String?> Function()? refreshToken,
  String? baseUrl,
}) async {
  final send = post ?? _defaultPost;
  final body = jsonEncode({'request': request, 'today': todayIso});
  final uri = Uri.parse('${baseUrl ?? _webBase()}/api/coach/plan-request');
  // Production Lambda reads `x-supabase-authorization` only (CloudFront's OAC
  // sigv4-signs `Authorization`), and OAC cannot hash a streamed body, so the
  // client supplies the payload hash or the Function URL 403s (#590).
  final hash = payloadSha256Hex(body);
  Map<String, String> headersFor(String token) => {
        HttpHeaders.contentTypeHeader: 'application/json',
        'x-supabase-authorization': 'Bearer $token',
        'x-amz-content-sha256': hash,
      };

  String? token;
  try {
    token = await (currentToken ?? _currentToken)();
  } catch (e) {
    debugPrint('plan_request_client: session lookup failed: $e');
  }
  if (token == null) {
    throw const PlanRequestError(PlanRequestErrorKind.notAuthenticated);
  }

  PlanRequestHttpResponse res;
  try {
    res = await send(uri, headersFor(token), body);
    if (res.statusCode == 401) {
      try {
        final refreshed = await (refreshToken ?? _refreshToken)();
        if (refreshed != null) {
          res = await send(uri, headersFor(refreshed), body);
        }
      } catch (e) {
        debugPrint('plan_request_client: refreshSession failed: $e');
      }
    }
  } catch (e) {
    debugPrint('plan_request_client: request failed: $e');
    throw const PlanRequestError(PlanRequestErrorKind.unavailable);
  }

  Object? json;
  try {
    json = jsonDecode(res.body);
  } catch (_) {
    json = null;
  }

  if (res.statusCode != 200) {
    final code = json is Map ? json['code'] : null;
    throw PlanRequestError(
        planRequestErrorKind(res.statusCode, code is String ? code : null));
  }

  final inputs = parsePlanRequestInputs(json is Map ? json['inputs'] : null);
  if (inputs == null) {
    throw const PlanRequestError(PlanRequestErrorKind.unavailable);
  }
  return inputs;
}
