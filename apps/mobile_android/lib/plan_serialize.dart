/// Plan import: parse a pasted Markdown table (or a JSON export) into a
/// plan ready for [TrainingService.createPlan]. The table shape is the one
/// web's plan export writes, so a plan exported on web, or a coach's
/// hand-built table in the same shape, imports here to the same workouts.
///
/// Dart twin of `apps/web/src/lib/training/plan_serialize.ts`, the PARSE
/// half only (decisions § 2053): `parsePlanMarkdown` + `parsePlanJson`,
/// with the header-aware Race / Priority / Goal columns and the legacy
/// six-column positional table. The Markdown writer is ported privately,
/// only because the JSON import is defined as "re-render as Markdown, then
/// parse" on web. Keep the accepted cell forms, error messages, phase and
/// volume recompute, goal-distance resolution and the mirrored test cases
/// in lockstep.
///
/// Lossy by design, as on web: pace tolerance, structured intervals and
/// duration steps are not in the table, so a parsed workout carries
/// distance, pace, notes and the race fields and nulls the rest.
library;

import 'dart:convert';

import 'plan_races.dart' show raceGoalMaxHours, racePriorities;
import 'training.dart';

const double _metresPerMile = 1609.344;

const List<String> _workoutKinds = [
  'easy',
  'long',
  'recovery',
  'tempo',
  'interval',
  'marathon_pace',
  'walk_run',
  'race',
  'rest',
];

const List<String> _goalEvents = [
  'distance_5k',
  'distance_10k',
  'distance_half',
  'distance_full',
  'custom',
];

/// A readable reason a pasted plan could not be read, for the UI to show.
class PlanParseError implements Exception {
  final String message;
  const PlanParseError(this.message);
  @override
  String toString() => message;
}

/// A parsed plan. [startDate] is ISO `yyyy-mm-dd`.
class ParsedPlan {
  final String name;
  final GoalEvent goalEvent;
  final double goalDistanceM;
  final int? goalTimeSec;
  final String startDate;
  final GeneratedPlan generated;

  const ParsedPlan({
    required this.name,
    required this.goalEvent,
    required this.goalDistanceM,
    required this.goalTimeSec,
    required this.startDate,
    required this.generated,
  });
}

/// JS `parseInt(s, 10)`: the leading integer, ignoring what follows.
int? _jsParseInt(String s) {
  final m = RegExp(r'^\s*([+-]?\d+)').firstMatch(s);
  return m == null ? null : int.parse(m.group(1)!);
}

/// JS `parseFloat`: the leading decimal, ignoring what follows.
double? _jsParseFloat(String s) {
  final m = RegExp(r'^\s*([+-]?(\d+\.?\d*|\.\d+))').firstMatch(s);
  return m == null ? null : double.parse(m.group(1)!);
}

String _fmtKmCell(num? metres) {
  if (metres == null || metres <= 0) return '';
  return '${(metres / 1000).toStringAsFixed(2)} km';
}

String _fmtPaceCell(num? secPerKm) {
  if (secPerKm == null || secPerKm <= 0) return '';
  final total = secPerKm.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

String _fmtHmsCell(num? sec) {
  if (sec == null || sec <= 0) return '';
  final total = sec.round();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${total ~/ 3600}:${two((total % 3600) ~/ 60)}:${two(total % 60)}';
}

String _sanitizeCell(String? s) {
  if (s == null || s.isEmpty) return '';
  return s.replaceAll('|', '/').replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
}

String _str(Object? v) => v == null ? '' : '$v';

/// Web's `planToMarkdown`, over the decoded JSON export shape.
String _planToMarkdown({
  required String name,
  required String goalEvent,
  required num goalDistanceM,
  required num? goalTimeSec,
  required String startDate,
  required List<Map<String, dynamic>> workouts,
}) {
  final lines = <String>[];
  final title = _sanitizeCell(name);
  lines.add('# ${title.isEmpty ? 'Training plan' : title}');
  lines.add('');
  lines.add('- Goal event: $goalEvent');
  lines.add('- Goal distance: ${(goalDistanceM / 1000).toStringAsFixed(2)} km');
  if (goalTimeSec != null && goalTimeSec > 0) {
    lines.add('- Goal time: ${_fmtHmsCell(goalTimeSec)}');
  }
  lines.add('- Start date: $startDate');
  lines.add('');
  bool truthy(Object? v) => v != null && v != '' && v != false && v != 0;
  final raceCols = workouts.any(
    (w) =>
        w['kind'] == 'race' &&
        (truthy(w['race_name']) ||
            truthy(w['race_priority']) ||
            ((w['target_duration_seconds'] as num?) ?? 0) > 0),
  );
  if (raceCols) {
    lines.add(
      '| Week | Date | Type | Distance | Pace | Notes | Race | Priority | Goal |',
    );
    lines.add('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  } else {
    lines.add('| Week | Date | Type | Distance | Pace | Notes |');
    lines.add('| --- | --- | --- | --- | --- | --- |');
  }
  final sorted = [...workouts];
  _stableSortBy(sorted, (w) => _str(w['scheduled_date']));
  for (final w in sorted) {
    final base =
        '| ${(w['week_index'] as num) + 1} | ${_str(w['scheduled_date'])}'
        ' | ${_str(w['kind'])} | ${_fmtKmCell(w['target_distance_m'] as num?)}'
        ' | ${_fmtPaceCell(w['target_pace_sec_per_km'] as num?)}'
        ' | ${_sanitizeCell(w['notes'] as String?)} |';
    if (!raceCols) {
      lines.add(base);
    } else if (w['kind'] == 'race') {
      lines.add(
        '$base ${_sanitizeCell(w['race_name'] as String?)}'
        ' | ${_str(w['race_priority'])}'
        ' | ${_fmtHmsCell(w['target_duration_seconds'] as num?)} |',
      );
    } else {
      lines.add('$base  |  |  |');
    }
  }
  return '${lines.join('\n')}\n';
}

void _stableSortBy<T>(List<T> list, String Function(T) key) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = key(a.$2).compareTo(key(b.$2));
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}

double? _parseDistanceCell(String cell) {
  final t = cell.trim();
  if (t.isEmpty) return null;
  final m = RegExp(
    r'^([\d.]+)\s*(km|mi|m)?$',
    caseSensitive: false,
  ).firstMatch(t);
  if (m == null) throw PlanParseError('Couldn\'t read distance "$cell".');
  final value = _jsParseFloat(m.group(1)!);
  if (value == null) {
    throw PlanParseError('Couldn\'t read distance "$cell".');
  }
  final unit = (m.group(2) ?? 'km').toLowerCase();
  if (unit == 'mi') return value * _metresPerMile;
  if (unit == 'm') return value;
  return value * 1000;
}

int? _parsePaceCell(String cell) {
  final t = cell.trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
  if (m == null) {
    throw PlanParseError('Couldn\'t read pace "$cell" — use m:ss.');
  }
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

int? _parseHms(String t) {
  final trimmed = t.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split(':').map(_jsParseInt).toList();
  if (parts.any((p) => p == null)) return null;
  if (parts.length == 3) return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
  if (parts.length == 2) return parts[0]! * 60 + parts[1]!;
  return null;
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

const int _raceNameMax = 120;

class _ParsedRow {
  final int weekIndex;
  final String scheduledDate;
  final String kind;
  final double? targetDistanceM;
  final int? targetPaceSecPerKm;
  final String? notes;
  final String? raceName;
  final String? racePriority;
  final int? targetDurationSeconds;

  const _ParsedRow({
    required this.weekIndex,
    required this.scheduledDate,
    required this.kind,
    required this.targetDistanceM,
    required this.targetPaceSecPerKm,
    required this.notes,
    required this.raceName,
    required this.racePriority,
    required this.targetDurationSeconds,
  });
}

const Map<String, String> _columnAliases = {
  'week': 'week',
  'date': 'date',
  'type': 'type',
  'kind': 'type',
  'distance': 'distance',
  'pace': 'pace',
  'notes': 'notes',
  'note': 'notes',
  'race': 'race',
  'priority': 'priority',
  'goal': 'goal',
};

const List<String> _legacyColumns = [
  'week',
  'date',
  'type',
  'distance',
  'pace',
  'notes',
];

/// Column positions from a header row, or null when the header is the
/// legacy six-column one (or a prefix of it) or names a column this parser
/// does not know — both of which keep the positional reading.
Map<String, int>? _headerColumns(List<String> cells) {
  final names = cells
      .map((c) => _columnAliases[c.trim().toLowerCase()])
      .toList();
  if (names.any((n) => n == null)) return null;
  var legacy = true;
  for (var i = 0; i < names.length; i++) {
    if (i >= _legacyColumns.length || names[i] != _legacyColumns[i]) {
      legacy = false;
      break;
    }
  }
  if (legacy) return null;
  final map = <String, int>{};
  for (var i = 0; i < names.length; i++) {
    if (map.containsKey(names[i])) {
      throw PlanParseError('Column "${cells[i]}" appears twice.');
    }
    map[names[i]!] = i;
  }
  for (final required in const ['week', 'date', 'type']) {
    if (!map.containsKey(required)) {
      throw PlanParseError('The table has no $required column.');
    }
  }
  return map;
}

String? _parseRaceName(String cell) {
  final t = cell.trim();
  if (t.isEmpty) return null;
  if (t.length > _raceNameMax) {
    throw PlanParseError(
      'Race name "${t.substring(0, 40)}…" is longer than '
      '$_raceNameMax characters.',
    );
  }
  return t;
}

String? _parsePriorityCell(String cell) {
  final t = cell.trim().toUpperCase();
  if (t.isEmpty) return null;
  if (!racePriorities.contains(t)) {
    throw PlanParseError('Bad race priority "$cell" — use A, B or C.');
  }
  return t;
}

/// A race goal cell: h:mm:ss with at most [raceGoalMaxHours] hours, or m:ss
/// under the same ceiling, minutes and seconds 0-59 where they are not the
/// leading field.
int? _parseGoalCell(String cell) {
  final t = cell.trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d+):(\d{2})(?::(\d{2}))?$').firstMatch(t);
  int? sec;
  if (m != null) {
    final fields = [
      for (var i = 1; i <= 3; i++)
        if (m.group(i) != null) int.parse(m.group(i)!),
    ];
    final total = _parseHms(t);
    if (fields.skip(1).every((f) => f <= 59) &&
        total != null &&
        total <= raceGoalMaxHours * 3600 + 59 * 60 + 59) {
      sec = total;
    }
  }
  if (sec == null || sec <= 0) {
    throw PlanParseError('Couldn\'t read goal time "$cell" — use h:mm:ss.');
  }
  return sec;
}

bool _isSeparatorRow(List<String> cells) => cells.every(
  (c) => RegExp(r'^:?-{2,}:?$').hasMatch(c.trim()) || c.trim().isEmpty,
);

DateTime _localDate(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Parse a Markdown export (or a hand-written table in the same shape).
/// Throws [PlanParseError] on malformed input.
ParsedPlan parsePlanMarkdown(String text) {
  var name = '';
  String? goalEventToken;
  double? goalDistanceM;
  int? goalTimeSec;
  String? startDate;
  final rows = <_ParsedRow>[];
  var sawHeaderRow = false;
  Map<String, int>? columns;

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('# ')) {
      if (name.isEmpty) name = line.substring(2).trim();
      continue;
    }
    if (line.startsWith('- ')) {
      final body = line.substring(2);
      final colon = body.indexOf(':');
      if (colon == -1) continue;
      final key = body.substring(0, colon).trim().toLowerCase();
      final val = body.substring(colon + 1).trim();
      if (key == 'goal event') {
        goalEventToken = val;
      } else if (key == 'goal distance') {
        goalDistanceM = _parseDistanceCell(val);
      } else if (key == 'goal time') {
        goalTimeSec = _parseHms(val);
      } else if (key == 'start date') {
        startDate = val;
      }
      continue;
    }
    if (line.startsWith('|')) {
      final split = line.split('|');
      final cells = split.length < 2
          ? <String>[]
          : split.sublist(1, split.length - 1).map((c) => c.trim()).toList();
      if (_isSeparatorRow(cells)) continue;
      if (!sawHeaderRow) {
        final legacyHeader =
            cells.length >= 2 &&
            RegExp('week', caseSensitive: false).hasMatch(cells[0]) &&
            RegExp('date', caseSensitive: false).hasMatch(cells[1]);
        final named =
            rows.isEmpty && cells.any((c) => c.trim().toLowerCase() == 'week');
        if (legacyHeader || named) {
          sawHeaderRow = true;
          columns = rows.isEmpty ? _headerColumns(cells) : null;
          continue;
        }
      }
      if (columns == null && cells.length < 5) continue;
      final cols = columns;
      String cell(String col) {
        final i = cols?[col];
        return i == null || i >= cells.length ? '' : cells[i];
      }

      final List<String> positional = cols != null
          ? [
              cell('week'),
              cell('date'),
              cell('type'),
              cell('distance'),
              cell('pace'),
              cell('notes'),
            ]
          : cells;
      final weekCell = positional[0];
      final dateCell = positional[1];
      final kindCell = positional[2];
      final distCell = positional[3];
      final paceCell = positional[4];
      final noteCells = positional.sublist(5);

      final weekNum = _jsParseInt(weekCell);
      if (weekNum == null || weekNum < 1) {
        throw PlanParseError('Bad week number "$weekCell".');
      }
      if (!_isoDate.hasMatch(dateCell)) {
        throw PlanParseError('Bad date "$dateCell" — use YYYY-MM-DD.');
      }
      final kind = kindCell.trim().toLowerCase();
      if (!_workoutKinds.contains(kind)) {
        throw PlanParseError('Unknown workout type "$kindCell".');
      }
      final raceName = _parseRaceName(cell('race'));
      final racePriority = _parsePriorityCell(cell('priority'));
      final targetDurationSeconds = _parseGoalCell(cell('goal'));
      if (kind != 'race' &&
          (raceName != null ||
              racePriority != null ||
              targetDurationSeconds != null)) {
        throw PlanParseError(
          'Race, Priority and Goal only apply to race rows '
          '— $dateCell is a $kind workout.',
        );
      }
      final notes = noteCells.join('|').trim();
      rows.add(
        _ParsedRow(
          weekIndex: weekNum - 1,
          scheduledDate: dateCell,
          kind: kind,
          targetDistanceM: _parseDistanceCell(distCell),
          targetPaceSecPerKm: _parsePaceCell(paceCell),
          notes: notes.isEmpty ? null : notes,
          raceName: raceName,
          racePriority: racePriority,
          targetDurationSeconds: targetDurationSeconds,
        ),
      );
    }
  }

  if (rows.isEmpty) {
    throw const PlanParseError(
      'No workout rows found. Expected a | Week | Date | … | table.',
    );
  }

  _stableSortBy(rows, (r) => r.scheduledDate);

  final totalWeeks =
      rows.map((r) => r.weekIndex).reduce((a, b) => a > b ? a : b) + 1;
  final byWeek = <int, List<_ParsedRow>>{};
  for (final r in rows) {
    byWeek.putIfAbsent(r.weekIndex, () => []).add(r);
  }
  final weekIndexes = byWeek.keys.toList()..sort();
  final weeks = [
    for (final weekIndex in weekIndexes)
      GeneratedWeek(
        weekIndex: weekIndex,
        phase: phaseFor(weekIndex, totalWeeks),
        targetVolumeM: byWeek[weekIndex]!.fold<double>(
          0,
          (s, w) => s + (w.targetDistanceM ?? 0),
        ),
        notes: null,
        workouts: [
          for (final w in byWeek[weekIndex]!)
            GeneratedWorkout(
              scheduledDate: _localDate(w.scheduledDate),
              kind: workoutKindFromDb(w.kind),
              targetDistanceM: w.targetDistanceM,
              targetDurationSeconds: w.targetDurationSeconds,
              targetPaceSecPerKm: w.targetPaceSecPerKm,
              notes: w.notes,
              raceName: w.raceName,
              racePriority: w.racePriority,
            ),
        ],
      ),
  ];

  final goalEvent =
      goalEventToken != null && _goalEvents.contains(goalEventToken)
      ? goalEventFromDb(goalEventToken)
      : GoalEvent.custom;
  // A known event takes its canonical distance: the "Goal distance" line is
  // rounded to 2 dp of km, so trusting it would turn 42195 m into 42200.
  final double resolvedDistance;
  if (goalEvent != GoalEvent.custom) {
    resolvedDistance = kGoalDistancesM[goalEvent]!;
  } else if (goalDistanceM != null && goalDistanceM > 0) {
    resolvedDistance = goalDistanceM;
  } else {
    resolvedDistance = rows.fold<double>(
      0,
      (m, r) => (r.targetDistanceM ?? 0) > m ? r.targetDistanceM! : m,
    );
  }
  if (!(resolvedDistance > 0)) {
    throw const PlanParseError('Could not determine a goal distance.');
  }

  final start = startDate != null && _isoDate.hasMatch(startDate)
      ? startDate
      : rows.first.scheduledDate;
  // create_training_plan refuses a workout outside the plan's window, so a
  // hand-written table dated before its own "Start date" line is refused
  // here, readably, rather than as a raw server code on create.
  if (rows.first.scheduledDate.compareTo(start) < 0) {
    throw PlanParseError(
      'The workout on ${rows.first.scheduledDate} is before the plan\'s start '
      'date, $start.',
    );
  }

  return ParsedPlan(
    name: name.isEmpty ? 'Imported plan' : name,
    goalEvent: goalEvent,
    goalDistanceM: resolvedDistance,
    goalTimeSec: goalTimeSec,
    startDate: start,
    generated: GeneratedPlan(
      weeks: weeks,
      paces: const TrainingPaces(
        easy: 0,
        marathon: 0,
        tempo: 0,
        interval: 0,
        repetition: 0,
      ),
      vdot: null,
      endDate: _localDate(rows.last.scheduledDate),
      goalDistanceM: resolvedDistance,
      pacesAreFallback: true,
    ),
  );
}

/// Parse a JSON export (web's `ExportPlan` shape) back into a plan. Routed
/// through the Markdown reader, as on web, so both formats share one
/// reconstruction and one set of validation errors.
ParsedPlan parsePlanJson(String text) {
  Object? obj;
  try {
    obj = jsonDecode(text);
  } on FormatException {
    throw const PlanParseError('Not valid JSON.');
  }
  if (obj is! Map<String, dynamic> || obj['workouts'] is! List) {
    throw const PlanParseError('JSON is missing a workouts array.');
  }
  final String markdown;
  try {
    markdown = _planToMarkdown(
      name: (obj['name'] as String?) ?? 'Imported plan',
      goalEvent: (obj['goalEvent'] as String?) ?? 'custom',
      goalDistanceM: (obj['goalDistanceM'] as num?) ?? 0,
      goalTimeSec: obj['goalTimeSec'] as num?,
      startDate: (obj['startDate'] as String?) ?? '',
      workouts: [
        for (final w in obj['workouts'] as List) w as Map<String, dynamic>,
      ],
    );
  } on TypeError {
    throw const PlanParseError('JSON workouts are not in the export shape.');
  }
  return _withTaperStamps(parsePlanMarkdown(markdown), [
    for (final w in obj['workouts'] as List) w as Map<String, dynamic>,
  ]);
}

final RegExp _taperStamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$');

/// The table drops `race_taper_applied_at`, so the JSON import lays each
/// workout's stamp back onto the parsed plan, matching the n-th workout of a
/// date and kind to the n-th the table produced (every sort on the way is
/// stable). Without it a tapered plan re-imported would be offered, and cut
/// by, the same taper again (decisions § 2063).
ParsedPlan _withTaperStamps(
    ParsedPlan parsed, List<Map<String, dynamic>> workouts) {
  final ordered = [...workouts];
  _stableSortBy(ordered, (w) => _str(w['scheduled_date']));
  final queues = <String, List<String?>>{};
  for (final w in ordered) {
    final raw = w['race_taper_applied_at'];
    if (raw != null && (raw is! String || !_taperStamp.hasMatch(raw))) {
      throw PlanParseError(
          'Couldn\'t read race_taper_applied_at "$raw" on ${w['scheduled_date']}.');
    }
    (queues['${w['scheduled_date']}|${w['kind']}'] ??= []).add(raw as String?);
  }
  String? next(String key) {
    final q = queues[key];
    return q == null || q.isEmpty ? null : q.removeAt(0);
  }

  final g = parsed.generated;
  return ParsedPlan(
    name: parsed.name,
    goalEvent: parsed.goalEvent,
    goalDistanceM: parsed.goalDistanceM,
    goalTimeSec: parsed.goalTimeSec,
    startDate: parsed.startDate,
    generated: GeneratedPlan(
      weeks: [
        for (final wk in g.weeks)
          GeneratedWeek(
            weekIndex: wk.weekIndex,
            phase: wk.phase,
            targetVolumeM: wk.targetVolumeM,
            notes: wk.notes,
            workouts: [
              for (final wo in wk.workouts)
                GeneratedWorkout(
                  scheduledDate: wo.scheduledDate,
                  kind: wo.kind,
                  targetDistanceM: wo.targetDistanceM,
                  targetDurationSeconds: wo.targetDurationSeconds,
                  targetPaceSecPerKm: wo.targetPaceSecPerKm,
                  targetPaceToleranceSec: wo.targetPaceToleranceSec,
                  structure: wo.structure,
                  notes: wo.notes,
                  raceName: wo.raceName,
                  racePriority: wo.racePriority,
                  raceTaperAppliedAt: next(
                      '${toIsoDate(wo.scheduledDate)}|${workoutKindDbValue(wo.kind)}'),
                ),
            ],
          ),
      ],
      paces: g.paces,
      vdot: g.vdot,
      endDate: g.endDate,
      goalDistanceM: g.goalDistanceM,
      pacesAreFallback: g.pacesAreFallback,
    ),
  );
}
