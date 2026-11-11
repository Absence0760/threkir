/// Timing-line calibration (#1304 § 6, step 1): the error figures a field
/// session measures, from the fixes the production feed hands the race
/// detector. Debug builds only — the screen and the run screen's capture are
/// both behind `kDebugMode`, so a release build carries neither.
///
/// The operator video-times each real crossing against an NTP-synced clock
/// and types those instants in afterwards. A tap on the phone would add the
/// operator's reaction time (a few hundred ms, and not a constant one) to
/// every error, which is the size of what is being measured.
///
/// Nothing here keeps a fix past the session or writes one anywhere: the
/// capture is in memory, and [calibrationCsv] carries error figures and
/// counts only — no position, no timestamp, no free text.
library;

import 'dart:math' as math;

import 'package:run_recorder/run_recorder.dart' show RunSnapshot;

import 'gate_crossing.dart';

/// The most fixes one capture holds: 12 h at one a second.
const int kCalibrationMaxFixes = 43200;

/// A detected crossing further than this from every true one is false, and a
/// true one with no detection this close is missed.
const Duration kCalibrationMatchWindow = Duration(seconds: 10);

/// The matrix cell a capture belongs to (#1304 § 6). Closed vocabularies, so
/// nothing typed by hand reaches the export.
enum CalibrationApproach {
  deg90('90'),
  deg30('30'),
  parallel20('parallel_20m'),
  parallel40('parallel_40m'),
  standing('standing_on_line');

  const CalibrationApproach(this.wire);
  final String wire;
}

enum CalibrationPace {
  walk('walk'),
  run('run'),
  still('still');

  const CalibrationPace(this.wire);
  final String wire;
}

enum CalibrationCarry {
  hand('phone_hand'),
  pocket('phone_pocket');

  const CalibrationCarry(this.wire);
  final String wire;
}

class CalibrationCell {
  const CalibrationCell(this.approach, this.pace, this.carry);

  final CalibrationApproach approach;
  final CalibrationPace pace;
  final CalibrationCarry carry;
}

/// The fixes the race detector is offered, captured while a session runs.
///
/// [offer] applies the run screen's live-race feed rule (#1304 § 4): a fresh,
/// trusted fix, once per fix instant, timed at that instant, never while
/// paused or stopping. Each recording is kept apart ([recordings]): a race
/// detector starts fresh with every recording, so the last fix of one run
/// and the first of the next are never a pair.
class LineCalibrationCapture {
  LineCalibrationCapture();

  static final LineCalibrationCapture instance = LineCalibrationCapture();

  bool _active = false;
  DateTime? _lastFixAt;
  Duration? _lastElapsed;
  final List<List<GateFix>> _recordings = [];
  int _count = 0;

  bool get active => _active;
  int get fixCount => _count;
  List<List<GateFix>> get recordings =>
      [for (final r in _recordings) List.unmodifiable(r)];

  /// The first fix's instant (device clock), or null before one.
  double? get firstFixMs {
    for (final r in _recordings) {
      if (r.isNotEmpty) return r.first.tMs;
    }
    return null;
  }

  void start() {
    clear();
    _active = true;
  }

  void stop() => _active = false;

  void clear() {
    _active = false;
    _recordings.clear();
    _count = 0;
    _lastFixAt = null;
    _lastElapsed = null;
  }

  void offer(RunSnapshot snapshot,
      {required bool fresh, required bool paused}) {
    if (!_active) return;
    final elapsed = snapshot.elapsed;
    final last = _lastElapsed;
    if (last == null || elapsed < last) _recordings.add([]);
    _lastElapsed = elapsed;
    if (paused || !fresh || !snapshot.positionTrusted) return;
    final pos = snapshot.currentPosition;
    final at = snapshot.positionFixedAt;
    if (pos == null || at == null || at == _lastFixAt) return;
    _lastFixAt = at;
    final covered = snapshot.distanceMetres;
    if (!pos.lat.isFinite || !pos.lng.isFinite || !covered.isFinite) return;
    if (_count >= kCalibrationMaxFixes) return;
    _count++;
    _recordings.last.add(GateFix(
      lat: pos.lat,
      lng: pos.lng,
      tMs: at.microsecondsSinceEpoch / 1000,
      coveredM: covered,
    ));
  }
}

/// The server clock minus the device's, from round trips to `server_now`:
/// the server stamped somewhere inside each round trip, so the midpoint is
/// the device-side estimate and its error is at most half the round trip.
/// The sample with the shortest round trip wins, as in `ServerClockOffset`.
class CalibrationClock {
  Duration? _offset;
  Duration? _rtt;

  Duration? get offset => _offset;

  /// The winning sample's round trip; the offset is good to half of it.
  Duration? get rtt => _rtt;

  void addSample({
    required DateTime sentAt,
    required DateTime receivedAt,
    required DateTime serverAt,
  }) {
    final rtt = receivedAt.difference(sentAt);
    if (rtt.isNegative) return;
    final best = _rtt;
    if (best != null && rtt >= best) return;
    final mid = sentAt.add(Duration(microseconds: rtt.inMicroseconds ~/ 2));
    _offset = serverAt.difference(mid);
    _rtt = rtt;
  }
}

enum CalibrationOutcome {
  matched('matched'),
  missed('missed'),
  falseCrossing('false'),

  /// The track crossed the extended line beyond the half-width, within
  /// [kCalibrationNearMissWidths] half-widths, and no true crossing explains
  /// it: a pass the line rightly ignored (a parallel path), kept for its
  /// lateral offset, which is what `halfWidthM` is calibrated from.
  nearMiss('near_miss');

  const CalibrationOutcome(this.wire);
  final String wire;
}

/// How far out, in half-widths, a crossing of the extended line is still
/// exported as a [CalibrationOutcome.nearMiss].
const double kCalibrationNearMissWidths = 3;

/// Why a true crossing was not detected:
/// - the track crossed the line beyond its half-width;
/// - the true instant falls inside a pair of fixes on either side of the line
///   further apart than `rejectGapS` (judged by the pair's span, because an
///   interpolated instant across such a gap means nothing);
/// - the only crossing near it is backward (often a bearing entered the wrong
///   way round);
/// - else no undetected crossing lies near it (none at all, or the only one
///   nearby was paired with another true crossing).
enum CalibrationMissReason {
  outsideHalfWidth('outside_half_width'),
  gapRejected('gap_rejected'),
  backwardOnly('backward_only'),
  noCrossing('no_crossing');

  const CalibrationMissReason(this.wire);
  final String wire;
}

class CalibrationRow {
  const CalibrationRow({
    required this.outcome,
    this.errorMs,
    this.offsetM,
    this.gapped = false,
    this.missReason,
  });

  final CalibrationOutcome outcome;

  /// Detected minus true, on the server clock: positive is late. Matched
  /// rows only.
  final int? errorMs;

  /// The crossing's lateral offset from the line's centre, metres: the
  /// detected one, or where the track crossed the extended line for an
  /// [CalibrationMissReason.outsideHalfWidth] miss and a near miss.
  final double? offsetM;
  final bool gapped;
  final CalibrationMissReason? missReason;
}

class CalibrationResult {
  const CalibrationResult({
    required this.cell,
    required this.rows,
    required this.trueCount,
    required this.forwardCount,
    required this.backwardCount,
    this.offsetRttMs,
    this.nearestDiffMs,
  });

  final CalibrationCell cell;
  final List<CalibrationRow> rows;
  final int trueCount;
  final int forwardCount;
  final int backwardCount;

  /// The round trip of the clock sample the offset came from; null when the
  /// offset was entered by hand. Every error is uncertain by half of it.
  final int? offsetRttMs;

  /// The median, over the true crossings, of the nearest forward detection
  /// minus the truth, with no window: when nothing matched, a value far from
  /// zero points at a clock, offset or time-zone slip, not the detector.
  final int? nearestDiffMs;

  int _count(CalibrationOutcome o) => rows.where((r) => r.outcome == o).length;
  int get matched => _count(CalibrationOutcome.matched);
  int get missed => _count(CalibrationOutcome.missed);
  int get falseCrossings => _count(CalibrationOutcome.falseCrossing);
  int get nearMisses => _count(CalibrationOutcome.nearMiss);

  List<int> get _errors => [
        for (final r in rows)
          if (r.errorMs != null) r.errorMs!,
      ];

  int? get medianErrorMs => calibrationMedianMs(_errors);
  int? get medianAbsErrorMs =>
      calibrationMedianMs([for (final e in _errors) e.abs()]);

  /// Nearest-rank, so below 20 matched crossings it is the largest error.
  int? get p95AbsErrorMs =>
      calibrationPercentileMs([for (final e in _errors) e.abs()], 95);
}

/// The median, the mean of the two middle values for an even count, rounded
/// to the millisecond. Null for no values.
int? calibrationMedianMs(List<int> values) {
  if (values.isEmpty) return null;
  final v = List.of(values)..sort();
  final n = v.length;
  if (n.isOdd) return v[n ~/ 2];
  return ((v[n ~/ 2 - 1] + v[n ~/ 2]) / 2).round();
}

/// The nearest-rank [p]th percentile: the smallest value with at least p %
/// of the values at or below it. Null for no values.
int? calibrationPercentileMs(List<int> values, double p) {
  if (values.isEmpty) return null;
  final v = List.of(values)..sort();
  final rank = (p / 100 * v.length).ceil().clamp(1, v.length);
  return v[rank - 1];
}

List<GateCrossing> _crossings(
        List<List<GateFix>> recordings, Gate gate, GateCrossingOptions o) =>
    [for (final r in recordings) ...crossingsOf(r, gate, o)];

/// Score one capture against the operator's true crossing instants.
///
/// Each recording goes through `gate_crossing` with the shipped options, as
/// the race detector runs it. A fix instant is on the device clock; adding
/// [clockOffsetMs] (server minus device) puts it on the server clock the
/// [trueCrossings] were timed on. Each true crossing is paired with the
/// forward crossing nearest it within [window], closest pairs first, each
/// used once. An unpaired true crossing is missed and an unpaired forward
/// crossing is false; backward crossings are counted, not scored; crossings
/// of the extended line just beyond the half-width are near misses.
CalibrationResult analyseCalibration({
  required CalibrationCell cell,
  required List<List<GateFix>> recordings,
  required Gate gate,
  required List<DateTime> trueCrossings,
  required int clockOffsetMs,
  int? offsetRttMs,
  Duration window = kCalibrationMatchWindow,
  GateCrossingOptions options = const GateCrossingOptions(),
}) {
  final all = _crossings(recordings, gate, options);
  final forward =
      all.where((c) => c.direction == GateDirection.forward).toList();
  final backward =
      all.where((c) => c.direction == GateDirection.backward).toList();
  final truth = [
    for (final t in trueCrossings) t.microsecondsSinceEpoch / 1000,
  ];
  double serverMs(GateCrossing c) => c.tMs + clockOffsetMs;
  final windowMs = window.inMicroseconds / 1000;

  final pairs = <({int t, int d, double err})>[];
  for (var i = 0; i < truth.length; i++) {
    for (var j = 0; j < forward.length; j++) {
      final err = serverMs(forward[j]) - truth[i];
      if (err.abs() <= windowMs) pairs.add((t: i, d: j, err: err));
    }
  }
  pairs.sort((a, b) {
    final byErr = a.err.abs().compareTo(b.err.abs());
    if (byErr != 0) return byErr;
    final byTrue = a.t.compareTo(b.t);
    return byTrue != 0 ? byTrue : a.d.compareTo(b.d);
  });
  final trueTaken = <int, ({int d, double err})>{};
  final detTaken = <int>{};
  for (final p in pairs) {
    if (trueTaken.containsKey(p.t) || detTaken.contains(p.d)) continue;
    trueTaken[p.t] = (d: p.d, err: p.err);
    detTaken.add(p.d);
  }

  // The extended line, for crossings the half-width rejected.
  final wide = Gate(
      lat: gate.lat, lng: gate.lng, bearingDeg: gate.bearingDeg, halfWidthM: 1e9);
  final beyond = [
    for (final c in _crossings(recordings, wide, options))
      if (c.direction == GateDirection.forward &&
          c.offsetM.abs() > gate.halfWidthM)
        c,
  ];
  final beyondTaken = <int>{};

  final rows = <CalibrationRow>[];
  for (var i = 0; i < truth.length; i++) {
    final m = trueTaken[i];
    if (m != null) {
      final c = forward[m.d];
      rows.add(CalibrationRow(
        outcome: CalibrationOutcome.matched,
        errorMs: m.err.round(),
        offsetM: c.offsetM,
        gapped: c.gapped,
      ));
      continue;
    }
    rows.add(_missed(
      truthMs: truth[i],
      offsetMs: clockOffsetMs,
      windowMs: windowMs,
      beyond: beyond,
      beyondTaken: beyondTaken,
      backward: backward,
      recordings: recordings,
      gate: gate,
      options: options,
    ));
  }
  for (var j = 0; j < forward.length; j++) {
    if (detTaken.contains(j)) continue;
    rows.add(CalibrationRow(
      outcome: CalibrationOutcome.falseCrossing,
      offsetM: forward[j].offsetM,
      gapped: forward[j].gapped,
    ));
  }
  final nearLimit = gate.halfWidthM * kCalibrationNearMissWidths;
  for (var k = 0; k < beyond.length; k++) {
    final c = beyond[k];
    if (beyondTaken.contains(k) || c.offsetM.abs() > nearLimit) continue;
    rows.add(CalibrationRow(
      outcome: CalibrationOutcome.nearMiss,
      offsetM: c.offsetM,
      gapped: c.gapped,
    ));
  }

  final nearest = <int>[];
  if (forward.isNotEmpty) {
    for (final t in truth) {
      var best = double.infinity;
      for (final c in forward) {
        final d = serverMs(c) - t;
        if (d.abs() < best.abs()) best = d;
      }
      nearest.add(best.round());
    }
  }

  return CalibrationResult(
    cell: cell,
    rows: rows,
    trueCount: truth.length,
    forwardCount: forward.length,
    backwardCount: backward.length,
    offsetRttMs: offsetRttMs,
    nearestDiffMs: calibrationMedianMs(nearest),
  );
}

CalibrationRow _missed({
  required double truthMs,
  required int offsetMs,
  required double windowMs,
  required List<GateCrossing> beyond,
  required Set<int> beyondTaken,
  required List<GateCrossing> backward,
  required List<List<GateFix>> recordings,
  required Gate gate,
  required GateCrossingOptions options,
}) {
  bool near(GateCrossing c) => (c.tMs + offsetMs - truthMs).abs() <= windowMs;
  var pick = -1;
  for (var k = 0; k < beyond.length; k++) {
    if (beyondTaken.contains(k) || !near(beyond[k])) continue;
    if (pick < 0 ||
        (beyond[k].tMs - truthMs).abs() < (beyond[pick].tMs - truthMs).abs()) {
      pick = k;
    }
  }
  if (pick >= 0) {
    beyondTaken.add(pick);
    return CalibrationRow(
      outcome: CalibrationOutcome.missed,
      offsetM: beyond[pick].offsetM,
      gapped: beyond[pick].gapped,
      missReason: CalibrationMissReason.outsideHalfWidth,
    );
  }
  final deviceMs = truthMs - offsetMs;
  final rejectMs = options.rejectGapS * 1000;
  for (final r in recordings) {
    for (var i = 1; i < r.length; i++) {
      final a = r[i - 1];
      final b = r[i];
      if (b.tMs - a.tMs <= rejectMs) continue;
      if (deviceMs < a.tMs || deviceMs > b.tMs) continue;
      final sa = gateProjection(gate, a.lat, a.lng).s;
      final sb = gateProjection(gate, b.lat, b.lng).s;
      if ((sa < 0) != (sb < 0)) {
        return const CalibrationRow(
          outcome: CalibrationOutcome.missed,
          gapped: true,
          missReason: CalibrationMissReason.gapRejected,
        );
      }
    }
  }
  if (backward.any(near)) {
    return const CalibrationRow(
      outcome: CalibrationOutcome.missed,
      missReason: CalibrationMissReason.backwardOnly,
    );
  }
  return const CalibrationRow(
    outcome: CalibrationOutcome.missed,
    missReason: CalibrationMissReason.noCrossing,
  );
}

const List<String> kCalibrationCsvColumns = [
  'kind',
  'approach',
  'pace',
  'carry',
  'crossing',
  'outcome',
  'error_ms',
  'offset_m',
  'gapped',
  'miss_reason',
  'true_count',
  'forward_detected',
  'backward_detected',
  'matched',
  'missed',
  'false',
  'near_miss',
  'median_error_ms',
  'median_abs_error_ms',
  'p95_abs_error_ms',
  'offset_rtt_ms',
];

/// The export: one `crossing` row per scored crossing and one `summary` row
/// per capture. Every field is an enum wire value or a number derived from
/// the errors; the lateral offset is relative to the line, to 0.1 m.
String calibrationCsv(List<CalibrationResult> results) {
  final out = StringBuffer(kCalibrationCsvColumns.join(','))..write('\n');
  String n(num? v) => v == null ? '' : '$v';
  String m(double? v) => v == null ? '' : v.toStringAsFixed(1);
  for (final r in results) {
    final cell = [r.cell.approach.wire, r.cell.pace.wire, r.cell.carry.wire];
    for (var i = 0; i < r.rows.length; i++) {
      final row = r.rows[i];
      out
        ..write([
          'crossing',
          ...cell,
          '${i + 1}',
          row.outcome.wire,
          n(row.errorMs),
          m(row.offsetM),
          row.gapped ? '1' : '0',
          row.missReason?.wire ?? '',
          ...List.filled(11, ''),
        ].join(','))
        ..write('\n');
    }
    out
      ..write([
        'summary',
        ...cell,
        ...List.filled(6, ''),
        n(r.trueCount),
        n(r.forwardCount),
        n(r.backwardCount),
        n(r.matched),
        n(r.missed),
        n(r.falseCrossings),
        n(r.nearMisses),
        n(r.medianErrorMs),
        n(r.medianAbsErrorMs),
        n(r.p95AbsErrorMs),
        n(r.offsetRttMs),
      ].join(','))
      ..write('\n');
  }
  return out.toString();
}

/// Parse the operator's video-timed instants: one per line, a time of day
/// `HH:MM:SS(.fff)` on [day] in the device's zone, or an ISO-8601 instant
/// (read in the device's zone when it names none). Returns null when any non-blank line does not parse.
List<DateTime>? parseCalibrationInstants(String text, DateTime day) {
  final out = <DateTime>[];
  final clock = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$');
  for (final raw in text.split(RegExp(r'[\n,;]'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final c = clock.firstMatch(line);
    if (c != null) {
      final h = int.parse(c[1]!);
      final mi = int.parse(c[2]!);
      final s = int.parse(c[3]!);
      if (h > 23 || mi > 59 || s > 59) return null;
      final frac = c[4] ?? '';
      final us = frac.isEmpty
          ? 0
          : (int.parse(frac) * math.pow(10, 6 - frac.length)).round();
      final local = day.toLocal();
      out.add(DateTime(local.year, local.month, local.day, h, mi, s)
          .add(Duration(microseconds: us)));
      continue;
    }
    final iso = DateTime.tryParse(line);
    if (iso == null) return null;
    out.add(iso);
  }
  return out;
}
