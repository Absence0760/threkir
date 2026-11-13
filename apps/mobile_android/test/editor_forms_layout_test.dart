// Each of the ten showFullScreenForm editors, opened the way the app opens
// it, keeps its one primary action on screen and tappable on a 320 dp phone
// at 2.0x text with a 3-button nav bar, with and without the keyboard up
// (issue #1374 TO-7, IK-11). The layout itself is EditorPage's, pinned in
// packages/ui_kit/test/editor_page_test.dart; this pins that every form
// hands it a Save and that no form's own fields break the page around it.

import 'dart:io';

import 'package:core_models/core_models.dart' show PlanWorkoutRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/local_food_store.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_routine_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/plate_photo_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/challenge_form_sheet.dart';
import '../lib/widgets/club_form_sheet.dart';
import '../lib/widgets/event_form_sheet.dart';
import '../lib/widgets/gear_form_sheet.dart';
import '../lib/widgets/goal_editor_sheet.dart';
import '../lib/widgets/gym_compose_sheet.dart';
import '../lib/widgets/nutrition_log_sheet.dart';
import '../lib/widgets/routine_builder_sheet.dart';
import '../lib/widgets/workout_edit_sheet.dart';
import 'editor_layout.dart';

class _ReadySocial extends SocialService {
  @override
  bool get isReady => true;
}

Directory _dir(String tag) {
  final dir = Directory.systemTemp.createTempSync('editor_layout_$tag');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Finder _filled(String label) => find.widgetWithText(FilledButton, label);

void main() {
  late Preferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = Preferences();
    await prefs.init();
  });

  testWidgets('gear', (tester) async {
    final store = LocalGearStore();
    await store.init(overrideDirectory: _dir('gear'));
    await expectEditorSaveReachable(
      tester,
      open: (context) => showGearFormSheet(
          context: context, store: store, preferences: prefs, kind: 'shoe'),
      save: _filled('Add'),
    );
  });

  testWidgets('club', (tester) async {
    await expectEditorSaveReachable(
      tester,
      open: (context) => showClubFormSheet(context, social: _ReadySocial()),
      save: _filled('Create'),
    );
  });

  testWidgets('event', (tester) async {
    await expectEditorSaveReachable(
      tester,
      open: (context) => showEventFormSheet(context,
          social: _ReadySocial(),
          clubId: 'c1',
          deviceTimeZone: () async => 'UTC'),
      save: _filled('Create event'),
    );
  });

  testWidgets('challenge', (tester) async {
    await expectEditorSaveReachable(
      tester,
      open: (context) =>
          showChallengeFormSheet(context, social: _ReadySocial()),
      save: _filled('Create challenge'),
    );
  });

  testWidgets('goal', (tester) async {
    await expectEditorSaveReachable(
      tester,
      open: (context) => showGoalEditorSheet(context, preferences: prefs),
      save: _filled('Save'),
    );
  });

  testWidgets('gym compose', (tester) async {
    final store = LocalGymStore();
    await store.init(overrideDirectory: _dir('gym'));
    await expectEditorSaveReachable(
      tester,
      open: (context) => showGymComposeSheet(context: context, store: store),
      save: _filled('Save workout'),
    );
  });

  testWidgets('routine builder', (tester) async {
    final store = LocalRoutineStore();
    await store.init(overrideDirectory: _dir('routine'));
    await expectEditorSaveReachable(
      tester,
      open: (context) =>
          showRoutineBuilderSheet(context: context, store: store),
      save: _filled('Save routine'),
    );
  });

  testWidgets('planned workout edit', (tester) async {
    await expectEditorSaveReachable(
      tester,
      open: (context) => showWorkoutEditSheet(
        context,
        workout: PlanWorkoutRow(
          id: 'wo1',
          weekId: 'wk1',
          scheduledDate: DateTime(2026, 4, 25),
          kind: 'tempo',
          targetDistanceM: 8000,
          targetPaceSecPerKm: 300,
          manuallyCompleted: false,
        ),
        training: TrainingService(),
        hrPrescription: false,
      ),
      save: _filled('Save'),
    );
  });

  testWidgets('nutrition manual entry', (tester) async {
    final store = LocalFoodStore();
    await store.init(overrideDirectory: _dir('food'));
    await expectEditorSaveReachable(
      tester,
      open: (context) => showNutritionLogSheet(context: context, store: store),
      settle: () async {
        await tester.ensureVisible(find.text('Enter manually'));
        await tester.tap(find.text('Enter manually'));
        await tester.pump();
      },
      save: _filled('Add'),
    );
  });

  testWidgets('plate photo', (tester) async {
    final store = LocalFoodStore();
    await store.init(overrideDirectory: _dir('plate'));
    await expectEditorSaveReachable(
      tester,
      open: (context) => showPlatePhotoScreen(context: context, store: store),
      save: find.byKey(const ValueKey('plate-photo-estimate')),
    );
  });
}
