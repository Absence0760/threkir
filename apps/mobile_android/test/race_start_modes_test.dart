import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/course_gates.dart';
import '../lib/race_start_modes.dart';

/// The Dart reader of `fixtures/race_start_modes_cases.json`, the case table
/// the `race_start_modes` pair shares with web's `race_start_modes.test.ts`.
final Map<String, dynamic> _fixture = jsonDecode(
        File('../../fixtures/race_start_modes_cases.json').readAsStringSync())
    as Map<String, dynamic>;

List<Map<String, dynamic>> _section(String name) =>
    (_fixture[name] as List).cast<Map<String, dynamic>>();

DateTime? _at(Object? v) => v == null ? null : DateTime.parse(v as String);

void main() {
  final serverNow = DateTime.parse(_fixture['serverNow'] as String);

  test('effectiveRaceStatus matches the fixture', () {
    for (final c in _section('effectiveStatus')) {
      final got = effectiveRaceStatus(
        StartModeSession(
          status: raceStatusFromWire(c['status'] as String)!,
          startMode: sessionStartModeFromWire(c['mode'] as String),
          scheduledStartAt: _at(c['scheduledStartAt']),
          windowOpensAt: _at(c['windowOpensAt']),
          windowClosesAt: _at(c['windowClosesAt']),
        ),
        serverNow,
      );
      expect(got.name, c['expected'], reason: c['note'] as String?);
    }
  });

  test('raceCountdownS matches the fixture', () {
    for (final c in _section('countdown')) {
      expect(
        raceCountdownS(_at(c['target']), _at(c['deviceNowMs'])!,
            c['serverOffsetMs'] as int),
        c['expected'],
        reason: c['note'] as String?,
      );
    }
  });

  test('voiceCountdownCue matches the fixture', () {
    for (final c in _section('voiceCue')) {
      expect(voiceCountdownCue(c['previous'] as int?, c['current'] as int?),
          c['expected'],
          reason: '${c['previous']} -> ${c['current']}');
    }
  });

  test('start offsets round-trip through the wall time', () {
    for (final c in _section('offsets')) {
      final local = LocalStartOffset(
          dayOffset: c['dayOffset'] as int,
          minuteOfDay: c['minuteOfDay'] as int);
      expect(startOffsetFromLocal(c['startMinuteOfDay'] as int, local),
          c['offsetS'],
          reason: c['note'] as String?);
      expect(
          localFromStartOffset(
              c['startMinuteOfDay'] as int, c['offsetS'] as int),
          local);
    }
  });

  test('selfTimedAttemptState matches the fixture', () {
    const wire = {
      SelfTimedAttemptState.notOpen: 'not_open',
      SelfTimedAttemptState.join: 'join',
      SelfTimedAttemptState.chooseCourse: 'choose_course',
      SelfTimedAttemptState.attempt: 'attempt',
      SelfTimedAttemptState.closed: 'closed',
    };
    for (final c in _section('attemptState')) {
      final got = selfTimedAttemptState(
        effectiveStatus: raceStatusFromWire(c['effectiveStatus'] as String)!,
        going: c['going'] as bool,
        courseCount: c['courseCount'] as int,
        courseChosen: c['courseChosen'] as bool,
      );
      expect(wire[got], c['expected'], reason: '$c');
    }
  });

  test('validateStartSettings matches the fixture', () {
    for (final c in _section('validate')) {
      expect(
        validateStartSettings(StartSettings(
          mode: sessionStartModeFromWire(c['mode'] as String),
          scheduledOffsetS: c['scheduledOffsetS'] as int?,
          windowOpenOffsetS: c['windowOpenOffsetS'] as int?,
          windowLengthS: c['windowLengthS'] as int?,
        )),
        (c['expected'] as List).cast<String>(),
        reason: '$c',
      );
    }
  });

  test('raceStartInstant is the scheduled GO or the window opening', () {
    final a = DateTime.utc(2026, 11, 8, 9);
    final b = DateTime.utc(2026, 11, 8, 10);
    expect(
        raceStartInstant(StartModeSession(
            status: RaceStatus.armed,
            startMode: SessionStartMode.scheduled,
            scheduledStartAt: a)),
        a);
    expect(
        raceStartInstant(StartModeSession(
            status: RaceStatus.armed,
            startMode: SessionStartMode.selfTimed,
            windowOpensAt: b)),
        b);
    expect(
        raceStartInstant(StartModeSession(
            status: RaceStatus.armed,
            startMode: SessionStartMode.hostGo,
            scheduledStartAt: a,
            windowOpensAt: b)),
        isNull);
  });

  test('sessionStartModeFromWire reads anything outside the CHECK as Host GO',
      () {
    expect(sessionStartModeFromWire('scheduled'), SessionStartMode.scheduled);
    expect(sessionStartModeFromWire('self_timed'), SessionStartMode.selfTimed);
    expect(sessionStartModeFromWire('host_go'), SessionStartMode.hostGo);
    expect(sessionStartModeFromWire(null), SessionStartMode.hostGo);
    expect(sessionStartModeFromWire('scheduled_go'), SessionStartMode.hostGo);
  });
}
