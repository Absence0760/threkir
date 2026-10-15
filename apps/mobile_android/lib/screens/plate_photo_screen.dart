import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../diary_day.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_food_store.dart';
import '../nutrition_totals.dart' show mealSlots;
import '../plate_photo_client.dart';
import '../typed_decimal.dart';
import '../widgets/full_screen_form.dart';

/// Picks a picture. Returns null when the runner backs out.
typedef PlatePhotoPicker = Future<Uint8List?> Function(ImageSource source);

/// Turns a picture and a note into an estimate. Production is
/// [requestPlateEstimate]; tests inject a fake.
typedef PlatePhotoEstimator = Future<PlateEstimate> Function(
  Uint8List bytes,
  String note,
);

Future<Uint8List?> _defaultPicker(ImageSource source) async {
  final f = await ImagePicker().pickImage(
    source: source,
    maxWidth: kPlateUploadLongEdgePx,
    maxHeight: kPlateUploadLongEdgePx,
    imageQuality: kPlateUploadJpegQuality,
  );
  return f == null ? null : await f.readAsBytes();
}

/// Open the plate-photo logger. Resolves true when entries were saved.
Future<bool?> showPlatePhotoScreen({
  required BuildContext context,
  required LocalFoodStore store,
  String? diaryDate,
}) {
  final key = GlobalKey<PlatePhotoFormState>();
  return showFullScreenForm<bool>(
    context,
    title: AppLocalizations.of(context).platePhotoTitle,
    isDirty: () => key.currentState?.isDirty ?? false,
    builder: (_) => PlatePhotoForm(key: key, store: store, diaryDate: diaryDate),
  );
}

/// The mobile half of web's `PlatePhotoLogger.svelte` (decisions § 1972): a
/// camera-first way into the food diary, since the phone is where the plate
/// is. The picture goes to the vision model once; every proposed item is
/// shown for the runner to edit or remove, and only what they keep is written
/// through the offline-first food store.
class PlatePhotoForm extends StatefulWidget {
  final LocalFoodStore store;
  final String? diaryDate;
  final PlatePhotoPicker? picker;
  final PlatePhotoEstimator? estimator;

  const PlatePhotoForm({
    super.key,
    required this.store,
    this.diaryDate,
    this.picker,
    this.estimator,
  });

  @override
  State<PlatePhotoForm> createState() => PlatePhotoFormState();
}

class _Draft {
  final PlateItem source;
  final TextEditingController name;
  final TextEditingController calories;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;

  _Draft(this.source)
      : name = TextEditingController(text: source.itemName),
        calories = TextEditingController(text: _fmt(source.calories)),
        protein = TextEditingController(text: _fmt(source.proteinG)),
        carbs = TextEditingController(text: _fmt(source.carbsG)),
        fat = TextEditingController(text: _fmt(source.fatG));

  static String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  void dispose() {
    name.dispose();
    calories.dispose();
    protein.dispose();
    carbs.dispose();
    fat.dispose();
  }
}

class PlatePhotoFormState extends State<PlatePhotoForm> {
  Uint8List? _bytes;
  final _note = TextEditingController();
  bool _estimating = false;
  bool _saving = false;
  List<_Draft>? _drafts;
  String _mealSlot = 'lunch';
  PlatePhotoErrorKind? _error;
  String? _saveError;

  bool get isDirty => _bytes != null || (_drafts?.isNotEmpty ?? false);

  @override
  void dispose() {
    _note.dispose();
    for (final d in _drafts ?? const <_Draft>[]) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final bytes = await (widget.picker ?? _defaultPicker)(source);
      if (bytes == null || !mounted) return;
      setState(() {
        _bytes = bytes;
        _error = null;
        _saveError = null;
      });
    } catch (e) {
      debugPrint('plate_photo_screen: picker failed: $e');
      if (mounted) setState(() => _error = PlatePhotoErrorKind.invalid);
    }
  }

  Future<void> _estimate() async {
    final bytes = _bytes;
    if (bytes == null || _estimating) return;
    setState(() {
      _estimating = true;
      _error = null;
    });
    try {
      final result = await (widget.estimator ?? requestPlateEstimate)(bytes, _note.text);
      if (!mounted) return;
      setState(() {
        _drafts = [for (final i in result.items) _Draft(i)];
        if (result.mealSlot != null) _mealSlot = result.mealSlot!;
      });
    } on PlatePhotoError catch (e) {
      if (mounted) setState(() => _error = e.kind);
    } catch (e) {
      debugPrint('plate_photo_screen: estimate failed: $e');
      if (mounted) setState(() => _error = PlatePhotoErrorKind.unavailable);
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  double? _parse(TextEditingController c) {
    final v = parseTypedDecimal(c.text);
    if (v == null || !v.isFinite || v < 0) return null;
    return v;
  }

  Future<void> _save() async {
    final keep = [
      for (final d in _drafts ?? const <_Draft>[])
        if (d.name.text.trim().isNotEmpty) d,
    ];
    if (keep.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final day = widget.diaryDate;
    try {
      for (final d in keep) {
        await widget.store.createLocal(
          startedAt: day == null ? DateTime.now() : entryTimestampFor(day, DateTime.now()),
          itemName: d.name.text.trim(),
          mealSlot: _mealSlot,
          calories: _parse(d.calories),
          proteinG: _parse(d.protein),
          carbsG: _parse(d.carbs),
          fatG: _parse(d.fat),
          fiberG: d.source.fiberG,
          sugarG: d.source.sugarG,
          sodiumMg: d.source.sodiumMg,
          saturatedFatG: d.source.saturatedFatG,
          cholesterolMg: d.source.cholesterolMg,
        );
        if (!mounted) return;
        setState(() => _drafts = [..._drafts!]..remove(d));
        d.dispose();
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('plate_photo_screen: save failed: $e');
      if (mounted) {
        setState(() => _saveError = AppLocalizations.of(context).nutritionSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorText(AppLocalizations l10n, PlatePhotoErrorKind kind) => switch (kind) {
        PlatePhotoErrorKind.consent => l10n.platePhotoErrorConsent,
        PlatePhotoErrorKind.proRequired => l10n.platePhotoErrorPro,
        PlatePhotoErrorKind.rateLimited => l10n.platePhotoErrorRate,
        PlatePhotoErrorKind.invalid => l10n.platePhotoErrorInvalid,
        PlatePhotoErrorKind.notUnderstood => l10n.platePhotoErrorNotUnderstood,
        PlatePhotoErrorKind.notAuthenticated ||
        PlatePhotoErrorKind.unavailable =>
          l10n.platePhotoErrorUnavailable,
      };

  String _slotLabel(AppLocalizations l10n, String slot) => switch (slot) {
        'breakfast' => l10n.nutritionSlotBreakfast,
        'lunch' => l10n.nutritionSlotLunch,
        'dinner' => l10n.nutritionSlotDinner,
        _ => l10n.nutritionSlotSnack,
      };

  Widget _num(String label, TextEditingController c) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final drafts = _drafts;
    return FullScreenFormBody(
      children: [
        Text(l10n.platePhotoIntro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        if (drafts == null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('plate-photo-camera'),
                onPressed: _estimating ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.platePhotoTakePhoto),
              ),
              OutlinedButton.icon(
                key: const ValueKey('plate-photo-gallery'),
                onPressed: _estimating ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.platePhotoChoosePhoto),
              ),
            ],
          ),
          if (_bytes != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _bytes!,
                height: 180,
                fit: BoxFit.cover,
                semanticLabel: l10n.platePhotoPreviewLabel,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: kMaxPlateNoteChars,
            decoration: InputDecoration(
              labelText: l10n.platePhotoNoteLabel,
              hintText: l10n.platePhotoNoteHint,
            ),
          ),
          FilledButton(
            key: const ValueKey('plate-photo-estimate'),
            onPressed: _bytes == null || _estimating ? null : _estimate,
            child: Text(_estimating ? l10n.platePhotoEstimating : l10n.platePhotoEstimate),
          ),
        ] else if (drafts.isEmpty) ...[
          Text(l10n.platePhotoEmpty),
        ] else ...[
          Text(l10n.platePhotoReviewHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.platePhotoReviewHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _mealSlot,
            decoration: InputDecoration(labelText: l10n.platePhotoMealSlot),
            items: [
              for (final s in mealSlots)
                DropdownMenuItem(value: s, child: Text(_slotLabel(l10n, s))),
            ],
            onChanged: (v) => setState(() => _mealSlot = v ?? _mealSlot),
          ),
          const SizedBox(height: 12),
          for (final d in drafts)
            Card(
              key: ObjectKey(d),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: d.name,
                            decoration: InputDecoration(labelText: l10n.platePhotoItemName),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.platePhotoRemoveItem(d.name.text),
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _drafts = [...drafts]..remove(d);
                            d.dispose();
                          }),
                        ),
                      ],
                    ),
                    if (d.source.lowConfidence)
                      Text(l10n.platePhotoLowConfidence, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _num(l10n.platePhotoCalories, d.calories),
                        const SizedBox(width: 8),
                        _num(l10n.platePhotoProtein, d.protein),
                      ],
                    ),
                    Row(
                      children: [
                        _num(l10n.platePhotoCarbs, d.carbs),
                        const SizedBox(width: 8),
                        _num(l10n.platePhotoFat, d.fat),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('plate-photo-save'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? l10n.platePhotoSaving : l10n.platePhotoSave(drafts.length)),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorText(l10n, _error!),
            key: const ValueKey('plate-photo-error'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(_saveError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
