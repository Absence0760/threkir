import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The session-plan dropdown a class can carry (session_planner.md P1). The
/// event form and the event page's attach sheet both use it, so creating a
/// class and changing its plan afterwards offer the same list, labels and
/// "none" option.
class SessionPlanPicker extends StatelessWidget {
  final String? value;
  final List<({String id, String title})> plans;
  final ValueChanged<String?> onChanged;
  final Key? fieldKey;

  const SessionPlanPicker({
    super.key,
    required this.value,
    required this.plans,
    required this.onChanged,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A dropdown asserts its value is one of its items, so an id the list does
    // not carry (a failed options read) shows as "none" rather than crashing.
    final selected = plans.any((p) => p.id == value) ? value : null;
    // A dropdown reads initialValue once, so a value changed from outside
    // (the other content picker clearing this one) needs a rebuilt field.
    return KeyedSubtree(
      key: ValueKey('plan-${selected ?? ''}'),
      child: DropdownButtonFormField<String?>(
        key: fieldKey,
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.eventFormSessionPlan,
          helperText: plans.isEmpty ? l10n.eventFormSessionPlanEmpty : null,
        ),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(l10n.eventFormSessionPlanNone),
          ),
          for (final p in plans)
            DropdownMenuItem<String?>(
              value: p.id,
              child: Text(p.title, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
