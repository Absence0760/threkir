import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/gen/app_localizations.dart';

/// The one typed-duration surface shared by Add run and the run-detail edit
/// dialog, over the `run_duration` parity pair (decisions § 2359). Both forms
/// used to carry their own copy of a parser that only refused a zero total,
/// which is how "12333" in the Hours box became a 12,333-hour run.

/// Digits only, and no wider than the box ever needs: three for hours (the
/// whole ten-day bound is 240 h), two for minutes and seconds.
List<TextInputFormatter> durationBoxFormatters({required bool hours}) => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(
          hours ? kHoursMaxDigits : kMinutesSecondsMaxDigits),
    ];

String manualDurationErrorText(
  AppLocalizations l10n,
  ManualDurationError error,
) =>
    switch (error) {
      ManualDurationError.invalid => l10n.manualDurationErrorInvalid,
      ManualDurationError.minutesOutOfRange => l10n.manualDurationErrorMinutes,
      ManualDurationError.secondsOutOfRange => l10n.manualDurationErrorSeconds,
      ManualDurationError.zero => l10n.addRunDurationInvalid,
      ManualDurationError.tooLong =>
        l10n.manualDurationErrorTooLong(kMaxRunDurationS ~/ 3600),
    };

/// Asks before saving a duration slower than 1 km/h over its distance. True
/// means save it as typed; false (or a dismissed dialog) means go back and fix.
Future<bool> confirmImplausiblySlowDuration(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.manualDurationSlowTitle),
      content: Text(l10n.manualDurationSlowBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.manualDurationSlowFix),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.manualDurationSlowSave),
        ),
      ],
    ),
  );
  return ok == true;
}
