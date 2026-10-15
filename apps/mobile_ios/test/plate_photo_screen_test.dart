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

  testWidgets('estimate stays disabled until a picture is chosen', (tester) async {
    await _pump(tester, PlatePhotoForm(store: _FakeStore(), picker: (_) async => null));
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('plate-photo-estimate')));
    expect(button.onPressed, isNull);
  });
}
