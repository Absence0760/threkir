import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppRadius;

/// The one box every plan-detail card sits in: the hero, the calendar, each
/// week, the rules, the share panel. `emphasised` is the current week's
/// primary outline.
BoxDecoration planCardDecoration(ThemeData theme, {bool emphasised = false}) =>
    BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      border: Border.all(
        color: emphasised
            ? theme.colorScheme.primary
            : theme.dividerColor,
        width: emphasised ? 1.5 : 1,
      ),
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
