// The mobile plate-photo logger (decisions § 1972): nothing is saved until
// the runner saves, a removed item is not saved, an edit is, and a refusal
// shows its own message.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/offline_sync_store.dart' show SyncState;
import '../lib/plate_photo_client.dart';
import '../lib/screens/plate_photo_screen.dart';

class _FakeStore extends LocalFoodStore {
  final saved = <Map<String, Object?>>[];

  @override
  Future<StoredFood> createLocal({
    required DateTime startedAt,
    required String itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
    double? sugarG,
    double? sodiumMg,
    double? saturatedFatG,
    double? cholesterolMg,
    bool isPublic = false,
  }) async {
    saved.add({'item_name': itemName, 'meal_slot': mealSlot, 'calories': calories});
    return StoredFood(row: const {}, syncState: SyncState.pendingCreate, lastModifiedAt: DateTime.now());
  }
}

class _RecordingStore extends LocalFoodStore {
  final saved = <Map<String, Object?>>[];

  @override
  Future<StoredFood> createLocal({
    required DateTime startedAt,
    required String itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
    double? sugarG,
    double? sodiumMg,
    double? saturatedFatG,
    double? cholesterolMg,
    bool isPublic = false,
  }) async {
    saved.add({
      'started_at': startedAt,
      'item_name': itemName,
      'meal_slot': mealSlot,
      'protein_g': proteinG,
      'fiber_g': fiberG,
      'sodium_mg': sodiumMg,
    });
    return StoredFood(row: const {}, syncState: SyncState.pendingCreate, lastModifiedAt: DateTime.now());
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

Future<Uint8List?> _picker(_) async => Uint8List.fromList([1, 2, 3]);

void main() {
  testWidgets('estimate, remove one, edit one, save only what is kept', (tester) async {
    final store = _FakeStore();
    await _pump(
      tester,
      PlatePhotoForm(
        store: store,
        picker: _picker,
        estimator: (_, _) async => const PlateEstimate([
          PlateItem(itemName: 'Rice', calories: 205),
          PlateItem(itemName: 'Napkin', lowConfidence: true),
        ], 'dinner'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('plate-photo-gallery')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plate-photo-estimate')));
    await tester.pump();
    await tester.pump();
    expect(store.saved, isEmpty);

    await tester.tap(find.byTooltip('Remove Napkin'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '205'), '250');
    await tester.ensureVisible(find.byKey(const ValueKey('plate-photo-save')));
    await tester.tap(find.byKey(const ValueKey('plate-photo-save')));
    await tester.pump();
    await tester.pump();
    expect(store.saved, [
      {'item_name': 'Rice', 'meal_slot': 'dinner', 'calories': 250.0},
    ]);
  });

  testWidgets('a Pro refusal shows the Pro message and saves nothing', (tester) async {
    final store = _FakeStore();
    await _pump(
      tester,
      PlatePhotoForm(
        store: store,
        picker: _picker,
        estimator: (_, _) async => throw const PlatePhotoError(PlatePhotoErrorKind.proRequired),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('plate-photo-camera')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plate-photo-estimate')));
    await tester.pump();
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.platePhotoErrorPro), findsOneWidget);
    expect(store.saved, isEmpty);
  });

  testWidgets('a consent refusal points at Settings → Account, not the Coach', (tester) async {
    // The Coach only asks a runner with no record, so a stale acceptance sent
    // there finds nothing to accept; Settings → Account accepts from both.
    await _pump(
      tester,
      PlatePhotoForm(
        store: _FakeStore(),
        picker: _picker,
        estimator: (_, _) async => throw const PlatePhotoError(PlatePhotoErrorKind.consent),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('plate-photo-camera')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plate-photo-estimate')));
    await tester.pump();
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.platePhotoErrorConsent), findsOneWidget);
    expect(l10n.platePhotoErrorConsent, contains('Settings → Account'));
    expect(l10n.platePhotoErrorConsent, isNot(contains('Coach')));
  });

  testWidgets('estimate stays disabled until a picture is chosen', (tester) async {
    await _pump(tester, PlatePhotoForm(store: _FakeStore(), picker: (_) async => null));
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('plate-photo-estimate')));
    expect(button.onPressed, isNull);
  });

  testWidgets('a past diary day, the note and a changed slot reach every saved item', (tester) async {
    final store = _RecordingStore();
    final notes = <String>[];
    await _pump(
      tester,
      PlatePhotoForm(
        store: store,
        diaryDate: '2026-03-14',
        picker: _picker,
        estimator: (_, note) async {
          notes.add(note);
          return const PlateEstimate([
            PlateItem(itemName: 'Oats', proteinG: 10, fiberG: 8),
            PlateItem(itemName: 'Coffee', sodiumMg: 5),
          ], 'breakfast');
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('plate-photo-camera')));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Note (optional)'), 'large bowl');
    await tester.tap(find.byKey(const ValueKey('plate-photo-estimate')));
    await tester.pump();
    await tester.pump();
    expect(notes, ['large bowl']);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snack').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('plate-photo-save')));
    await tester.tap(find.byKey(const ValueKey('plate-photo-save')));
    await tester.pump();
    await tester.pump();

    expect(store.saved.map((r) => r['item_name']), ['Oats', 'Coffee']);
    for (final r in store.saved) {
      final at = r['started_at'] as DateTime;
      expect([at.year, at.month, at.day], [2026, 3, 14]);
      expect(r['meal_slot'], 'snack');
    }
    expect(store.saved.first['protein_g'], 10.0);
    expect(store.saved.first['fiber_g'], 8.0);
    expect(store.saved.last['sodium_mg'], 5.0);
  });

  testWidgets('an estimate with no food says so and offers nothing to save', (tester) async {
    final store = _FakeStore();
    await _pump(
      tester,
      PlatePhotoForm(
        store: store,
        picker: _picker,
        estimator: (_, _) async => const PlateEstimate([], null),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('plate-photo-gallery')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plate-photo-estimate')));
    await tester.pump();
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.platePhotoEmpty), findsOneWidget);
    expect(find.byKey(const ValueKey('plate-photo-save')), findsNothing);
    expect(store.saved, isEmpty);
  });
}
