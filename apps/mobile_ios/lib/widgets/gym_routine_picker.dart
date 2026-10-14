import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The club routine-template dropdown a class can carry (decisions § 1869).
/// The event form and the event page's attach sheet both use it, so creating
/// a class and changing its routine afterwards offer the same list, labels and
/// "none" option.
class GymRoutinePicker extends StatelessWidget {
  final String? value;
  final List<({String id, String title})> routines;
  final ValueChanged<String?> onChanged;
  final Key? fieldKey;

  const GymRoutinePicker({
    super.key,
    required this.value,
    required this.routines,
    required this.onChanged,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A dropdown asserts its value is one of its items, so an id the list does
    // not carry (a failed options read) shows as "none" rather than crashing.
    final selected =
        routines.any((r) => r.id == value) ? value : null;
    // A dropdown reads initialValue once, so a value changed from outside
    // (the other content picker clearing this one) needs a rebuilt field.
    return KeyedSubtree(
      key: ValueKey('routine-${selected ?? ''}'),
      child: DropdownButtonFormField<String?>(
        key: fieldKey,
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.eventFormGymRoutine,
          helperText: routines.isEmpty
              ? l10n.eventFormGymRoutineEmpty
              : l10n.eventFormGymRoutineHint,
          helperMaxLines: 3,
        ),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(l10n.eventFormGymRoutineNone),
          ),
          for (final r in routines)
            DropdownMenuItem<String?>(
              value: r.id,
              child: Text(r.title, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
