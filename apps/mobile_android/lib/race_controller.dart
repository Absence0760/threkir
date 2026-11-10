import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apple_watch_race_bridge.dart';
import 'course_gates.dart' show CourseGate, GateSource, SessionStartMode;
import 'race_finish.dart';
import 'race_start_modes.dart';
import 'rate_limit_errors.dart';
import 'social_service.dart';

/// SharedPreferences key holding the finisher times that haven't reached
/// the server yet, as a JSON list of [PendingRaceResult].
const kPendingRaceResultsKey = 'race_pending_results';

/// Upper bound on the queue. A finisher time is one row per race, so this
/// is generous; the cap only exists so a permanently-failing write can't
/// grow the stored list without limit. Oldest entries drop first.
const kPendingRaceResultsMax = 20;

/// SharedPreferences key holding the last scheduled or self-timed race this
/// account found, with its window and the frozen start line, so the banner
/// and the attempt still work with no signal (#1306 offline).
const kActiveRaceCacheKey = 'race_active_cache';

/// SharedPreferences key holding the frozen course of the race this account
/// last found, so a recording times by the lines with no signal (#1307
/// offline): one entry, keyed to its account and race.
const kRaceCourseCacheKey = 'race_course_cache';

/// SharedPreferences key holding the automatic finishes an undo could not
/// delete with no signal, as `{user_id, event_id, instance_start}` entries.
/// Each is deleted before any result for its race is sent again, so a hand
/// finish after the undo never lands beside, or under the lock rule of, the
/// finish the runner withdrew.
const kPendingRaceVoidsKey = 'race_pending_voids';

/// How long "Not finished? Resume" is offered after a line finish (#1307
/// m11).
const Duration kRaceUndoWindow = Duration(seconds: 60);

/// Fixes a recording keeps from its Start for the detector to replay when
/// the race or its course is known only later: twelve hours at one a second.
/// Past it the oldest go first.
const int kRaceFixLogMax = 43200;

/// How a result's start was detected (`event_results.start_detection`):
/// a start-line crossing or GO itself ([gate]), or the runner's own Start
/// press ([device]).
enum RaceStartDetection {
  gate('gate'),
  device('device');

  const RaceStartDetection(this.wire);
  final String wire;
}

/// The HTTP status PostgREST answers an error [code] with, after its error
/// table (docs.postgrest.org, "Errors"): `supabase_flutter` surfaces the
/// SQLSTATE or `PGRST` code, and only a body it could not parse carries the
/// status itself. Null when the code is unknown or absent.
@visibleForTesting
int? postgrestHttpStatus(String? code) {
  if (code == null) return null;
  if (RegExp(r'^\d{3}$').hasMatch(code)) return int.parse(code);
  if (code.startsWith('PGRST')) return _pgrstStatus[code];
  if (code.length != 5) return null;
  switch (code) {
    case '23503' || '23505':
      return 409;
    case '25006':
      return 405;
    case '42501':
      return 403;
    case '42883' || '42P01':
      return 404;
    case '42P17':
      return 500;
    case 'P0001':
      return 400;
  }
  return switch (code.substring(0, 2)) {
    '08' || '53' => 503,
    '54' => 413,
    '0L' || '0P' || '28' => 403,
    '09' || '25' || '2D' || '38' || '39' || '3B' || '40' || '55' || '57' ||
    '58' || 'F0' || 'HV' || 'P0' || 'XX' =>
      500,
    _ => 400,
  };
}

const Map<String, int> _pgrstStatus = {
  'PGRST000': 503, 'PGRST001': 503, 'PGRST002': 503, 'PGRST003': 504,
  'PGRST100': 400, 'PGRST101': 405, 'PGRST102': 400, 'PGRST103': 416,
  'PGRST105': 405, 'PGRST106': 406, 'PGRST107': 415, 'PGRST108': 400,
  'PGRST111': 500, 'PGRST112': 500, 'PGRST114': 400, 'PGRST115': 400,
  'PGRST116': 406, 'PGRST117': 405, 'PGRST118': 400, 'PGRST120': 400,
  'PGRST121': 500, 'PGRST122': 400, 'PGRST123': 400, 'PGRST124': 400,
  'PGRST125': 404, 'PGRST126': 404, 'PGRST127': 400, 'PGRST128': 400,
  'PGRST200': 400, 'PGRST201': 300, 'PGRST202': 404, 'PGRST203': 300,
  'PGRST204': 400, 'PGRST205': 404,
  'PGRST300': 500, 'PGRST301': 401, 'PGRST302': 401, 'PGRST303': 401,
};

/// Whether a failed finisher-time write is worth replaying. A 400, 403, 404
/// or 422 answers the same way on every retry — a CHECK, the closed result
/// window, RLS, a row that is gone — so replaying it only holds a slot in
/// the capped queue until a real result is pushed out; it is dropped, as
/// Wear's `isRetryableRaceResultFailure` drops it. Everything else is kept:
/// no network, a 5xx, an expired session (401), a code this cannot read,
/// and a rate-limit refusal, which PostgREST also answers 400 but which
/// clears by itself.
bool isRetryableRaceResultFailure(Object e) {
  if (e is! PostgrestException) return true;
  if (parseRateLimitError(code: e.code, message: e.message) != null) {
    return true;
  }
  final status = postgrestHttpStatus(e.code);
  return status == null || !const {400, 403, 404, 422}.contains(status);
}

/// Remove every queued finisher time. Called on sign-out: the queue is the
/// one place a departing account's results would otherwise wait for the
/// next account to sign in. Never throws.
Future<void> clearPendingRaceResults() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPendingRaceResultsKey);
    await prefs.remove(kPendingRaceVoidsKey);
  } catch (e) {
    debugPrint('[clearPendingRaceResults] ${safeErrorLabel(e)}');
  }
}

/// A finisher time that couldn't be submitted when the run finished.
///
/// `submitEventResult` upserts on `(event_id, instance_start, user_id)`, so
/// replaying one is idempotent — a queued result that actually landed on a
/// retry we never saw the response to just rewrites the same row.
class PendingRaceResult {
  const PendingRaceResult({
    required this.userId,
    required this.eventId,
    required this.instanceStart,
    this.runId,
    required this.durationS,
    required this.distanceM,
    this.finisherStatus = 'finished',
    this.courseId,
    this.gunTimeS,
    this.chipTimeS,
    this.finishMethod,
    this.crossings = RaceCrossings.none,
  });

  /// The account the time belongs to. The upsert writes whoever is signed
  /// in, so an entry only ever replays while this account is.
  final String userId;
  final String eventId;
  final DateTime instanceStart;
  /// Null for a finish filed at the line, before the run is saved: Stop
  /// files it again with the run.
  final String? runId;
  final int durationS;
  final double distanceM;
  final String finisherStatus;
  final String? courseId;
  final int? gunTimeS;
  final int? chipTimeS;
  final String? finishMethod;

  /// The crossing instants on the server clock and how each was detected
  /// (#1307). Sent with every replay, null included.
  final RaceCrossings crossings;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user_id': userId,
        'event_id': eventId,
        'instance_start': instanceStartKey(instanceStart),
        if (runId != null) 'run_id': runId,
        'duration_s': durationS,
        'distance_m': distanceM,
        'finisher_status': finisherStatus,
        if (courseId != null) 'course_id': courseId,
        if (gunTimeS != null) 'gun_time_s': gunTimeS,
        if (chipTimeS != null) 'chip_time_s': chipTimeS,
        if (finishMethod != null) 'finish_method': finishMethod,
        ...{
          for (final e in crossings.toRow().entries)
            if (e.value != null) e.key: e.value,
        },
      };

  /// Null for an entry that cannot be replayed safely, including one queued
  /// before entries carried their account: nothing says whose it is, and
  /// replaying it would file it under whoever is signed in now.
  static PendingRaceResult? fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final eventId = json['event_id'];
    final instance = json['instance_start'];
    final runId = json['run_id'];
    final durationS = json['duration_s'];
    final distanceM = json['distance_m'];
    if (userId is! String ||
        userId.isEmpty ||
        eventId is! String ||
        instance is! String ||
        runId is! String? ||
        durationS is! num ||
        distanceM is! num) {
      return null;
    }
    final parsed = parseIsoStrict(instance);
    if (parsed == null) return null;
    // Entries queued before live-race timing carry none of the fields below;
    // they replay exactly as they were queued.
    final status = json['finisher_status'];
    final gun = json['gun_time_s'];
    final chip = json['chip_time_s'];
    return PendingRaceResult(
      userId: userId,
      eventId: eventId,
      instanceStart: parsed,
      runId: runId,
      durationS: durationS.toInt(),
      distanceM: distanceM.toDouble(),
      finisherStatus: status is String ? status : 'finished',
      courseId: json['course_id'] as String?,
      gunTimeS: gun is num ? gun.toInt() : null,
      chipTimeS: chip is num ? chip.toInt() : null,
      finishMethod: json['finish_method'] as String?,
      crossings: RaceCrossings(
        startAt: parseIsoStrictValue(json['start_at']),
        finishAt: parseIsoStrictValue(json['finish_at']),
        startDetection: json['start_detection'] as String?,
        finishDetection: json['finish_detection'] as String?,
        clockOffsetMs: (json['clock_offset_ms'] as num?)?.toInt(),
      ),
    );
  }
}

/// The course a racer is running: what the finish detector and the coverage
/// gate need, resolved once when the recorder attaches. Read off the race's
/// frozen copy of the course (`race_session_courses`, decisions § 2391) when
/// it has one, else the `event_courses` row — never the route.
class RaceCourse {
  const RaceCourse({
    required this.courseId,
    required this.distanceM,
    this.finishLat,
    this.finishLng,
    this.startLat,
    this.startLng,
    this.startGate,
    this.finishGate,
    this.finishLineSelfCross = false,
  });

  /// Null for an event with no `event_courses` rows, raced on the event's
  /// own distance with no finish point.
  final String? courseId;
  final double? distanceM;
  final double? finishLat;
  final double? finishLng;
  final double? startLat;
  final double? startLng;

  /// The course's timing lines: drawn on the race screen's map and handed
  /// to `race_finish v2` (#1307).
  final CourseGate? startGate;
  final CourseGate? finishGate;

  /// The route crosses its own finish line before its end (laps, a track):
  /// the line cannot tell a lap from the finish, so this course finishes by
  /// hand only.
  final bool finishLineSelfCross;

  bool get hasFinish => finishLat != null && finishLng != null;
  bool get hasStart => startLat != null && startLng != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'course_id': courseId,
        'distance_m': distanceM,
        'finish_lat': finishLat,
        'finish_lng': finishLng,
        'start_lat': startLat,
        'start_lng': startLng,
        'start_gate': _gateJson(startGate),
        'finish_gate': _gateJson(finishGate),
        'finish_line_self_cross': finishLineSelfCross,
      };

  /// A cached [toJson]; null when it is not one.
  static RaceCourse? fromJson(Object? j) {
    if (j is! Map) return null;
    double? n(Object? v) => v is num && v.toDouble().isFinite ? v.toDouble() : null;
    final id = j['course_id'];
    return RaceCourse(
      courseId: id is String ? id : null,
      distanceM: n(j['distance_m']),
      finishLat: n(j['finish_lat']),
      finishLng: n(j['finish_lng']),
      startLat: n(j['start_lat']),
      startLng: n(j['start_lng']),
      startGate: _gateFromJson(j['start_gate']),
      finishGate: _gateFromJson(j['finish_gate']),
      finishLineSelfCross: j['finish_line_self_cross'] == true,
    );
  }

  static Map<String, dynamic>? _gateJson(CourseGate? g) => g == null
      ? null
      : <String, dynamic>{
          'lat': g.lat,
          'lng': g.lng,
          'bearing_deg': g.bearingDeg,
          'half_width_m': g.halfWidthM,
          'source': g.source.name,
        };

  static CourseGate? _gateFromJson(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'];
    final lng = j['lng'];
    final bearing = j['bearing_deg'];
    final half = j['half_width_m'];
    if (lat is! num || lng is! num || bearing is! num || half is! num) {
      return null;
    }
    return CourseGate(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      bearingDeg: bearing.toDouble(),
      halfWidthM: half.toDouble(),
      source: j['source'] == GateSource.organiser.name
          ? GateSource.organiser
          : GateSource.derived,
    );
  }
}

/// Which of an event's [courses] a racer runs: the one they picked at RSVP,
/// else the only one. Null when there are several and none was picked — the
/// race still records and can be finished by hand, but nothing is assumed.
EventCourseView? pickRaceCourse(
    List<EventCourseView> courses, String? myCourseId) {
  if (myCourseId != null) {
    for (final c in courses) {
      if (c.id == myCourseId) return c;
    }
  }
  return courses.length == 1 ? courses.single : null;
}

/// Tracks live race sessions for events the user has RSVP'd to and is
/// therefore likely participating in. When the organiser arms a race, the
/// run screen surfaces a "Race armed — waiting for GO" banner. Once the
/// session is `running`, a recording joins it ([attachIfRaceRunning]) —
/// one started after GO at Start, one started while the race was armed at
/// GO — and pushes pings until it stops.
///
/// This is deliberately a lightweight notifier rather than a full state
/// machine — the existing `RunRecorder` state machine in run_screen is
/// complex enough already. Nothing starts a recording on the remote
/// signal: the runner taps Start (the recorder already handles permissions
/// + countdown correctly); auto-start is a follow-up that needs
/// permission-flow plumbing.
class ActiveRace {
  final String eventId;
  final DateTime instanceStart;
  final String status; // armed | running | finished | cancelled (stored)
  final DateTime? startedAt;
  final String? eventTitle;

  /// How the race starts (#1306) and its instants on the server clock.
  final SessionStartMode startMode;
  final DateTime? scheduledStartAt;
  final DateTime? windowOpensAt;
  final DateTime? windowClosesAt;

  /// The course on this runner's RSVP; null for a single-course race.
  final String? courseId;

  /// A self-timed race's frozen start line centre, for the distance to it.
  final double? startLineLat;
  final double? startLineLng;

  const ActiveRace({
    required this.eventId,
    required this.instanceStart,
    required this.status,
    required this.startedAt,
    required this.eventTitle,
    this.startMode = SessionStartMode.hostGo,
    this.scheduledStartAt,
    this.windowOpensAt,
    this.windowClosesAt,
    this.courseId,
    this.startLineLat,
    this.startLineLng,
  });

  StartModeSession get _session => StartModeSession(
        status: raceStatusFromWire(status) ?? RaceStatus.armed,
        startMode: startMode,
        scheduledStartAt: scheduledStartAt,
        windowOpensAt: windowOpensAt,
        windowClosesAt: windowClosesAt,
      );

  /// The status on the server clock at [serverNow]: a scheduled race whose
  /// GO has passed is running before the per-minute job moves it.
  RaceStatus statusAt(DateTime serverNow) =>
      effectiveRaceStatus(_session, serverNow);

  /// When the clock starts: the scheduled GO or the window's opening.
  DateTime? get startInstant => raceStartInstant(_session);

  /// GO as the server stamps it; for a scheduled or self-timed race that is
  /// the instant itself, known before the stored row says running.
  DateTime? get goAt => startedAt ?? startInstant;

  bool get isSelfTimed => startMode == SessionStartMode.selfTimed;

  /// A status the client does not know reads as neither armed nor running.
  bool get isArmed =>
      raceStatusFromWire(status) != null &&
      statusAt(DateTime.now().toUtc()) == RaceStatus.armed;
  bool get isRunning =>
      raceStatusFromWire(status) != null &&
      statusAt(DateTime.now().toUtc()) == RaceStatus.running;

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'instance_start': instanceStartKey(instanceStart),
        'status': status,
        'started_at': startedAt?.toUtc().toIso8601String(),
        'event_title': eventTitle,
        'start_mode': switch (startMode) {
          SessionStartMode.scheduled => 'scheduled',
          SessionStartMode.selfTimed => 'self_timed',
          SessionStartMode.hostGo => 'host_go',
        },
        'scheduled_start_at': scheduledStartAt?.toUtc().toIso8601String(),
        'window_opens_at': windowOpensAt?.toUtc().toIso8601String(),
        'window_closes_at': windowClosesAt?.toUtc().toIso8601String(),
        'course_id': courseId,
        'start_line_lat': startLineLat,
        'start_line_lng': startLineLng,
      };

  /// A row of `my_race_sessions()` or a cached [toJson]; null when the keys
  /// it cannot do without are missing or malformed.
  static ActiveRace? fromJson(Map<String, dynamic> j) {
    final eventId = j['event_id'];
    final inst = parseIsoStrictValue(j['instance_start']);
    final status = j['status'];
    if (eventId is! String || inst == null || status is! String) return null;
    double? num_(Object? v) => v is num ? v.toDouble() : null;
    return ActiveRace(
      eventId: eventId,
      instanceStart: inst,
      status: status,
      startedAt: parseIsoStrictValue(j['started_at']),
      eventTitle: j['event_title'] as String?,
      startMode: sessionStartModeFromWire(j['start_mode'] as String?),
      scheduledStartAt: parseIsoStrictValue(j['scheduled_start_at']),
      windowOpensAt: parseIsoStrictValue(j['window_opens_at']),
      windowClosesAt: parseIsoStrictValue(j['window_closes_at']),
      courseId: j['course_id'] as String?,
      startLineLat: num_(j['start_line_lat']),
      startLineLng: num_(j['start_line_lng']),
    );
  }

  ActiveRace withStartLine(double? lat, double? lng) => ActiveRace(
        eventId: eventId,
        instanceStart: instanceStart,
        status: status,
        startedAt: startedAt,
        eventTitle: eventTitle,
        startMode: startMode,
        scheduledStartAt: scheduledStartAt,
        windowOpensAt: windowOpensAt,
        windowClosesAt: windowClosesAt,
        courseId: courseId,
        startLineLat: lat,
        startLineLng: lng,
      );
}

/// One `race_pings` row, built in one place.
///
/// Both senders reach it — the phone's own recorder through [
/// RaceController.pushPing], and the Apple Watch's relay through
/// [RaceController.ingestWatchPing] — so the spectator map cannot be handed
/// two differently-shaped dots depending on which device the runner wore.
Map<String, dynamic> racePingRow({
  required String eventId,
  required DateTime instance,
  required String? userId,
  required double lat,
  required double lng,
  double? distanceM,
  int? elapsedS,
  int? bpm,
}) =>
    <String, dynamic>{
      'event_id': eventId,
      'instance_start': instanceStartKey(instance),
      'user_id': userId,
      'lat': lat,
      'lng': lng,
      if (distanceM != null) 'distance_m': distanceM,
      if (elapsedS != null) 'elapsed_s': elapsedS,
      if (bpm != null) 'bpm': bpm,
    };

class RaceController extends ChangeNotifier {
  RaceController(this._social);

  final SocialService _social;
  SupabaseClient get _c {
    if (!ApiClient.isInitialized) {
      throw StateError(
        'RaceController called before Supabase.initialize() resolved.',
      );
    }
    return Supabase.instance.client;
  }

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  Timer? _pingTimer;

  ActiveRace? _active;
  ActiveRace? get active => _active;

  /// Set by the run screen while a run that's been stamped with a race
  /// is in progress. The controller polls for the session's status
  /// changing to `finished/cancelled` and posts pings until then.
  String? _hostingEventId;
  DateTime? _hostingInstance;

  /// Who was signed in when the recording attached: the account its result
  /// belongs to, whoever is signed in by the time it is filed.
  String? _hostingUserId;

  /// GO, on the server clock. Null until the session row says so.
  DateTime? _gunAt;
  DateTime? _recordingStartedAt;
  RaceCourse? _course;
  RaceFinishDetector? _detector;
  RaceOutcome? _outcome;
  bool _raceEnded = false;
  bool _lateStart = false;
  bool _firstFixSeen = false;
  double? _firstFixLat;
  double? _firstFixLng;

  /// Device-to-server clock offset, sampled off every ping's server-stamped
  /// `at` (decisions § 1843).
  final ServerClockOffset clockOffset = ServerClockOffset();

  // ── Detection from the recording's Start (#1307 M1) ──────────────────────
  //
  // Every fresh fix of a recording is logged from its Start, bound to a race
  // or not, and the detector is (re)built over the log whenever the race and
  // its course are both known: a self-timed attempt as soon as it is armed,
  // a gun race once GO is. So a crossing in the seconds before the phone
  // hears GO, or before the course loads, is kept and resolved against GO
  // rather than lost.

  /// A recording is running on this device.
  bool _recording = false;
  final List<RaceFix> _fixLog = [];

  /// Log length when the recording attached: a v1 detector (no lines) with
  /// no GO on record only ever saw fixes after the attach, and still does.
  int _attachLogIndex = 0;

  /// `eventId|instance` of the race the detector and [_course] belong to.
  String? _detKey;

  /// The finish behind an automatic [_outcome], for its detection and start.
  RaceFinish? _finish;

  /// An automatic finish found while replaying the log rather than on a live
  /// fix; the run screen collects it with [takePendingFinish].
  RaceFinish? _pendingFinish;

  /// The runner said "Not finished? Resume": this recording finishes by hand.
  bool _autoFinishVoided = false;

  /// The start the voided finish was measured from: the hand finish after an
  /// undo is still timed from the start line, not the Start press.
  RaceStart? _keptStart;

  /// The outcome already filed by [fileOutcomeNow], so Stop does not file it
  /// twice, and the write in flight that a void must wait for.
  RaceOutcome? _filedOutcome;
  Future<void>? _filing;

  bool _startCued = false;

  /// Metres from the runner to the centre of the start line, until a start
  /// is committed; null without a course start line or a fix.
  final ValueNotifier<double?> distanceToStartM = ValueNotifier<double?>(null);

  /// Called once per recording when a start-line crossing commits the start.
  /// The run screen cues it; a failure there is the screen's to contain.
  void Function()? onStartLineCrossed;

  /// The course of each race seen this session, keyed like [_detKey].
  final Map<String, RaceCourse> _courseCache = {};
  final Set<String> _coursePrefetched = {};

  /// Whether a recorder is attached to a running race.
  bool get isHosting => _hostingEventId != null;

  /// The host ended the race before this runner finished. The server marks
  /// the runner DNF; nothing is submitted from here.
  bool get raceEnded => _raceEnded;

  /// The recording started more than five minutes after GO, or its first
  /// fix was more than 200 m from the course's start point — measured only
  /// when the course row carries one, never against the route (decisions
  /// § 1845). Surfaced on the run screen; not yet carried on the result
  /// (decisions § 1843).
  bool get lateStart => _lateStart;

  RaceCourse? get course => _course;
  RaceOutcome? get outcome => _outcome;

  /// The finish behind the current automatic outcome; null otherwise.
  RaceFinish? get autoFinish => _finish;

  /// Whether a recording on this device is feeding the detector: from
  /// [beginRecording] (or an attach) until it is detached.
  bool get followsRecording => _recording;

  /// Whether this recording has a detector timing it right now.
  bool get detecting => _detector != null;

  /// A finish the detector found while replaying fixes (at GO, or when the
  /// course arrived), once; null when there is none to collect.
  RaceFinish? takePendingFinish() {
    final f = _pendingFinish;
    _pendingFinish = null;
    return f;
  }

  /// Stop while racing is a pause until the runner says otherwise: true when
  /// a hosted race has no outcome yet, was not ended by the host, and the
  /// runner is not mid-approach at the finish (a stop there IS the finish).
  bool get stopNeedsRaceChoice =>
      isHosting &&
      _outcome == null &&
      !_raceEnded &&
      _detector?.candidate == null;

  /// Whether [coveredM] clears the 90% gate on this racer's course.
  bool coverageMet(double coveredM) =>
      raceCoverageMet(coveredM, _course?.distanceM);

  /// Gun time to [finishAtDevice], or null with no GO on record.
  int? gunTimeTo(DateTime finishAtDevice) {
    final gun = _gunAt;
    if (gun == null) return null;
    return raceGunTimeS(
      finishAtDevice: finishAtDevice,
      gunAt: gun,
      clockOffset: clockOffset.offset,
    );
  }

  /// Attach the controller to a user session. Starts polling for armed
  /// sessions on events the user has RSVP'd to. Idempotent.
  Future<void> start() async {
    if (_pollTimer != null) return;
    _attachWatchRelays();
    await _refresh();
    // Realtime on race_sessions handles the live case (any change fires
    // a refresh). The 60 s timer is a watchdog for when the channel
    // silently disconnects — short enough to recover quickly, long
    // enough not to duplicate the realtime path. Was 15 s; that did 4×
    // the round-trips for no functional gain.
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
    // Realtime on race_sessions — the server-published filter scopes to
    // all rows; we narrow in-client against the user's RSVPed events
    // because Postgres-level filtering by a join is awkward. For a v1
    // this is fine: a user is in at most a handful of upcoming races.
    _channel = _c
        .channel('race-controller-${_c.auth.currentUser?.id ?? 'anon'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'race_sessions',
          callback: (_) => _refresh(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_watchRelaysAttached) {
      AppleWatchRaceBridge.detach();
      _watchRelaysAttached = false;
    }
    _pollTimer?.cancel();
    _pingTimer?.cancel();
    _transitionTimer?.cancel();
    distanceToStartM.dispose();
    final ch = _channel;
    if (ch != null) _c.removeChannel(ch);
    super.dispose();
  }

  /// One discovery pass, for tests that drive [activeRaceLoader].
  @visibleForTesting
  Future<void> refreshForTest() => _refresh();

  Future<void> _refresh() async {
    final uid = _signedInUserId;
    if (uid == null) {
      if (_active != null) {
        _active = null;
        notifyListeners();
      }
      return;
    }
    await drainPendingResults();
    final hostEid = _hostingEventId;
    final hostInst = _hostingInstance;
    if (hostEid != null && hostInst != null) {
      // Read the hosted session directly: the RSVP window below can age out
      // of a long race, and a race that left it must not read as ended.
      final s = await _social.fetchRaceSession(hostEid, hostInst);
      if (s != null) observeHostedSession(s.status, s.startedAt);
    }
    // One call finds every race this runner is going to that is armed or
    // live by the server clock, in any start mode, and creates the sessions
    // of their scheduled and self-timed occurrences that are due: discovery
    // goes by the window, not by how far the occurrence's start is from now
    // (#1306 B4). Its server clock samples the countdown's offset (m3).
    try {
      final loader = activeRaceLoader ?? _loadActiveRaces;
      final rows = await loader();
      ActiveRace? next;
      for (final r in rows) {
        if (next == null || (r.isRunning && !next.isRunning)) next = r;
      }
      if (next != null && next.isSelfTimed) {
        next = await _withStartLine(next);
      }
      _setActive(next);
      unawaited(_writeActiveCache(next));
      if (next != null) unawaited(_prefetchCourse(next));
    } catch (e) {
      debugPrint('[RaceController._refresh] ${safeErrorLabel(e)}');
      // Offline: a self-timed or scheduled race found earlier still stands
      // while its window has not closed on this device's clock.
      final cached = await _readActiveCache();
      if (cached != null && cached.statusAt(clockOffset.toServer(DateTime.now()).toUtc()) != RaceStatus.finished) {
        _setActive(cached);
      }
    }
  }

  /// The discovery read, as a seam: the default reaches Supabase, which no
  /// host test can initialize.
  @visibleForTesting
  Future<List<ActiveRace>> Function()? activeRaceLoader;

  Future<List<ActiveRace>> _loadActiveRaces() async {
    final sentAt = DateTime.now();
    final raw = await _c.rpc('my_race_sessions');
    final receivedAt = DateTime.now();
    final out = <ActiveRace>[];
    for (final row in (raw as List).cast<Map<String, dynamic>>()) {
      final serverNow = parseIsoStrictValue(row['server_now']);
      if (serverNow != null) {
        clockOffset.addSample(
            sentAt: sentAt, receivedAt: receivedAt, serverAt: serverNow);
      }
      final race = ActiveRace.fromJson(row);
      if (race != null) out.add(race);
    }
    return out;
  }

  /// A self-timed race's frozen start line, for the banner's distance to it.
  /// L4: a failed read keeps the race without one (the attempt still works).
  Future<ActiveRace> _withStartLine(ActiveRace race) async {
    final cur = _active;
    if (cur != null &&
        cur.eventId == race.eventId &&
        cur.instanceStart.isAtSameMomentAs(race.instanceStart) &&
        cur.startLineLat != null) {
      return race.withStartLine(cur.startLineLat, cur.startLineLng);
    }
    try {
      final loader = courseLoader ?? _loadCourse;
      final course = await loader(race.eventId, race.instanceStart);
      final gate = course?.startGate;
      if (gate != null) return race.withStartLine(gate.lat, gate.lng);
    } catch (e) {
      debugPrint('[RaceController._withStartLine] ${safeErrorLabel(e)}');
    }
    return race;
  }

  Future<void> _writeActiveCache(ActiveRace? race) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (race == null || race.startMode == SessionStartMode.hostGo) {
        await prefs.remove(kActiveRaceCacheKey);
        return;
      }
      await prefs.setString(kActiveRaceCacheKey, jsonEncode({
        'user_id': _signedInUserId,
        ...race.toJson(),
      }));
    } catch (e) {
      debugPrint('[RaceController._writeActiveCache] $e');
    }
  }

  Future<ActiveRace?> _readActiveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kActiveRaceCacheKey);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      if (j['user_id'] != _signedInUserId) return null;
      return ActiveRace.fromJson(j);
    } catch (e) {
      debugPrint('[RaceController._readActiveCache] $e');
      return null;
    }
  }

  /// Fires a listener notification at the active race's start instant and at
  /// its window close, so the banner turns live and a recording waiting on
  /// GO joins it without waiting for the next poll (no cron lag on the
  /// phone either).
  Timer? _transitionTimer;

  void _scheduleTransition(ActiveRace? race) {
    _transitionTimer?.cancel();
    _transitionTimer = null;
    if (race == null || race.startMode == SessionStartMode.hostGo) return;
    final serverNow = clockOffset.toServer(DateTime.now());
    final targets = [race.startInstant, race.windowClosesAt]
        .whereType<DateTime>()
        .where((t) => t.isAfter(serverNow))
        .toList()
      ..sort();
    if (targets.isEmpty) return;
    final wait = targets.first.difference(serverNow) +
        const Duration(milliseconds: 250);
    _transitionTimer = Timer(wait, () {
      notifyListeners();
      _scheduleTransition(_active);
    });
  }

  /// A Self-timed race binds a recording only after the runner says so
  /// (#1306 owner decision 4a): "This run is my attempt". Other runs in the
  /// window never bind or ping.
  bool _attemptArmed = false;
  bool get attemptArmed => _attemptArmed;

  void armAttempt() {
    final race = _active;
    if (race == null || !race.isSelfTimed || _attemptArmed) return;
    _attemptArmed = true;
    _detectionChanged();
    notifyListeners();
  }

  void cancelAttempt() {
    if (!_attemptArmed) return;
    _attemptArmed = false;
    _detectionChanged();
    notifyListeners();
  }

  /// Visible-for-testing — RaceControllerTest exercises the change-
  /// detection directly without a live Supabase. Keeps the test
  /// honest about which fields are part of an ActiveRace's
  /// observed-by-listeners identity.
  @visibleForTesting
  void setActiveForTest(ActiveRace? next) => _setActive(next);

  void _setActive(ActiveRace? next) {
    // instanceStart is part of an ActiveRace's identity — Instance 1
    // of recurring event E is a DIFFERENT race from Instance 2 of E
    // (different start time, different RSVP row, different
    // race_sessions PK). Omitting it from change-detection let a
    // back-to-back armed transition (Instance 1 finishes → Instance
    // 2 armed; same eventId, same 'armed' status, both null
    // startedAt) silently update `_active` without firing
    // notifyListeners, leaving the banner rendering Instance 1's
    // time until something else triggered a rebuild.
    final sameRace = next?.eventId == _active?.eventId &&
        next?.instanceStart == _active?.instanceStart;
    final changed = !sameRace ||
        next?.status != _active?.status ||
        next?.startedAt != _active?.startedAt ||
        next?.startMode != _active?.startMode ||
        next?.scheduledStartAt != _active?.scheduledStartAt ||
        next?.windowOpensAt != _active?.windowOpensAt ||
        next?.windowClosesAt != _active?.windowClosesAt ||
        next?.startLineLat != _active?.startLineLat;
    if (!sameRace) _attemptArmed = false;
    // The paired Apple Watch is TOLD Arm / Go / End; it cannot poll
    // `race_sessions` itself, because the Supabase surface does not grow on
    // that wrist (decisions § 1712). Computed before `_active` moves, and off
    // `_active` rather than off `_hostingEventId` — that field is null on the
    // participant path, and a relay keyed on it would never fire at all.
    final pushes = appleWatchRacePushes(
      previous: _watchRace(_active),
      next: _watchRace(next),
    );
    _active = next;
    _scheduleTransition(next);
    _detectionChanged();
    if (changed) notifyListeners();
    // L4, and last: a watch on a charger in another room must not be able to
    // hold up the poll that found this transition, let alone fail it.
    for (final push in pushes) {
      unawaited(AppleWatchRaceBridge.relay(push));
    }
  }

  WatchRace? _watchRace(ActiveRace? race) => race == null
      ? null
      : WatchRace(
          eventId: race.eventId,
          instanceStart: instanceStartKey(race.instanceStart),
          status: race.status,
          eventTitle: race.eventTitle,
        );

  bool _watchRelaysAttached = false;

  void _attachWatchRelays() {
    AppleWatchRaceBridge.attach(
      onPing: (ping) => unawaited(ingestWatchPing(ping)),
      onResult: ingestWatchResult,
    );
    _watchRelaysAttached = true;
  }

  /// Write a fix the Apple Watch relayed off the wrist.
  ///
  /// Keyed on the payload's own `(event_id, instance_start)`, never on
  /// `_hostingEventId` — the phone is not the recorder here, so that field is
  /// null and a relay that read it would silently never write a row.
  ///
  /// DROPPED on failure, deliberately: the watch already declined to queue
  /// this durably for the same reason (a position an hour stale is a lie
  /// about where the runner is), and a phone-side retry would deliver exactly
  /// the stale dot the watch refused to send.
  Future<void> ingestWatchPing(WatchRacePing ping) async {
    try {
      await _insertPing(racePingRow(
        eventId: ping.eventId,
        instance: ping.instanceStart,
        userId: _currentUserId,
        lat: ping.lat,
        lng: ping.lng,
        distanceM: ping.distanceM,
        elapsedS: ping.elapsedS,
        bpm: ping.bpm,
      ));
    } catch (e) {
      debugPrint('[RaceController.ingestWatchPing] $e');
    }
  }

  /// Write a finisher time the Apple Watch relayed off the wrist.
  ///
  /// The opposite trade to a ping, mirroring the watch's own: this is the one
  /// value in the feature nobody can re-derive, so a failed write goes to the
  /// same on-disk queue [submitResult] uses and is replayed by
  /// [drainPendingResults]. Returns whether the time is accounted for — the
  /// native side re-delivers anything this says it is not. A time the
  /// server refuses outright is accounted for by being dropped: redelivering
  /// it would be refused the same way.
  Future<bool> ingestWatchResult(WatchRaceResult result) async {
    try {
      await _social.submitEventResult(
        eventId: result.eventId,
        instance: result.instanceStart,
        durationS: result.durationS,
        distanceM: result.distanceM,
        runId: result.runId,
        finisherStatus: 'finished',
      );
      return true;
    } catch (e) {
      debugPrint('[RaceController.ingestWatchResult] ${safeErrorLabel(e)}');
      if (!isRetryableRaceResultFailure(e)) return true;
    }
    final uid = _signedInUserId;
    if (uid == null) return false;
    return _queuePendingResult(PendingRaceResult(
      userId: uid,
      eventId: result.eventId,
      instanceStart: result.instanceStart,
      runId: result.runId,
      durationS: result.durationS,
      distanceM: result.distanceM,
    ));
  }

  /// Join a recording in progress to the user's race if that race is
  /// running: at Start, and again on every race change, so a recording
  /// started while the race was armed joins at GO, as Wear's `raceToBind`
  /// does. A recording already attached is never re-attached, including one
  /// whose race the host has since ended — it stays attached, ended, until
  /// it stops. [recordingStartedAt] is the recording's Start on the device
  /// clock. Returns whether it attached.
  bool attachIfRaceRunning({required DateTime recordingStartedAt}) {
    if (isHosting) return false;
    final race = _active;
    if (race == null || !race.isRunning) return false;
    if (race.isSelfTimed && !_attemptArmed) return false;
    attachRecorder(
      eventId: race.eventId,
      instance: race.instanceStart,
      startedAt: race.goAt,
      recordingStartedAt: recordingStartedAt,
    );
    return true;
  }

  /// Attach a recording to a running race. Enables live pings at a 10s
  /// cadence and resolves the racer's course for finish detection.
  /// [startedAt] is the session's GO; [recordingStartedAt] is when this
  /// recording began (device clock), which may be before GO.
  void attachRecorder({
    required String eventId,
    required DateTime instance,
    DateTime? startedAt,
    DateTime? recordingStartedAt,
  }) {
    final key = _raceKey(eventId, instance);
    // The same race the recording was already timing before it bound keeps
    // its course, detector and any outcome; anything else starts clean.
    if (_detKey != key) _resetDetection();
    _recording = true;
    _hostingEventId = eventId;
    _hostingInstance = instance;
    _hostingUserId = _signedInUserId;
    _gunAt = startedAt;
    _recordingStartedAt = recordingStartedAt ?? _recordingStartedAt;
    _attachLogIndex = _fixLog.length;
    _raceEnded = false;
    _lateStart = false;
    _firstFixSeen = false;
    _firstFixLat = null;
    _firstFixLng = null;
    unawaited(_resolveCourse(++_attachGeneration, eventId, instance));
    _syncDetector();
  }

  /// A recording started on this device at [startedAt] (device clock). From
  /// here every fix offered is kept for the detector, whether or not the
  /// recording has joined a race yet (#1307 M1).
  void beginRecording({required DateTime startedAt}) {
    if (isHosting) return;
    _resetDetection();
    _fixLog.clear();
    _attachLogIndex = 0;
    _recording = true;
    _recordingStartedAt = startedAt;
    _detectionChanged();
  }

  void detachRecorder() {
    _attachGeneration++;
    _hostingEventId = null;
    _hostingInstance = null;
    _hostingUserId = null;
    _gunAt = null;
    _recordingStartedAt = null;
    _recording = false;
    _fixLog.clear();
    _attachLogIndex = 0;
    _resetDetection();
    _raceEnded = false;
    _lateStart = false;
    _firstFixSeen = false;
    _firstFixLat = null;
    _firstFixLng = null;
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _resetDetection() {
    _detKey = null;
    _course = null;
    _detector = null;
    _outcome = null;
    _finish = null;
    _pendingFinish = null;
    _autoFinishVoided = false;
    _keptStart = null;
    _filedOutcome = null;
    _filing = null;
    _startCued = false;
    distanceToStartM.value = null;
  }

  static String _raceKey(String eventId, DateTime instance) =>
      '$eventId|${instanceStartKey(instance)}';

  /// The race this recording is timed for right now: the one it is bound to,
  /// else the runner's armed or live race while a recording runs (a
  /// self-timed one only once "This run is my attempt" is on).
  ({String eventId, DateTime instance, bool selfTimed, DateTime? goAt})?
      _detectionRace() {
    final eid = _hostingEventId;
    final inst = _hostingInstance;
    final a = _active;
    if (eid != null && inst != null) {
      final same = a != null &&
          a.eventId == eid &&
          a.instanceStart.isAtSameMomentAs(inst);
      return (
        eventId: eid,
        instance: inst,
        selfTimed: same && a.isSelfTimed,
        goAt: _gunAt,
      );
    }
    if (!_recording || a == null) return null;
    if (!a.isArmed && !a.isRunning) return null;
    if (a.isSelfTimed && !_attemptArmed) return null;
    return (
      eventId: a.eventId,
      instance: a.instanceStart,
      selfTimed: a.isSelfTimed,
      goAt: a.isRunning ? a.goAt : null,
    );
  }

  /// The race, its course or GO moved: bring the detector up to date, and
  /// find the course if it is not in hand. Never throws (L4).
  void _detectionChanged() {
    try {
      _syncDetector();
      final r = _detectionRace();
      if (r != null && _course == null && !isHosting) {
        unawaited(_loadDetectionCourse(r.eventId, r.instance));
      }
    } catch (e) {
      debugPrint('[RaceController._detectionChanged] ${safeErrorLabel(e)}');
    }
  }

  void _syncDetector() {
    final r = _detectionRace();
    if (r == null) {
      if (!isHosting && _detKey != null) _resetDetection();
      return;
    }
    final key = _raceKey(r.eventId, r.instance);
    if (_detKey != key) {
      _resetDetection();
      _detKey = key;
      _course = _courseCache[key];
    }
    final course = _course;
    if (course == null || _autoFinishVoided || _outcome != null) return;
    final goDevice = r.goAt?.subtract(clockOffset.offset);
    final d = _detector;
    if (d == null) {
      // A gun race waits for GO; a recording already bound (whose GO may
      // never have been on record) times as it always did.
      if (!r.selfTimed && goDevice == null && !isHosting) return;
      final built = _buildDetector(course, r.selfTimed, goDevice);
      if (built == null) return;
      _detector = built;
      _replayLog(goDevice);
    } else if (!r.selfTimed && goDevice != null) {
      final f = d.setGo(goDevice);
      if (f != null) _onDetectedFinish(f, live: false);
      _checkStartCue();
    }
  }

  /// `race_finish v2` over this course, or null when it cannot finish
  /// itself: no distance, no finish, or a finish line the route crosses
  /// before its end, which finishes by hand only.
  RaceFinishDetector? _buildDetector(
      RaceCourse course, bool selfTimed, DateTime? goDevice) {
    if (course.finishLineSelfCross) return null;
    final distance = course.distanceM;
    if (distance == null || !distance.isFinite || distance <= 0) return null;
    final lat = course.finishLat ?? course.finishGate?.lat;
    final lng = course.finishLng ?? course.finishGate?.lng;
    if (lat == null || lng == null) return null;
    return RaceFinishDetector(
      finishLat: lat,
      finishLng: lng,
      courseDistanceM: distance,
      startGate: course.startGate,
      finishGate: course.finishGate,
      mode: selfTimed ? RaceStartMode.selfTimed : RaceStartMode.gun,
      goAt: selfTimed ? null : goDevice,
    );
  }

  static bool _isV1(RaceFinishDetector d) =>
      d.mode == RaceStartMode.gun && d.startGate == null && d.finishGate == null;

  /// Whether a v1 detector (no lines) may see [fix]: v1 holds nothing until
  /// GO, so it is shown only fixes from GO on, or, with no GO on record,
  /// only those after the recording attached, as before #1307.
  bool _v1Sees(RaceFix fix, int index, DateTime? goDevice) => goDevice != null
      ? !fix.at.isBefore(goDevice)
      : index >= _attachLogIndex;

  void _replayLog(DateTime? goDevice) {
    final d = _detector;
    if (d == null) return;
    final v1 = _isV1(d);
    for (var i = 0; i < _fixLog.length; i++) {
      final fix = _fixLog[i];
      if (v1 && !_v1Sees(fix, i, goDevice)) continue;
      final f = d.offer(fix);
      if (f != null) {
        _onDetectedFinish(f, live: false);
        break;
      }
    }
    _checkStartCue();
  }

  RaceFinish _onDetectedFinish(RaceFinish finish, {required bool live}) {
    _outcome = RaceOutcome(
      finisherStatus: 'finished',
      method: RaceFinishMethod.auto,
      finishAt: finish.at,
    );
    _finish = finish;
    if (!live) _pendingFinish = finish;
    distanceToStartM.value = null;
    notifyListeners();
    return finish;
  }

  void _checkStartCue() {
    final start = _detector?.start;
    if (start == null) return;
    distanceToStartM.value = null;
    if (_startCued || start.kind != RaceStartKind.line) return;
    _startCued = true;
    try {
      onStartLineCrossed?.call();
    } catch (e) {
      debugPrint('[RaceController.onStartLineCrossed] ${safeErrorLabel(e)}');
    }
  }

  void _updateDistanceToStart(double lat, double lng) {
    final gate = _course?.startGate;
    if (gate == null || _detector?.start != null || _outcome != null) {
      if (distanceToStartM.value != null) distanceToStartM.value = null;
      return;
    }
    distanceToStartM.value = raceDistanceM(lat, lng, gate.lat, gate.lng);
  }

  /// The course lookup, as a seam: the default reaches Supabase, which no
  /// host test can initialize.
  @visibleForTesting
  Future<RaceCourse?> Function(String eventId, DateTime instance)? courseLoader;

  /// Bumped by every attach and detach, so a course load that outlives the
  /// recording it was started for — a detach, or a re-attach to the same
  /// race — lands on nothing.
  int _attachGeneration = 0;

  /// L4: a course that cannot be resolved leaves the race recording with no
  /// auto-finish and an ungated manual finish, never a broken recording.
  /// With no signal the course comes off the device's cache (#1307
  /// offline): detection never needs the network once the race was seen.
  Future<void> _resolveCourse(
      int generation, String eventId, DateTime instance) async {
    final key = _raceKey(eventId, instance);
    RaceCourse? course;
    try {
      final loader = courseLoader ?? _loadCourse;
      course = await loader(eventId, instance);
      if (course != null) unawaited(_cacheCourse(key, course));
    } catch (e) {
      debugPrint('[RaceController._resolveCourse] ${safeErrorLabel(e)}');
      course = _courseCache[key] ?? await _readCachedCourse(key);
    }
    if (generation != _attachGeneration) return;
    if (course == null && _course != null) return;
    setCourse(course);
  }

  /// Install the racer's course and time the recording by it, replaying the
  /// fixes so far. Public for the run-screen tests, which drive a race
  /// without a network.
  @visibleForTesting
  void setCourse(RaceCourse? course) {
    final key = _detKey;
    _course = course;
    if (course != null && key != null) _courseCache[key] = course;
    if (_outcome == null) _detector = null;
    _syncDetector();
    _evaluateLateStart();
  }

  /// The course of the race a recording not yet bound is going to time, off
  /// the memory cache, the device cache or the network, in that order.
  Future<void> _loadDetectionCourse(String eventId, DateTime instance) async {
    final key = _raceKey(eventId, instance);
    if (!_courseLoads.add(key)) return;
    try {
      await _loadDetectionCourseOnce(key, eventId, instance);
    } finally {
      _courseLoads.remove(key);
    }
  }

  final Set<String> _courseLoads = {};

  Future<void> _loadDetectionCourseOnce(
      String key, String eventId, DateTime instance) async {
    var course = _courseCache[key] ?? await _readCachedCourse(key);
    if (course == null) {
      try {
        final loader = courseLoader ?? _loadCourse;
        course = await loader(eventId, instance);
        if (course != null) unawaited(_cacheCourse(key, course));
      } catch (e) {
        debugPrint('[RaceController._loadDetectionCourse] ${safeErrorLabel(e)}');
      }
    }
    if (course == null || _detKey != key || _course != null) return;
    setCourse(course);
  }

  /// The race this runner is going to was found: keep its frozen course on
  /// the device, once per race per session, so a recording times by it with
  /// no signal later. L4.
  Future<void> _prefetchCourse(ActiveRace race) async {
    final key = _raceKey(race.eventId, race.instanceStart);
    if (!_coursePrefetched.add(key)) return;
    try {
      final loader = courseLoader ?? _loadCourse;
      final course = await loader(race.eventId, race.instanceStart);
      if (course == null) return;
      await _cacheCourse(key, course);
      if (_detKey == key && _course == null) setCourse(course);
    } catch (e) {
      _coursePrefetched.remove(key);
      debugPrint('[RaceController._prefetchCourse] ${safeErrorLabel(e)}');
    }
  }

  Future<void> _cacheCourse(String key, RaceCourse course) async {
    _courseCache[key] = course;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kRaceCourseCacheKey, jsonEncode({
        'user_id': _signedInUserId,
        'race': key,
        'course': course.toJson(),
      }));
    } catch (e) {
      debugPrint('[RaceController._cacheCourse] $e');
    }
  }

  Future<RaceCourse?> _readCachedCourse(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kRaceCourseCacheKey);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map || j['user_id'] != _signedInUserId || j['race'] != key) {
        return null;
      }
      final course = RaceCourse.fromJson(j['course']);
      if (course != null) _courseCache[key] = course;
      return course;
    } catch (e) {
      debugPrint('[RaceController._readCachedCourse] $e');
      return null;
    }
  }

  /// The finish point comes off the course row, never the route: a
  /// non-owner is served the route privacy-clipped (moving the line) and a
  /// private route not at all. A course with no finish point, or an event
  /// with no courses, races with a manual finish only. A failed read throws
  /// rather than reading as "no courses": the event's own distance is not
  /// this racer's course, and gating on it could mark a finisher DNF.
  Future<RaceCourse?> _loadCourse(String eventId, DateTime instance) async {
    final courses = await _social.fetchEventCourses(eventId);
    if (courses.isNotEmpty) {
      final mine = pickRaceCourse(
          courses, await _social.fetchMyCourseId(eventId, instance));
      if (mine == null) return null;
      // The frozen copy is what every racer in this race crosses; a race with
      // none (created before it existed) or a failed read keeps the live row.
      FrozenRaceCourse? frozen;
      try {
        frozen =
            (await _social.fetchRaceSessionCourses(eventId, instance))[mine.id];
      } catch (e) {
        debugPrint('[RaceController._loadCourse frozen] ${safeErrorLabel(e)}');
      }
      if (frozen != null) {
        return RaceCourse(
          courseId: mine.id,
          distanceM: frozen.distanceM,
          finishLat: frozen.finishLat,
          finishLng: frozen.finishLng,
          startLat: mine.startLat,
          startLng: mine.startLng,
          startGate: frozen.startGate,
          finishGate: frozen.finishGate,
          finishLineSelfCross: frozen.finishLineSelfCross,
        );
      }
      return RaceCourse(
        courseId: mine.id,
        distanceM: mine.distanceM,
        finishLat: mine.finishLat,
        finishLng: mine.finishLng,
        startLat: mine.startLat,
        startLng: mine.startLng,
        startGate: mine.startGate,
        finishGate: mine.finishGate,
        finishLineSelfCross: mine.finishLineSelfCross,
      );
    }
    return RaceCourse(
      courseId: null,
      distanceM: await _social.fetchEventDistanceM(eventId),
    );
  }

  /// Feed one fresh fix of the hosted recording. Returns the finish on the
  /// fix that finalises it — the caller then stops the recorder — and
  /// null otherwise. [at] is the device clock at the fix.
  RaceFinish? offerFix({
    required double lat,
    required double lng,
    required double coveredM,
    required DateTime at,
  }) {
    if (!_recording || _outcome != null || _raceEnded) return null;
    if (!lat.isFinite || !lng.isFinite || !coveredM.isFinite) return null;
    if (isHosting && !_firstFixSeen) {
      _firstFixSeen = true;
      _firstFixLat = lat;
      _firstFixLng = lng;
      _evaluateLateStart();
    }
    final fix = RaceFix(lat: lat, lng: lng, at: at, coveredM: coveredM);
    _fixLog.add(fix);
    if (_fixLog.length > kRaceFixLogMax + 1000) {
      _fixLog.removeRange(0, 1000);
      _attachLogIndex = _attachLogIndex > 1000 ? _attachLogIndex - 1000 : 0;
    }
    _updateDistanceToStart(lat, lng);
    final d = _detector;
    if (d == null) return null;
    if (_isV1(d) &&
        !_v1Sees(fix, _fixLog.length - 1,
            _gunAt?.subtract(clockOffset.offset))) {
      return null;
    }
    final finish = d.offer(fix);
    _checkStartCue();
    if (finish == null) return null;
    return _onDetectedFinish(finish, live: true);
  }

  /// Runs on the first fix and again when the course lands, whichever is
  /// second: the course load is async and may finish after the first fix.
  void _evaluateLateStart() {
    final gun = _gunAt;
    final began = _recordingStartedAt;
    if (_lateStart || !_firstFixSeen || gun == null || began == null) return;
    final course = _course;
    final lat = _firstFixLat;
    final lng = _firstFixLng;
    final fromStart = course != null && course.hasStart &&
            lat != null && lng != null
        ? raceDistanceM(lat, lng, course.startLat!, course.startLng!)
        : null;
    if (raceStartFlagged(
      gunAt: gun,
      recordingStartedAt: clockOffset.toServer(began),
      firstFixFromStartM: fromStart,
    )) {
      _lateStart = true;
      notifyListeners();
    }
  }

  /// The runner chose "Finish race" (or stopped mid-approach): settle the
  /// outcome from what they covered, timed at [now] — the instant they
  /// pressed Stop. A host End that arrived while they were choosing does
  /// not void it: the stop came first, so it is filed (§ 1857).
  RaceOutcome decideStop({required double coveredM, DateTime? now}) {
    final existing = _outcome;
    if (existing != null) return existing;
    final settled = _detector?.settle();
    final o = raceStopOutcome(
      candidate: settled,
      coveredM: coveredM,
      courseDistanceM: _course?.distanceM,
      now: now ?? DateTime.now(),
    );
    _outcome = o;
    if (o.method == RaceFinishMethod.auto) _finish = settled;
    notifyListeners();
    return o;
  }

  /// The hosted session's status as last read. A terminal status before
  /// this runner has an outcome is the host's End.
  @visibleForTesting
  void observeHostedSession(String status, DateTime? startedAt) {
    if (!isHosting) return;
    if (startedAt != null) {
      _gunAt = startedAt;
      _syncDetector();
    }
    if ((status == 'finished' || status == 'cancelled') &&
        _outcome == null &&
        !_raceEnded) {
      _raceEnded = true;
      notifyListeners();
    }
  }

  /// Fire once per GPS sample the recorder produces while a race is
  /// running. Posts a ping at most every 10s — more than that would
  /// spam `race_pings` and the spectator map.
  DateTime _lastPingAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> pushPing({
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
  }) async {
    final eid = _hostingEventId;
    final inst = _hostingInstance;
    if (eid == null || inst == null) return;
    final now = DateTime.now();
    if (now.difference(_lastPingAt) < const Duration(seconds: 10)) return;
    _lastPingAt = now;
    try {
      await _insertPing(racePingRow(
        eventId: eid,
        instance: inst,
        userId: _currentUserId,
        lat: lat,
        lng: lng,
        distanceM: distanceM,
        elapsedS: elapsedS,
        bpm: bpm,
      ));
    } catch (e) {
      debugPrint('[RaceController.pushPing] $e');
    }
  }

  /// The `race_pings` insert, as a seam. `_c` reaches a Supabase client no
  /// host test can initialize, and what these tests need to pin is not the
  /// insert but WHICH race each of the two callers keys its row to.
  @visibleForTesting
  Future<void> Function(Map<String, dynamic> row)? pingWriter;

  Future<void> _insertPing(Map<String, dynamic> row) async {
    final writer = pingWriter;
    if (writer != null) return writer(row);
    final sentAt = DateTime.now();
    final res =
        await _c.from('race_pings').insert(row).select('at').maybeSingle();
    final receivedAt = DateTime.now();
    final serverAt = parseIsoStrictValue(res?['at']);
    if (serverAt != null) {
      clockOffset.addSample(
          sentAt: sentAt, receivedAt: receivedAt, serverAt: serverAt);
    }
  }

  String? get _currentUserId => ApiClient.isInitialized
      ? Supabase.instance.client.auth.currentUser?.id
      : null;

  /// The signed-in account, as a seam: no host test can sign in to Supabase.
  @visibleForTesting
  String? Function()? userIdReader;

  String? get _signedInUserId {
    final reader = userIdReader;
    return reader != null ? reader() : _currentUserId;
  }

  /// Submit an event result tied to the currently hosted race, then
  /// detach. Called by the run screen once the recorder finishes.
  ///
  /// [detachRecorder] clears the only in-memory record that this run
  /// belonged to a race, so a failed submit used to lose the finisher's
  /// official time outright — the common case being a runner who crossed
  /// the line somewhere with no signal. The result is queued to disk on
  /// failure instead and replayed by [drainPendingResults].
  ///
  /// The timing columns come from [raceResultTiming]: a finish carries gun
  /// and chip time and ranks on the gun time when the race had a GO
  /// (decisions § 1843); a DNF carries neither, with [durationS] — the
  /// recording's elapsed seconds — as its `duration_s` (§ 1855). A
  /// race the host ended while this runner was still running submits
  /// nothing: the server has already marked them DNF.
  Future<void> submitResult({
    required String runId,
    required int durationS,
    required double distanceM,
  }) async {
    final eid = _hostingEventId;
    final inst = _hostingInstance;
    if (eid == null || inst == null) return;
    final owner = _hostingUserId ?? _signedInUserId;
    if (owner == null) {
      debugPrint('[RaceController.submitResult] no account to file under');
      detachRecorder();
      return;
    }
    final outcome = _outcome ??
        (_raceEnded ? null : decideStop(coveredM: distanceM));
    if (outcome == null) {
      detachRecorder();
      return;
    }
    // A finish filed at the line went without its run, which did not exist
    // yet; filing it again with the run links it. The timing is unchanged,
    // so the race guard treats it as no timing write at all.
    if (identical(outcome, _filedOutcome)) await _filing;
    await _file(_resultFor(
      owner: owner,
      eventId: eid,
      instance: inst,
      runId: runId,
      durationS: durationS,
      distanceM: distanceM,
      outcome: outcome,
    ));
    detachRecorder();
  }

  /// File the automatic finish now, while the recording stays open for
  /// "Not finished? Resume" (#1307 m11): the result reaches the leaderboard
  /// at the line, and a Stop later in the window files nothing again.
  Future<void> fileOutcomeNow({
    required int durationS,
    required double distanceM,
  }) {
    final eid = _hostingEventId;
    final inst = _hostingInstance;
    final outcome = _outcome;
    final owner = _hostingUserId ?? _signedInUserId;
    if (eid == null || inst == null || outcome == null || owner == null) {
      return Future<void>.value();
    }
    _filedOutcome = outcome;
    final filing = _file(_resultFor(
      owner: owner,
      eventId: eid,
      instance: inst,
      runId: null,
      durationS: durationS,
      distanceM: distanceM,
      outcome: outcome,
    ));
    _filing = filing;
    return filing;
  }

  /// "Not finished? Resume": void the automatic finish and keep racing. The
  /// filed row is deleted while it is still the runner's own automatic one,
  /// and a queued one is dropped. The rest of this recording finishes by
  /// hand: a line that finished the runner once where they were not
  /// finishing would do it again. Returns whether there was one to void.
  Future<bool> voidAutoFinish() async {
    final eid = _hostingEventId;
    final inst = _hostingInstance;
    final outcome = _outcome;
    if (eid == null ||
        inst == null ||
        outcome == null ||
        outcome.method != RaceFinishMethod.auto) {
      return false;
    }
    final filed = _filedOutcome != null;
    final filing = _filing;
    _keptStart = _finish?.start ?? _detector?.start;
    _outcome = null;
    _finish = null;
    _pendingFinish = null;
    _filedOutcome = null;
    _filing = null;
    _detector = null;
    _autoFinishVoided = true;
    notifyListeners();
    if (!filed) return true;
    final owner = _hostingUserId ?? _signedInUserId;
    _voiding = true;
    try {
      try {
        await filing;
      } catch (e) {
        debugPrint('[RaceController.voidAutoFinish filing] ${safeErrorLabel(e)}');
      }
      // A replay in flight could send the queued finish again after the
      // delete; let it land first, and start no other until this is done.
      await _drainFuture;
      if (owner != null) await _dequeuePendingResult(owner, eid, inst);
      try {
        await _social.deleteOwnAutoEventResult(eventId: eid, instance: inst);
      } catch (e) {
        debugPrint('[RaceController.voidAutoFinish] ${safeErrorLabel(e)}');
        if (owner != null && isRetryableRaceResultFailure(e)) {
          await _addPendingVoid(owner, eid, inst);
        }
      }
    } finally {
      _voiding = false;
    }
    return true;
  }

  bool _voiding = false;

  /// The row a race recording files for [outcome]: the timing columns from
  /// [raceResultTiming], and the crossings (#1307) on the server clock — the
  /// device instant plus the offset the gun time uses, which the server
  /// re-derives the gun and chip time from. A committed start (a start-line
  /// crossing, or GO for a runner past the line) is `gate`; without one the
  /// start is the runner's own Start press, `device`. A DNF carries none.
  PendingRaceResult _resultFor({
    required String owner,
    required String eventId,
    required DateTime instance,
    required String? runId,
    required int durationS,
    required double distanceM,
    required RaceOutcome outcome,
  }) {
    final auto = outcome.method == RaceFinishMethod.auto;
    final finish = auto ? _finish : null;
    final start = outcome.finished
        ? (finish?.start ?? _detector?.start ?? _keptStart)
        : null;
    // One offset, in whole milliseconds, for every instant filed and for the
    // offset filed beside them, so the server's derivation and a re-time
    // from the track (both in ms) reproduce the device's own gun time.
    final offset = Duration(milliseconds: clockOffset.offset.inMilliseconds);
    final gun = _gunAt;
    // A start at GO is GO itself: re-expressed under today's offset, not
    // the one the detector saw GO under, or a refined offset would put the
    // chip time a fraction under the gun time.
    final startDevice = !outcome.finished
        ? null
        : start != null && start.kind == RaceStartKind.go && gun != null
            ? gun.subtract(offset)
            : (start?.at ?? _recordingStartedAt);
    final finishDevice = outcome.finished ? outcome.finishAt : null;
    final timing = raceResultTiming(
      outcome: outcome,
      gunAt: gun,
      clockOffset: offset,
      recordingStartedAt: _recordingStartedAt,
      startAt: start == null ? null : startDevice,
      elapsedS: durationS,
    );
    return PendingRaceResult(
      userId: owner,
      eventId: eventId,
      instanceStart: instance,
      runId: runId,
      durationS: timing.durationS,
      distanceM: distanceM,
      finisherStatus: outcome.finisherStatus,
      courseId: _course?.courseId,
      gunTimeS: timing.gunTimeS,
      chipTimeS: timing.chipTimeS,
      finishMethod: outcome.method?.wire,
      crossings: RaceCrossings(
        startAt: startDevice?.add(offset).toUtc(),
        finishAt: finishDevice?.add(offset).toUtc(),
        startDetection: startDevice == null
            ? null
            : (start != null ? RaceStartDetection.gate : RaceStartDetection.device)
                .wire,
        finishDetection: auto
            ? (finish?.detection ?? RaceFinishDetection.zone).wire
            : null,
        clockOffsetMs: clockOffset.known ? offset.inMilliseconds : null,
      ),
    );
  }

  Future<void> _file(PendingRaceResult result) async {
    try {
      await _submitPending(result);
    } catch (e) {
      debugPrint('[RaceController.submitResult] ${safeErrorLabel(e)}');
      if (isRetryableRaceResultFailure(e)) await _queuePendingResult(result);
    }
  }

  Future<void> _dequeuePendingResult(
      String owner, String eventId, DateTime instance) async {
    try {
      final queued = await _readPendingResults();
      final before = queued.length;
      queued.removeWhere((r) =>
          r.userId == owner &&
          r.eventId == eventId &&
          r.instanceStart.isAtSameMomentAs(instance));
      if (queued.length != before) await _writePendingResults(queued);
    } catch (e) {
      debugPrint('[RaceController._dequeuePendingResult] $e');
    }
  }

  /// The upsert writes whoever is signed in, so a result is only ever sent
  /// while its own account is; otherwise it throws, which the callers read
  /// as retryable and keep on disk for that account's return.
  Future<void> _submitPending(PendingRaceResult r) async {
    if (_signedInUserId != r.userId) {
      throw StateError('race result belongs to another account');
    }
    await _flushPendingVoid(r.userId, r.eventId, r.instanceStart);
    return _social.submitEventResult(
      eventId: r.eventId,
      instance: r.instanceStart,
      durationS: r.durationS,
      distanceM: r.distanceM,
      runId: r.runId,
      finisherStatus: r.finisherStatus,
      courseId: r.courseId,
      gunTimeS: r.gunTimeS,
      chipTimeS: r.chipTimeS,
      finishMethod: r.finishMethod,
      crossings: r.crossings,
    );
  }

  Future<void>? _drainFuture;

  /// Replay every finisher time [submitResult] couldn't deliver. Runs off
  /// the session poll (and therefore also off [start]), so a result queued
  /// in a dead spot lands as soon as the phone is back on the network or
  /// the app is next opened. A result the server refuses outright is
  /// dropped ([isRetryableRaceResultFailure]). Only the signed-in account's
  /// entries are sent; another account's stay queued, untouched. An undo's
  /// pending delete goes first, and no replay starts while an undo runs.
  Future<void> drainPendingResults() {
    if (_voiding) return Future<void>.value();
    return _drainFuture ??= _drain().whenComplete(() => _drainFuture = null);
  }

  Future<void> _drain() async {
    final uid = _signedInUserId;
    if (uid == null) return;
    for (final v in await _readPendingVoids()) {
      if (v.userId != uid) continue;
      try {
        await _flushPendingVoid(v.userId, v.eventId, v.instance);
      } catch (e) {
        debugPrint('[RaceController.drainPendingResults void] ${safeErrorLabel(e)}');
      }
    }
    final queued = await _readPendingResults();
    if (queued.isEmpty) return;
    final remaining = <PendingRaceResult>[];
    for (final r in queued) {
      if (r.userId != uid) {
        remaining.add(r);
        continue;
      }
      try {
        await _submitPending(r);
      } catch (e) {
        final keep = isRetryableRaceResultFailure(e);
        debugPrint('[RaceController.drainPendingResults] '
            '${keep ? 'kept' : 'dropped'}: ${safeErrorLabel(e)}');
        if (keep) remaining.add(r);
      }
    }
    await _writePendingResults(remaining);
  }

  Future<List<({String userId, String eventId, DateTime instance})>>
      _readPendingVoids() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kPendingRaceVoidsKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <({String userId, String eventId, DateTime instance})>[];
      for (final e in decoded.whereType<Map>()) {
        final u = e['user_id'];
        final ev = e['event_id'];
        final inst = parseIsoStrictValue(e['instance_start']);
        if (u is String && ev is String && inst != null) {
          out.add((userId: u, eventId: ev, instance: inst));
        }
      }
      return out;
    } catch (e) {
      debugPrint('[RaceController._readPendingVoids] $e');
      return [];
    }
  }

  Future<void> _writePendingVoids(
      List<({String userId, String eventId, DateTime instance})> voids) async {
    final prefs = await SharedPreferences.getInstance();
    if (voids.isEmpty) {
      await prefs.remove(kPendingRaceVoidsKey);
      return;
    }
    await prefs.setString(
        kPendingRaceVoidsKey,
        jsonEncode([
          for (final v in voids)
            {
              'user_id': v.userId,
              'event_id': v.eventId,
              'instance_start': instanceStartKey(v.instance),
            }
        ]));
  }

  Future<void> _addPendingVoid(
      String userId, String eventId, DateTime instance) async {
    try {
      final voids = await _readPendingVoids();
      voids.removeWhere((v) =>
          v.userId == userId &&
          v.eventId == eventId &&
          v.instance.isAtSameMomentAs(instance));
      voids.add((userId: userId, eventId: eventId, instance: instance));
      await _writePendingVoids(voids);
    } catch (e) {
      debugPrint('[RaceController._addPendingVoid] $e');
    }
  }

  /// Delete the withdrawn finish for this race, if one is waiting. Throws
  /// when the delete fails for a reason worth retrying, so the result
  /// behind it waits too; a refusal drops the entry.
  Future<void> _flushPendingVoid(
      String userId, String eventId, DateTime instance) async {
    final voids = await _readPendingVoids();
    bool same(({String userId, String eventId, DateTime instance}) v) =>
        v.userId == userId &&
        v.eventId == eventId &&
        v.instance.isAtSameMomentAs(instance);
    if (!voids.any(same)) return;
    try {
      await _social.deleteOwnAutoEventResult(
          eventId: eventId, instance: instance);
    } catch (e) {
      if (isRetryableRaceResultFailure(e)) rethrow;
    }
    voids.removeWhere(same);
    await _writePendingVoids(voids);
  }

  /// Returns whether the result is now on disk. A `false` means the finisher
  /// time is lost unless its sender still holds it, which is why the watch
  /// relay reports it back rather than swallowing it.
  Future<bool> _queuePendingResult(PendingRaceResult result) async {
    try {
      final queued = await _readPendingResults();
      queued.removeWhere((r) =>
          r.userId == result.userId &&
          r.eventId == result.eventId &&
          r.instanceStart.isAtSameMomentAs(result.instanceStart));
      queued.add(result);
      await _writePendingResults(queued.length > kPendingRaceResultsMax
          ? queued.sublist(queued.length - kPendingRaceResultsMax)
          : queued);
      return true;
    } catch (e) {
      debugPrint('[RaceController._queuePendingResult] $e');
      return false;
    }
  }

  Future<List<PendingRaceResult>> _readPendingResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kPendingRaceResultsKey);
      if (raw == null || raw.isEmpty) return <PendingRaceResult>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <PendingRaceResult>[];
      return decoded
          .whereType<Map>()
          .map((e) => PendingRaceResult.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v))))
          .whereType<PendingRaceResult>()
          .toList();
    } catch (e) {
      debugPrint('[RaceController._readPendingResults] $e');
      return <PendingRaceResult>[];
    }
  }

  Future<void> _writePendingResults(List<PendingRaceResult> results) async {
    final prefs = await SharedPreferences.getInstance();
    if (results.isEmpty) {
      await prefs.remove(kPendingRaceResultsKey);
      return;
    }
    await prefs.setString(
        kPendingRaceResultsKey, jsonEncode(results.map((r) => r.toJson()).toList()));
  }
}
