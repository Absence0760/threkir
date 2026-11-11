// Widget tests for "Report a problem with this course" (issue #1346,
// decisions § 2449 + § 2469): the reasons the sheet offers, the limits it
// holds the fields to, the contact email a rights holder's request needs, the
// payload a filing sends and the copy each refusal of the
// `park-course-report` Edge Function gets.

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/park_course_report.dart';
import '../lib/widgets/park_course_report_sheet.dart';

class _FakeApiClient extends ApiClient {
  final calls = <Map<String, Object?>>[];
  Object? errorToThrow;
  Completer<void>? gate;

  @override
  Future<void> submitParkCourseReport({
    required String courseId,
    required String reason,
    required String notes,
    String? contactEmail,
  }) async {
    calls.add({
      'courseId': courseId,
      'reason': reason,
      'notes': notes,
      'contactEmail': contactEmail,
    });
    if (gate != null) await gate!.future;
    if (errorToThrow != null) throw errorToThrow!;
  }
}

final _l10n = AppLocalizationsEn();

final _notes = find.byKey(const Key('park-course-report-notes'));
final _email = find.byKey(const Key('park-course-report-email'));
final _submit = find.byKey(const Key('park-course-report-submit'));
final _error = find.byKey(const Key('park-course-report-error'));

Future<void> _openSheet(WidgetTester tester, _FakeApiClient api) async {
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showParkCourseReportSheet(
                context,
                api: api,
                courseId: 'course-1',
                courseName: 'Swift Creek 5K',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('park-course-report-sheet')), findsOneWidget);
}

Future<void> _pickReason(WidgetTester tester, String reason) async {
  await tester.tap(find.byKey(Key('park-course-report-reason-$reason')));
  await tester.pump();
}

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_submit).onPressed != null;

InputDecoration _emailDecoration(WidgetTester tester) => tester
    .widget<TextField>(
      _email,
    )
    .decoration!;

void main() {
  testWidgets('every reason is offered, in order, the first one picked',
      (tester) async {
    await _openSheet(tester, _FakeApiClient());
    expect(kCourseReportReasons, [
      'course_hazard',
      'course_closure',
      'course_off_trail',
      'land_manager_request',
      'rights_holder_request',
      'other',
    ]);
    final labels = {
      'course_hazard': _l10n.parkCourseReportReasonHazard,
      'course_closure': _l10n.parkCourseReportReasonClosure,
      'course_off_trail': _l10n.parkCourseReportReasonOffTrail,
      'land_manager_request': _l10n.parkCourseReportReasonLandManager,
      'rights_holder_request': _l10n.parkCourseReportReasonRightsHolder,
      'other': _l10n.parkCourseReportReasonOther,
    };
    double? lastY;
    for (final reason in kCourseReportReasons) {
      final tile = find.byKey(Key('park-course-report-reason-$reason'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text(labels[reason]!)),
        findsOneWidget,
      );
      final y = tester.getTopLeft(tile).dy;
      if (lastY != null) expect(y, greaterThan(lastY));
      lastY = y;
    }
    expect(find.text(_l10n.parkCourseReportReasonLandManagerHint),
        findsOneWidget);
    expect(find.text(_l10n.parkCourseReportReasonRightsHolderHint),
        findsOneWidget);
    final first = tester.widget<RadioListTile<String>>(
      find.byKey(const Key('park-course-report-reason-course_hazard')),
    );
    expect(first.groupValue, 'course_hazard');
  });

  testWidgets('the notes and email fields carry the server limits',
      (tester) async {
    await _openSheet(tester, _FakeApiClient());
    final notes = tester.widget<TextField>(
      _notes,
    );
    final email = tester.widget<TextField>(
      _email,
    );
    expect(notes.maxLength, kCourseReportNotesMax);
    expect(kCourseReportNotesMax, 1000);
    expect(email.maxLength, kCourseReportEmailMax);
    expect(kCourseReportEmailMax, 254);

    await tester.enterText(_notes, 'x' * (kCourseReportNotesMax + 50));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            _notes,
          )
          .controller!
          .text
          .length,
      kCourseReportNotesMax,
    );
  });

  testWidgets('Send stays disabled until a note is written', (tester) async {
    await _openSheet(tester, _FakeApiClient());
    expect(_submitEnabled(tester), isFalse);
    await tester.enterText(_notes, '   ');
    await tester.pump();
    expect(_submitEnabled(tester), isFalse);
    await tester.enterText(_notes, 'A fallen tree at the second bridge');
    await tester.pump();
    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('the email is optional for every reason but a rights holder',
      (tester) async {
    await _openSheet(tester, _FakeApiClient());
    await tester.enterText(_notes, 'Something to say');
    await tester.pump();
    for (final reason in kCourseReportReasons) {
      if (reason == 'rights_holder_request') continue;
      await _pickReason(tester, reason);
      expect(_submitEnabled(tester), isTrue, reason: reason);
      expect(_emailDecoration(tester).labelText,
          _l10n.parkCourseReportEmailLabel);
      expect(_emailDecoration(tester).helperText,
          _l10n.parkCourseReportEmailHint);
    }
  });

  testWidgets(
      'a rights-holder request needs a valid email: Send waits for one and '
      'the field says why', (tester) async {
    await _openSheet(tester, _FakeApiClient());
    await tester.enterText(_notes, 'The course name is our trade mark');
    await _pickReason(tester, 'rights_holder_request');

    expect(_submitEnabled(tester), isFalse);
    var deco = _emailDecoration(tester);
    expect(deco.labelText, _l10n.parkCourseReportEmailLabelRequired);
    // Empty is not yet a mistake: the helper says what the address is for.
    expect(deco.helperText, _l10n.parkCourseReportEmailHintRequired);
    expect(deco.errorText, isNull);
    expect(find.text(_l10n.parkCourseReportEmailHintRequired), findsOneWidget);

    await tester.enterText(_email, 'not-an-address');
    await tester.pump();
    expect(_submitEnabled(tester), isFalse);
    deco = _emailDecoration(tester);
    expect(deco.errorText, _l10n.parkCourseReportErrorEmail);
    expect(deco.helperText, isNull);

    await tester.enterText(_email, 'legal@example.com');
    await tester.pump();
    expect(_submitEnabled(tester), isTrue);
    expect(_emailDecoration(tester).errorText, isNull);

    // Switching away makes the address optional again; back makes it needed.
    await tester.enterText(_email, '');
    await _pickReason(tester, 'other');
    expect(_submitEnabled(tester), isTrue);
    await _pickReason(tester, 'rights_holder_request');
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets('a malformed optional email still blocks Send', (tester) async {
    await _openSheet(tester, _FakeApiClient());
    await tester.enterText(_notes, 'A closure');
    await tester.enterText(_email, 'me@nowhere');
    await tester.pump();
    expect(_submitEnabled(tester), isFalse);
    expect(_emailDecoration(tester).errorText, _l10n.parkCourseReportErrorEmail);
  });

  testWidgets(
      'a filing sends the course, reason, note and email, then closes and '
      'thanks the runner', (tester) async {
    final api = _FakeApiClient();
    await _openSheet(tester, api);
    await _pickReason(tester, 'rights_holder_request');
    await tester.enterText(_notes, '  Our course data, used without leave  ');
    await tester.enterText(_email, 'legal@example.com');
    await tester.pump();
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(api.calls, [
      {
        'courseId': 'course-1',
        'reason': 'rights_holder_request',
        'notes': '  Our course data, used without leave  ',
        'contactEmail': 'legal@example.com',
      },
    ]);
    expect(find.byKey(const Key('park-course-report-sheet')), findsNothing);
    expect(find.text(_l10n.parkCourseReportSent), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a second tap while a filing is in flight sends nothing more',
      (tester) async {
    final api = _FakeApiClient()..gate = Completer<void>();
    await _openSheet(tester, api);
    await tester.enterText(_notes, 'A hazard');
    await tester.pump();
    await tester.tap(_submit);
    await tester.pump();
    expect(_submitEnabled(tester), isFalse);
    expect(
      find.descendant(
          of: _submit, matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    await tester.tap(_submit, warnIfMissed: false);
    await tester.pump();
    expect(api.calls, hasLength(1));
    api.gate!.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
  });

  final refusals = <String, (Object, String Function())>{
    'already reported': (
      const FunctionException(
          status: 409, details: {'error': 'already_reported'}),
      () => _l10n.parkCourseReportErrorAlreadyReported,
    ),
    'rate limited': (
      const FunctionException(status: 429, details: {'error': 'rate_limited'}),
      () => _l10n.parkCourseReportErrorRateLimited,
    ),
    'email required': (
      const FunctionException(
          status: 400, details: {'error': 'email_required'}),
      () => _l10n.parkCourseReportErrorEmailRequired,
    ),
    'invalid email': (
      const FunctionException(status: 400, details: {'error': 'invalid_email'}),
      () => _l10n.parkCourseReportErrorEmail,
    ),
    'course gone': (
      const FunctionException(
          status: 404, details: {'error': 'course_not_found'}),
      () => _l10n.parkCourseReportErrorNotFound,
    ),
    'invalid report': (
      const FunctionException(status: 400, details: {'error': 'notes_too_long'}),
      () => _l10n.parkCourseReportErrorInvalid,
    ),
    'unknown code': (
      const FunctionException(status: 500, details: {'error': 'boom'}),
      () => _l10n.parkCourseReportErrorFailed,
    ),
    'offline': (
      Exception('SocketException: Failed host lookup'),
      () => _l10n.parkCourseReportErrorFailed,
    ),
  };

  for (final MapEntry(key: name, value: (error, copy)) in refusals.entries) {
    testWidgets('a refusal ($name) keeps the sheet and the text up with its '
        'own message', (tester) async {
      final api = _FakeApiClient()..errorToThrow = error;
      await _openSheet(tester, api);
      await tester.enterText(_notes, 'A washed-out bridge');
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(api.calls, hasLength(1));
      expect(find.byKey(const Key('park-course-report-sheet')), findsOneWidget);
      expect(_error, findsOneWidget);
      expect(tester.widget<Text>(_error).data, copy());
      expect(find.text('A washed-out bridge'), findsOneWidget);
      expect(_submitEnabled(tester), isTrue);
    });
  }

  test('each refusal code maps to its own wording', () {
    expect(
      {
        for (final code in [
          'rate_limited',
          'rate_limit_exceeded',
          'rate_limit_unavailable',
          'already_reported',
          'course_not_found',
          'invalid_email',
          'email_required',
          'notes_required',
          'invalid_reason',
        ])
          code: courseReportRefusal({'error': code}),
      },
      {
        'rate_limited': CourseReportRefusal.rateLimited,
        'rate_limit_exceeded': CourseReportRefusal.rateLimited,
        'rate_limit_unavailable': CourseReportRefusal.rateLimited,
        'already_reported': CourseReportRefusal.alreadyReported,
        'course_not_found': CourseReportRefusal.notFound,
        'invalid_email': CourseReportRefusal.invalidEmail,
        'email_required': CourseReportRefusal.emailRequired,
        'notes_required': CourseReportRefusal.invalid,
        'invalid_reason': CourseReportRefusal.invalid,
      },
    );
    expect(courseReportRefusal(null), CourseReportRefusal.failed);
    expect(courseReportRefusal('already_reported'), CourseReportRefusal.failed);
  });

  test('the email check: required only for a rights holder, shape and length',
      () {
    expect(courseReportEmailRequired('rights_holder_request'), isTrue);
    for (final r in kCourseReportReasons.where((r) => r != 'rights_holder_request')) {
      expect(courseReportEmailRequired(r), isFalse, reason: r);
    }
    expect(courseReportEmailOk('', reason: 'rights_holder_request'), isFalse);
    expect(courseReportEmailOk('  ', reason: 'other'), isTrue);
    expect(courseReportEmailOk(''), isTrue);
    expect(courseReportEmailOk(' a@b.co '), isTrue);
    expect(courseReportEmailOk('a b@c.co'), isFalse);
    final local = 'a' * (kCourseReportEmailMax - '@b.co'.length);
    expect(courseReportEmailOk('$local@b.co'), isTrue);
    expect(courseReportEmailOk('a$local@b.co'), isFalse);
  });
}
