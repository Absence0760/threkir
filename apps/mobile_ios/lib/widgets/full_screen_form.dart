import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show systemBottomInset;

import 'confirm_discard.dart';

/// Canonical presentation for a create / edit entity form on mobile: a
/// full-screen modal dialog (slide-up, close affordance) hosting [builder]
/// inside a [Scaffold] + [AppBar] + [SafeArea].
///
/// Every "add / edit X" surface routes through here — gear, club, event,
/// goal, gym, manual run, planned-workout edit — so the presentation is
/// identical and no form re-derives the wrapper. Replaces the earlier mix
/// of `showModalBottomSheet` (gear / event / workout-edit) and bare
/// `MaterialPageRoute` pages (club): the sheets fought the soft keyboard
/// (`viewInsets` + `FractionallySizedBox` both reflow during open, the
/// "slow and glitchy" feel) and a plain page lacked the dialog's slide-up +
/// close affordance.
///
/// [title] is read from the caller's context once (the heading lives in the
/// AppBar, not inline in the body). Resolves to whatever the form pops.
///
/// [isDirty], when set, arms a [DiscardGuard]: backing out (system back, the
/// AppBar close button, or any `maybePop`) while it reports unsaved edits
/// confirms via [confirmDiscard] before popping. Save paths that pop with
/// `Navigator.pop` after persisting bypass the guard by design.
Future<T?> showFullScreenForm<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  bool Function()? isDirty,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: (ctx) {
        final scaffold = Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(child: builder(ctx)),
        );
        if (isDirty == null) return scaffold;
        return DiscardGuard(isDirty: isDirty, child: scaffold);
      },
    ),
  );
}

/// Standard scrollable chrome for a [showFullScreenForm] child: a 20px
/// inset that grows by ui_kit's `systemBottomInset` (the keyboard when it
/// is up, else the gesture / nav bar), the same inset `SheetScaffold` adds
/// to a bottom sheet. Wraps the children in a [SingleChildScrollView] +
/// stretch [Column].
class FullScreenFormBody extends StatelessWidget {
  const FullScreenFormBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(20, 20, 20, 20 + systemBottomInset(context)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Uppercase muted section label used between field groups on the
/// full-screen forms (goal targets, gym title, …).
class FormSectionLabel extends StatelessWidget {
  const FormSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
