import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apple_watch_race_bridge.dart';
import 'race_finish.dart';
import 'rate_limit_errors.dart';
import 'social_service.dart';

/// SharedPreferences key holding the finisher times that haven't reached
/// the server yet, as a JSON list of [PendingRaceResult].
const kPendingRaceResultsKey = 'race_pending_results';

/// Upper bound on the queue. A finisher time is one row per race, so this
/// is generous; the cap only exists so a permanently-failing write can't
/// grow the stored list without limit. Oldest entries drop first.
const kPendingRaceResultsMax = 20;

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

/// A finisher time that couldn't be submitted when the run finished.
///
/// `submitEventResult` upserts on `(event_id, instance_start, user_id)`, so
/// replaying one is idempotent — a queued result that actually landed on a
/// retry we never saw the response to just rewrites the same row.
class PendingRaceResult {
  const PendingRaceResult({
    required this.eventId,
    required this.instanceStart,
    required this.runId,
    required this.durationS,
    required this.distanceM,
    this.finisherStatus = 'finished',
    this.courseId,
    this.gunTimeS,
    this.chipTimeS,
    this.finishMethod,
  });

  final String eventId;
  final DateTime instanceStart;
  final String runId;
  final int durationS;
  final double distanceM;
  final String finisherStatus;
  final String? courseId;
  final int? gunTimeS;
  final int? chipTimeS;
  final String? finishMethod;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'event_id': eventId,
        'instance_start': instanceStartKey(instanceStart),
        'run_id': runId,
        'duration_s': durationS,
        'distance_m': distanceM,
        'finisher_status': finisherStatus,
        if (courseId != null) 'course_id': courseId,
        if (gunTimeS != null) 'gun_time_s': gunTimeS,
        if (chipTimeS != null) 'chip_time_s': chipTimeS,
        if (finishMethod != null) 'finish_method': finishMethod,
      };

  static PendingRaceResult? fromJson(Map<String, dynamic> json) {
    final eventId = json['event_id'];
    final instance = json['instance_start'];
    final runId = json['run_id'];
    final durationS = json['duration_s'];
    final distanceM = json['distance_m'];
    if (eventId is! String ||
        instance is! String ||
        runId is! String ||
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
    );
  }
}

/// The course a racer is running: what the finish detector and the coverage
/// gate need, resolved once when the recorder attaches. Read off the
/// `event_courses` row alone — never the route.
class RaceCourse {
  const RaceCourse({
    required this.courseId,
    required this.distanceM,
    this.finishLat,
    this.finishLng,
  });

  /// Null for an event with no `event_courses` rows, raced on the event's
  /// own distance with no finish point.
  final String? courseId;
  final double? distanceM;
  final double? finishLat;
  final double? finishLng;

  bool get hasFinish => finishLat != null && finishLng != null;
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
/// run screen surfaces a "Race armed — waiting for GO" banner. When the
/// session flips to `running`, clients hosting a recorder tag the
/// resulting run with `event_id` and push pings while it's in progress.
///
/// This is deliberately a lightweight notifier rather than a full state
/// machine — the existing `RunRecorder` state machine in run_screen is
/// complex enough already. When the race flips to running the user still
/// taps Start manually for v1 (the recorder already handles permissions
/// + countdown correctly); auto-start from the remote signal is a
/// follow-up that needs permission-flow plumbing.
class ActiveRace {
  final String eventId;
  final DateTime instanceStart;
  final String status; // armed | running | finished | cancelled
  final DateTime? startedAt;
  final String? eventTitle;

  const ActiveRace({
    required this.eventId,
    required this.instanceStart,
    required this.status,
    required this.startedAt,
    required this.eventTitle,
  });

  bool get isArmed => status == 'armed';
  bool get isRunning => status == 'running';
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

  /// GO, on the server clock. Null until the session row says so.
  DateTime? _gunAt;
  DateTime? _recordingStartedAt;
  RaceCourse? _course;
  RaceFinishDetector? _detector;
  RaceOutcome? _outcome;
  bool _raceEnded = false;
  bool _lateStart = false;
  bool _firstFixSeen = false;

  /// Device-to-server clock offset, sampled off every ping's server-stamped
  /// `at` (decisions § 1843).
  final ServerClockOffset clockOffset = ServerClockOffset();

  /// Whether a recorder is attached to a running race.
  bool get isHosting => _hostingEventId != null;

  /// The host ended the race before this runner finished. The server marks
  /// the runner DNF; nothing is submitted from here.
  bool get raceEnded => _raceEnded;

  /// The recording started more than five minutes after GO (the
  /// far-from-start arm is dormant: no start point on the course row,
  /// decisions § 1845). Surfaced on the run screen; not yet carried on the
  /// result (decisions § 1843).
  bool get lateStart => _lateStart;

  RaceCourse? get course => _course;
  RaceOutcome? get outcome => _outcome;

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
    final ch = _channel;
    if (ch != null) _c.removeChannel(ch);
    super.dispose();
  }

  Future<void> _refresh() async {
    final uid = _c.auth.currentUser?.id;
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
    // Events the user is `going` to within the next 24h (window for
    // live races). Keeps the fetch small for a single user.
    final now = DateTime.now().toUtc();
    final horizon = now.add(const Duration(hours: 24));
    final past = now.subtract(const Duration(hours: 6));
    try {
      final rsvps = await _c
          .from('event_attendees')
          .select('event_id, instance_start, status')
          .eq('user_id', uid)
          .eq('status', 'going')
          .gte('instance_start', instanceStartKey(past))
          .lte('instance_start', instanceStartKey(horizon));
      final list = (rsvps as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) { _setActive(null); return; }

      // Check each for an armed/running race session. In practice a user
      // has 1-3 upcoming RSVPs at most, but firing the per-RSVP fetches
      // in parallel via Future.wait means we get done in the wall time
      // of the slowest one rather than the sum of all of them.
      final sessionResults = await Future.wait(list.map((r) async {
        final eventId = r['event_id'] as String;
        final inst =
            parseIsoStrictRequired(r['instance_start'], 'instance_start');
        final res = await _c
            .from('race_sessions')
            .select('status, started_at')
            .eq('event_id', eventId)
            .eq('instance_start', instanceStartKey(inst))
            .inFilter('status', ['armed', 'running'])
            .maybeSingle();
        return (eventId: eventId, inst: inst, row: res);
      }));

      ActiveRace? next;
      for (final s in sessionResults) {
        final res = s.row;
        if (res == null) continue;
        final title = await _eventTitle(s.eventId);
        next = ActiveRace(
          eventId: s.eventId,
          instanceStart: s.inst,
          status: res['status'] as String,
          startedAt: parseIsoStrictValue(res['started_at']),
          eventTitle: title,
        );
        // Prefer running over armed if we somehow see both.
        if (next.isRunning) break;
      }
      _setActive(next);
    } catch (e) {
      debugPrint('[RaceController._refresh] $e');
    }
  }

  // LinkedHashMap-style cache with a simple LRU cap. Was unbounded —
  // a user attending many events over an app session would accumulate
  // titles indefinitely.
  static const _titleCacheMax = 32;
  final Map<String, String?> _titleCache = <String, String?>{};
  Future<String?> _eventTitle(String eventId) async {
    if (_titleCache.containsKey(eventId)) {
      // Bump to most-recent by re-inserting.
      final v = _titleCache.remove(eventId);
      _titleCache[eventId] = v;
      return v;
    }
    final row = await _c
        .from('events')
        .select('title')
        .eq('id', eventId)
        .maybeSingle();
    final title = (row as Map?)?['title'] as String?;
    _titleCache[eventId] = title;
    if (_titleCache.length > _titleCacheMax) {
      _titleCache.remove(_titleCache.keys.first);
    }
    return title;
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
    final changed = next?.eventId != _active?.eventId ||
        next?.instanceStart != _active?.instanceStart ||
        next?.status != _active?.status ||
        next?.startedAt != _active?.startedAt;
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
    return _queuePendingResult(PendingRaceResult(
      eventId: result.eventId,
      instanceStart: result.instanceStart,
      runId: result.runId,
      durationS: result.durationS,
      distanceM: result.distanceM,
    ));
  }

  /// Called by the run screen when it starts a recorder while a race is
  /// running. Enables live pings at a 10s cadence and resolves the racer's
  /// course for finish detection. [startedAt] is the session's GO;
  /// [recordingStartedAt] is when this recording began (device clock).
  void attachRecorder({
    required String eventId,
    required DateTime instance,
    DateTime? startedAt,
    DateTime? recordingStartedAt,
  }) {
    _hostingEventId = eventId;
    _hostingInstance = instance;
    _gunAt = startedAt;
    _recordingStartedAt = recordingStartedAt;
    _course = null;
    _detector = null;
    _outcome = null;
    _raceEnded = false;
    _lateStart = false;
    _firstFixSeen = false;
    unawaited(_resolveCourse(++_attachGeneration, eventId, instance));
  }

  void detachRecorder() {
    _attachGeneration++;
    _hostingEventId = null;
    _hostingInstance = null;
    _gunAt = null;
    _recordingStartedAt = null;
    _course = null;
    _detector = null;
    _outcome = null;
    _raceEnded = false;
    _lateStart = false;
    _firstFixSeen = false;
    _pingTimer?.cancel();
    _pingTimer = null;
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
  Future<void> _resolveCourse(
      int generation, String eventId, DateTime instance) async {
    try {
      final loader = courseLoader ?? _loadCourse;
      final course = await loader(eventId, instance);
      if (generation != _attachGeneration) return;
      setCourse(course);
    } catch (e) {
      debugPrint('[RaceController._resolveCourse] ${safeErrorLabel(e)}');
    }
  }

  /// Install the racer's course. Public for the run-screen tests, which
  /// drive a race without a network.
  @visibleForTesting
  void setCourse(RaceCourse? course) {
    _course = course;
    final distance = course?.distanceM;
    _detector = course != null &&
            course.hasFinish &&
            distance != null &&
            distance.isFinite &&
            distance > 0
        ? RaceFinishDetector(
            finishLat: course.finishLat!,
            finishLng: course.finishLng!,
            courseDistanceM: distance,
          )
        : null;
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
      return RaceCourse(
        courseId: mine.id,
        distanceM: mine.distanceM,
        finishLat: mine.finishLat,
        finishLng: mine.finishLng,
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
    if (!isHosting || _outcome != null || _raceEnded) return null;
    if (!_firstFixSeen) {
      _firstFixSeen = true;
      _evaluateLateStart();
    }
    final finish = _detector?.offer(
        RaceFix(lat: lat, lng: lng, at: at, coveredM: coveredM));
    if (finish == null) return null;
    _outcome = RaceOutcome(
      finisherStatus: 'finished',
      method: RaceFinishMethod.auto,
      finishAt: finish.at,
    );
    notifyListeners();
    return finish;
  }

  void _evaluateLateStart() {
    final gun = _gunAt;
    final began = _recordingStartedAt;
    if (_lateStart || gun == null || began == null) return;
    // No first-fix-from-start distance: the course row carries no start
    // point and the route is not read (decisions § 1845).
    if (raceStartFlagged(
      gunAt: gun,
      recordingStartedAt: clockOffset.toServer(began),
    )) {
      _lateStart = true;
      notifyListeners();
    }
  }

  /// The runner chose "Finish race" (or stopped mid-approach): settle the
  /// outcome from what they covered.
  RaceOutcome decideStop({required double coveredM, DateTime? now}) {
    final existing = _outcome;
    if (existing != null) return existing;
    final o = raceStopOutcome(
      candidate: _detector?.settle(),
      coveredM: coveredM,
      courseDistanceM: _course?.distanceM,
      now: now ?? DateTime.now(),
    );
    _outcome = o;
    notifyListeners();
    return o;
  }

  /// The hosted session's status as last read. A terminal status before
  /// this runner has an outcome is the host's End.
  @visibleForTesting
  void observeHostedSession(String status, DateTime? startedAt) {
    if (!isHosting) return;
    if (startedAt != null) _gunAt = startedAt;
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

  /// Submit an event result tied to the currently hosted race, then
  /// detach. Called by the run screen once the recorder finishes.
  ///
  /// [detachRecorder] clears the only in-memory record that this run
  /// belonged to a race, so a failed submit used to lose the finisher's
  /// official time outright — the common case being a runner who crossed
  /// the line somewhere with no signal. The result is queued to disk on
  /// failure instead and replayed by [drainPendingResults].
  ///
  /// Chip time runs from this recording's Start to the finish instant on the
  /// device clock, pauses included; [durationS] stands in only when there is
  /// no finish instant (a DNF). The submitted `duration_s` is the gun time
  /// whenever the race had a GO, else the chip time (decisions § 1843). A race the host ended first submits nothing: the
  /// server has already marked this runner DNF.
  Future<void> submitResult({
    required String runId,
    required int durationS,
    required double distanceM,
  }) async {
    final eid = _hostingEventId;
    final inst = _hostingInstance;
    if (eid == null || inst == null) return;
    final outcome = _outcome ??
        (_raceEnded ? null : decideStop(coveredM: distanceM));
    if (outcome == null) {
      detachRecorder();
      return;
    }
    final finishAt = outcome.finishAt;
    final began = _recordingStartedAt;
    final gun = finishAt == null ? null : gunTimeTo(finishAt);
    final chip = finishAt != null && began != null
        ? raceChipTimeS(finishAtDevice: finishAt, recordingStartedAt: began)
        : null;
    final result = PendingRaceResult(
      eventId: eid,
      instanceStart: inst,
      runId: runId,
      durationS: gun ?? chip ?? durationS,
      distanceM: distanceM,
      finisherStatus: outcome.finisherStatus,
      courseId: _course?.courseId,
      gunTimeS: gun,
      chipTimeS: chip ?? durationS,
      finishMethod: outcome.method?.wire,
    );
    try {
      await _submitPending(result);
    } catch (e) {
      debugPrint('[RaceController.submitResult] ${safeErrorLabel(e)}');
      if (isRetryableRaceResultFailure(e)) await _queuePendingResult(result);
    }
    detachRecorder();
  }

  Future<void> _submitPending(PendingRaceResult r) => _social.submitEventResult(
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
      );

  bool _draining = false;

  /// Replay every finisher time [submitResult] couldn't deliver. Runs off
  /// the session poll (and therefore also off [start]), so a result queued
  /// in a dead spot lands as soon as the phone is back on the network or
  /// the app is next opened. A result the server refuses outright is
  /// dropped ([isRetryableRaceResultFailure]).
  Future<void> drainPendingResults() async {
    if (_draining) return;
    final queued = await _readPendingResults();
    if (queued.isEmpty) return;
    _draining = true;
    try {
      final remaining = <PendingRaceResult>[];
      for (final r in queued) {
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
    } finally {
      _draining = false;
    }
  }

  /// Returns whether the result is now on disk. A `false` means the finisher
  /// time is lost unless its sender still holds it, which is why the watch
  /// relay reports it back rather than swallowing it.
  Future<bool> _queuePendingResult(PendingRaceResult result) async {
    try {
      final queued = await _readPendingResults();
      queued.removeWhere((r) =>
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
