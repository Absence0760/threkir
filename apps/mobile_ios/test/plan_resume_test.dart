// Twin of apps/web/src/lib/training/plan_resume.test.ts — same cases.

import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_resume.dart';

ResumeShift? _shift(String? pausedOn, String today) => resumeShift(
    startIso: '2026-06-01', pausedOnIso: pausedOn, todayIso: today, weekCount: 12);

void main() {
  test('paused in week 2, resumed three weeks later: weeks 3 on move back three weeks',
      () {
    expect(_shift('2026-06-17', '2026-07-08'),
        const ResumeShift(fromWeekIndex: 3, weeks: 3));
  });

  test('paused and resumed inside the same plan week offers nothing', () {
    expect(_shift('2026-06-15', '2026-06-20'), isNull);
  });

  test('resumed in the very next plan week moves the rest back one week', () {
    expect(_shift('2026-06-20', '2026-06-22'),
        const ResumeShift(fromWeekIndex: 3, weeks: 1));
  });

  test('a pause before the plan started, or an unknown pause date, offers nothing',
      () {
    expect(_shift('2026-05-20', '2026-06-22'), isNull);
    expect(_shift(null, '2026-06-22'), isNull);
  });

  test('a pause in the last week has no later week to move', () {
    expect(_shift('2026-08-18', '2026-09-15'), isNull);
  });

  test('a very long pause is capped at 52 weeks', () {
    expect(_shift('2026-06-02', '2028-06-02'),
        const ResumeShift(fromWeekIndex: 1, weeks: 52));
  });

  test('an unreadable date offers nothing rather than reading as week 0', () {
    expect(_shift('not-a-date', '2026-07-08'), isNull);
  });
}
