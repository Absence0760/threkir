import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show SheetScaffold;

import '../l10n/gen/app_localizations.dart';
import '../race_phases.dart';
import 'form_sheet.dart';

/// What the race-strategy sheet was confirmed with: the preset and the two
/// fields as typed, which the run screen parses.
typedef RaceStrategyChoice = ({
  RacePhasePreset? preset,
  String distance,
  String goal,
});

/// The pre-run race-strategy sheet: pick a phase preset, confirm the race
/// distance (prefilled from the selected route), optionally set a goal time
/// so the phases carry target paces. Null when the runner backs out.
Future<RaceStrategyChoice?> showRaceStrategySheet(
  BuildContext context, {
  required RacePhasePreset? preset,
  required String distance,
  required String goal,
  required bool miles,
}) => showFormSheet<RaceStrategyChoice>(
  context,
  builder: (_) => _RaceStrategySheet(
    preset: preset,
    distance: distance,
    goal: goal,
    miles: miles,
  ),
);

class _RaceStrategySheet extends StatefulWidget {
  const _RaceStrategySheet({
    required this.preset,
    required this.distance,
    required this.goal,
    required this.miles,
  });

  final RacePhasePreset? preset;
  final String distance;
  final String goal;
  final bool miles;

  @override
  State<_RaceStrategySheet> createState() => _RaceStrategySheetState();
}

class _RaceStrategySheetState extends State<_RaceStrategySheet> {
  // The sheet owns its fields, so they outlive the slide-out that still
  // draws them after the result is returned.
  late final _distance = TextEditingController(text: widget.distance);
  late final _goal = TextEditingController(text: widget.goal);
  late RacePhasePreset? _preset = widget.preset;
  late final FieldSnapshot _start;

  @override
  void initState() {
    super.initState();
    _start = FieldSnapshot([_distance, _goal]);
  }

  @override
  void dispose() {
    _distance.dispose();
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    RadioListTile<RacePhasePreset?> option(
      RacePhasePreset? value,
      String title, [
      String? hint,
    ]) => RadioListTile<RacePhasePreset?>(
      value: value,
      groupValue: _preset,
      title: Text(title),
      subtitle: hint == null ? null : Text(hint),
      onChanged: (v) => setState(() => _preset = v),
    );
    return SheetDiscardGuard(
      isDirty: () => _start.changed || _preset != widget.preset,
      child: SheetScaffold(
        title: Text(l10n.runRaceStrategy),
        actions: Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('race-strategy-ok'),
            onPressed: () => Navigator.pop(context, (
              preset: _preset,
              distance: _distance.text,
              goal: _goal.text,
            )),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            option(null, l10n.runStrategyNone),
            option(
              RacePhasePreset.tenTenTen,
              l10n.runStrategyTenTenTen,
              l10n.runStrategyTenTenTenHint,
            ),
            option(
              RacePhasePreset.negativeSplit,
              l10n.runStrategyNegativeSplit,
              l10n.runStrategyNegativeSplitHint,
            ),
            option(
              RacePhasePreset.even,
              l10n.runStrategyEven,
              l10n.runStrategyEvenHint,
            ),
            if (_preset != null) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('race-strategy-distance'),
                controller: _distance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.runStrategyDistance,
                  suffixText: widget.miles ? 'mi' : 'km',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('race-strategy-goal'),
                controller: _goal,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: l10n.runStrategyGoalTime,
                  hintText: 'hh:mm:ss',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
