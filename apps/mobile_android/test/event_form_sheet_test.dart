import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/event_gym_template.dart';
import '../lib/social_service.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/event_form_sheet.dart';

/// Captures createEvent args (incl. the typed-event fields) + returns a
/// stub EventRow so the success path + field self-hiding can be asserted
/// end-to-end. [throwOnCreate] drives the failure-surface path.
class _CapturingSocialService extends SocialService {
  _CapturingSocialService({
    this.throwOnCreate,
    this.chargesEnabled = false,
    this.plans = const [],
    this.routines = const [],
    this.throwOnPricing,
  });
  final Object? throwOnCreate;
  final bool chargesEnabled;
  final List<({String id, String title})> plans;
  final List<({String id, String title})> routines;
  final Object? throwOnPricing;

  int? capturedCapacity;
  DateTime? capturedUntil;
  int? capturedCount;
  Map<String, Object?>? capturedPricing;
  String? capturedSessionPlanId;
  String? capturedGymRoutineId;
  String? routinesRequestedFor;

  @override
  Future<({bool chargesEnabled, String? defaultCurrency})?>
      fetchPayoutCapability() async =>
          (chargesEnabled: chargesEnabled, defaultCurrency: 'eur');

  @override
  Future<List<({String id, String title})>> fetchSessionPlanOptions() async =>
      plans;

  @override
  Future<void> setEventPricing({
    required String eventId,
    required int priceCents,
    required String currency,
    required String refundPolicy,
    required int salesCloseOffsetMinutes,
  }) async {
    capturedPricing = {
      'eventId': eventId,
      'priceCents': priceCents,
      'currency': currency,
      'refundPolicy': refundPolicy,
      'salesClose': salesCloseOffsetMinutes,
    };
    if (throwOnPricing != null) throw throwOnPricing!;
  }

  @override
  Future<void> setEventSessionPlan(String eventId, String? sessionPlanId) async {
    capturedSessionPlanId = sessionPlanId;
  }

  @override
  Future<List<({String id, String title})>> fetchClubGymRoutineOptions(
    String clubId,
  ) async {
    routinesRequestedFor = clubId;
    return routines;
  }

  @override
  Future<void> setEventGymRoutine(String eventId, String? gymRoutineId) async {
    capturedGymRoutineId = gymRoutineId;
  }

  bool createCalled = false;
  String? capturedTitle;
  String? capturedCategory;
  String? capturedDiscipline;
  double? capturedDistanceM;
  EventGymTemplate? capturedGymTemplate;
  String? capturedRecurrenceFreq;
  bool? capturedIsPublic;
  String? capturedTimezone;

  @override
  Future<EventRow> createEvent({
    required String clubId,
    required String title,
    required DateTime startsAt,
    String category = 'run',
    String? discipline,
    EventGymTemplate? gymTemplate,
    String? description,
    int? durationMin,
    String? meetLabel,
    double? meetLat,
    double? meetLng,
    String? routeId,
    double? distanceM,
    int? paceTargetSec,
    int? capacity,
    String? recurrenceFreq,
    List<String>? recurrenceByDay,
    DateTime? recurrenceUntil,
    int? recurrenceCount,
    bool isPublic = true,
    String? timezone,
  }) async {
    createCalled = true;
    capturedTimezone = timezone;
    capturedTitle = title;
    capturedCategory = category;
    capturedDiscipline = discipline;
    capturedDistanceM = distanceM;
    capturedGymTemplate = gymTemplate;
    capturedRecurrenceFreq = recurrenceFreq;
    capturedIsPublic = isPublic;
    capturedCapacity = capacity;
    capturedUntil = recurrenceUntil;
    capturedCount = recurrenceCount;
    if (throwOnCreate != null) throw throwOnCreate!;
    return EventRow(
      id: 'event-new',
      clubId: clubId,
      title: title,
      startsAt: startsAt,
      authorId: 'author-1',
      category: category,
      isPublic: isPublic,
      discipline: discipline,
    );
  }
}

class _Launcher extends StatefulWidget {
  final SocialService social;
  final bool clubIsPublic;
  final Future<String?> Function() deviceTimeZone;
  const _Launcher({
    required this.social,
    this.clubIsPublic = true,
    this.deviceTimeZone = _noZone,
  });

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  String? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                final r = await showEventFormSheet(
                  context,
                  social: widget.social,
                  clubId: 'club-1',
                  clubIsPublic: widget.clubIsPublic,
                  deviceTimeZone: widget.deviceTimeZone,
                );
                setState(() => _result = r ?? '<cancelled>');
              },
              child: const Text('Open'),
            ),
            if (_result != null) Text('result=$_result'),
          ],
        ),
      ),
    );
  }
}

Future<String?> _noZone() async => null;

Future<void> _openSheet(
  WidgetTester tester, {
  bool clubIsPublic = true,
  SocialService? social,
  Future<String?> Function() deviceTimeZone = _noZone,
}) async {
  // Larger viewport so the scrollable form actually paints all rows.
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Launcher(
          social: social ?? SocialService(),
          clubIsPublic: clubIsPublic,
          deviceTimeZone: deviceTimeZone)));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('showEventFormSheet', () {
    testWidgets('opens as a full-screen dialog with the New event heading',
        (tester) async {
      await _openSheet(tester);
      // Heading now lives in the host AppBar (full-screen dialog), not an
      // inline Text in a bottom sheet.
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('New event'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('renders the Title and Starts at fields', (tester) async {
      await _openSheet(tester);
      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
      // Starts-at is rendered with an InputDecorator (not a TextField)
      // because it opens a date/time picker on tap.
      expect(find.text('Starts at'), findsOneWidget);
    });

    testWidgets('shows the category picker with all four types as the first '
        'control', (tester) async {
      await _openSheet(tester);
      expect(find.text('Event type'), findsOneWidget);
      for (final label in ['Group run', 'Cycle', 'Class', 'Social']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
    });

    testWidgets('a run event shows the distance field and no discipline field',
        (tester) async {
      await _openSheet(tester);
      expect(find.widgetWithText(TextField, 'Distance (km)'), findsOneWidget);
      expect(find.text('Discipline'), findsNothing);
    });

    testWidgets('picking Class reveals the discipline field and hides the '
        'athletic distance field', (tester) async {
      await _openSheet(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Class'));
      await tester.pumpAndSettle();
      expect(find.text('Discipline'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Distance (km)'), findsNothing);
    });

    testWidgets('picking Social hides both the discipline and distance fields',
        (tester) async {
      await _openSheet(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Social'));
      await tester.pumpAndSettle();
      expect(find.text('Discipline'), findsNothing);
      expect(find.widgetWithText(TextField, 'Distance (km)'), findsNothing);
    });

    testWidgets('a public club shows the members-only toggle, defaulting off',
        (tester) async {
      await _openSheet(tester);
      final toggle = find.widgetWithText(SwitchListTile, 'Members only');
      expect(toggle, findsOneWidget);
      // Default is public → the members-only switch is off.
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      // It's interactive.
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    });

    testWidgets('a private club hides the members-only toggle', (tester) async {
      // A private club's events are already members-only via the club gate,
      // so the toggle is hidden there.
      await _openSheet(tester, clubIsPublic: false);
      expect(find.widgetWithText(SwitchListTile, 'Members only'), findsNothing);
    });
  });

  group('showEventFormSheet — submit', () {
    Future<void> tapCreate(WidgetTester tester) async {
      final btn = find.widgetWithText(FilledButton, 'Create event');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();
    }

    testWidgets('blank title → Create is a no-op (no createEvent call)',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tapCreate(tester);
      expect(fake.createCalled, isFalse);
    });

    testWidgets(
        'blank title flags the field inline; typing clears it; create then '
        'proceeds (issue #666 U6)', (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      final titleField = find.widgetWithText(TextField, 'Title');

      await tapCreate(tester);
      expect(tester.widget<TextField>(titleField).decoration?.errorText,
          'Give the event a title.');
      expect(fake.createCalled, isFalse);

      await tester.enterText(titleField, 'Saturday 5k');
      await tester.pump();
      expect(tester.widget<TextField>(titleField).decoration?.errorText,
          isNull);
      await tapCreate(tester);
      expect(fake.createCalled, isTrue);
      expect(find.text('result=ok'), findsOneWidget);
    });

    testWidgets('a run event submits distance in metres + run category',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Saturday 5k');
      await tester.enterText(
          find.widgetWithText(TextField, 'Distance (km)'), '5');
      await tapCreate(tester);
      expect(fake.createCalled, isTrue);
      expect(fake.capturedTitle, 'Saturday 5k');
      expect(fake.capturedCategory, 'run');
      // 5 km entered → 5000 m persisted.
      expect(fake.capturedDistanceM, 5000);
      expect(fake.capturedDiscipline, isNull);
      expect(fake.capturedGymTemplate, isNull);
      expect(find.text('result=ok'), findsOneWidget);
    });

    testWidgets(
        'a class event submits discipline + gym_template and drops distance',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Class'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Discipline'), 'Vinyasa Yoga');
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Morning flow');
      await tester.enterText(
          find.widgetWithText(TextField, 'Duration (min)'), '60');
      await tapCreate(tester);
      expect(fake.capturedCategory, 'class');
      expect(fake.capturedDiscipline, 'Vinyasa Yoga');
      // Athletic distance is not collected for a class.
      expect(fake.capturedDistanceM, isNull);
      expect(fake.capturedGymTemplate, isNotNull);
      expect(fake.capturedGymTemplate!.discipline, 'Vinyasa Yoga');
      expect(fake.capturedGymTemplate!.durationMin, 60);
    });

    testWidgets(
        'typing a distance then switching to Social clears it before submit',
        (tester) async {
      // The self-hiding contract: a distance typed under "run" must not
      // survive a switch to a non-athletic category.
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Distance (km)'), '10');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Social'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Pub night');
      await tapCreate(tester);
      expect(fake.capturedCategory, 'social');
      expect(fake.capturedDistanceM, isNull);
    });

    testWidgets('the event is stamped with the device zone it was picked in',
        (tester) async {
      // The picked date + time are the organiser's wall clock, and a series
      // stays on it only if the row says which zone that is. Without it a
      // mobile-created series expanded in every viewer's own zone.
      final fake = _CapturingSocialService();
      await _openSheet(
        tester,
        social: fake,
        deviceTimeZone: () async => 'America/New_York',
      );
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Wednesday night run');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Weekly'));
      await tester.pumpAndSettle();
      await tapCreate(tester);
      expect(fake.capturedTimezone, 'America/New_York');
    });

    testWidgets('a device that cannot name its zone sends none', (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Wednesday night run');
      await tapCreate(tester);
      expect(fake.createCalled, isTrue);
      expect(fake.capturedTimezone, isNull);
    });

    testWidgets('picking Weekly threads a weekly recurrence freq',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Tuesday tempo');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Weekly'));
      await tester.pumpAndSettle();
      await tapCreate(tester);
      expect(fake.capturedRecurrenceFreq, 'weekly');
    });

    testWidgets('toggling members-only on a public club submits isPublic=false',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Members run');
      final toggle = find.widgetWithText(SwitchListTile, 'Members only');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tapCreate(tester);
      expect(fake.capturedIsPublic, isFalse);
    });

    testWidgets('a failed create surfaces the error inline + does not pop',
        (tester) async {
      final fake =
          _CapturingSocialService(throwOnCreate: Exception('boom-create'));
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Doomed event');
      await tapCreate(tester);
      expect(fake.createCalled, isTrue);
      // Classified copy inline, never the raw exception (issue #240).
      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect(find.textContaining('boom-create'), findsNothing);
      // The sheet stays open (result not yet set on the launcher).
      expect(find.textContaining('result='), findsNothing);
    });
  });
  group('showEventFormSheet — capacity, series end, price, session plan', () {
    Future<void> tapCreate(WidgetTester tester) async {
      final btn = find.widgetWithText(FilledButton, 'Create event');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();
    }

    Future<void> enter(WidgetTester tester, Key key, String text) async {
      final field = find.byKey(key);
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
      await tester.pump();
    }

    testWidgets('a capacity is submitted; a capacity below 1 is refused inline',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Spin');
      await enter(tester, const Key('event-form-capacity'), '0');
      await tapCreate(tester);
      expect(fake.createCalled, isFalse);
      expect(find.text('Enter a whole number of 1 or more, or leave it empty.'),
          findsOneWidget);

      await enter(tester, const Key('event-form-capacity'), '12');
      await tapCreate(tester);
      expect(fake.capturedCapacity, 12);
      expect(find.text('result=ok'), findsOneWidget);
    });

    testWidgets('a series takes an occurrence count; a one-off sends none',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Tempo');
      expect(find.byKey(const Key('event-form-count')), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Weekly'));
      await tester.pumpAndSettle();
      await enter(tester, const Key('event-form-count'), '521');
      await tapCreate(tester);
      expect(fake.createCalled, isFalse);
      await enter(tester, const Key('event-form-count'), '8');
      await tapCreate(tester);
      expect(fake.capturedRecurrenceFreq, 'weekly');
      expect(fake.capturedCount, 8);
      expect(fake.capturedUntil, isNull);
    });

    testWidgets('a host who cannot take payments sees the charge toggle disabled',
        (tester) async {
      await _openSheet(tester, social: _CapturingSocialService());
      final toggle = find.byKey(const Key('event-form-charge'));
      await tester.ensureVisible(toggle);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      expect(find.text('Set up payouts on the web to charge for events.'),
          findsOneWidget);
      expect(find.byKey(const Key('event-form-price')), findsNothing);
    });

    testWidgets(
        'a charges-enabled host prices the event: validated, then written in '
        'minor units after the create', (tester) async {
      final fake = _CapturingSocialService(chargesEnabled: true);
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Reformer');
      final toggle = find.byKey(const Key('event-form-charge'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      // The account's settlement currency is the default.
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('event-form-currency')))
              .controller!
              .text,
          'eur');

      await enter(tester, const Key('event-form-price'), '0.40');
      await tapCreate(tester);
      expect(fake.createCalled, isFalse);
      expect(find.text('Enter a price of at least 0.50.'), findsOneWidget);

      await enter(tester, const Key('event-form-price'), '22,50');
      await tapCreate(tester);
      expect(fake.createCalled, isTrue);
      expect(fake.capturedPricing, {
        'eventId': 'event-new',
        'priceCents': 2250,
        'currency': 'eur',
        'refundPolicy': 'full_until_24h',
        'salesClose': 0,
      });
      expect(find.text('result=ok'), findsOneWidget);
    });

    testWidgets('a price that fails to save is reported, not retried',
        (tester) async {
      final fake = _CapturingSocialService(
          chargesEnabled: true, throwOnPricing: Exception('rls'));
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Reformer');
      final toggle = find.byKey(const Key('event-form-charge'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await enter(tester, const Key('event-form-price'), '22');
      await tapCreate(tester);
      expect(fake.createCalled, isTrue);
      expect(
          find.text('result=Event created, but saving the price failed. '
              'Set the price from the event on the web.'),
          findsOneWidget);
    });

    testWidgets('a class attaches the picked session plan after the create',
        (tester) async {
      final fake = _CapturingSocialService(
          plans: const [(id: 'plan-1', title: 'Hip openers')]);
      await _openSheet(tester, social: fake);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Class'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Flow');
      final picker = find.byKey(const Key('event-form-session-plan'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hip openers').last);
      await tester.pumpAndSettle();
      await tapCreate(tester);
      expect(fake.capturedSessionPlanId, 'plan-1');
      expect(find.text('result=ok'), findsOneWidget);
    });

    Future<void> pick(WidgetTester tester, Key key, String label) async {
      final picker = find.byKey(key);
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a class attaches the picked club routine after the create',
        (tester) async {
      final fake = _CapturingSocialService(
          routines: const [(id: 'routine-1', title: 'Lower Body')]);
      await _openSheet(tester, social: fake);
      expect(fake.routinesRequestedFor, 'club-1');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Class'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Strength');
      await pick(tester, const Key('event-form-gym-routine'), 'Lower Body');
      await tapCreate(tester);
      expect(fake.capturedGymRoutineId, 'routine-1');
      expect(fake.capturedSessionPlanId, isNull);
      expect(find.text('result=ok'), findsOneWidget);
    });

    testWidgets('picking a routine clears a picked session plan',
        (tester) async {
      final fake = _CapturingSocialService(
        plans: const [(id: 'plan-1', title: 'Hip openers')],
        routines: const [(id: 'routine-1', title: 'Lower Body')],
      );
      await _openSheet(tester, social: fake);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Class'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Strength');
      await pick(tester, const Key('event-form-session-plan'), 'Hip openers');
      await pick(tester, const Key('event-form-gym-routine'), 'Lower Body');
      await tapCreate(tester);
      expect(fake.capturedGymRoutineId, 'routine-1');
      expect(fake.capturedSessionPlanId, isNull);
    });

    testWidgets('a club with no routine templates says so under the picker',
        (tester) async {
      await _openSheet(tester, social: _CapturingSocialService());
      await tester.tap(find.widgetWithText(ChoiceChip, 'Class'));
      await tester.pumpAndSettle();
      expect(
        find.text(
            'This club has no routine templates yet. Publish a routine to the club first.'),
        findsOneWidget,
      );
    });
  });
}
