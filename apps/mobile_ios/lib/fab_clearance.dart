import 'package:flutter/widgets.dart';

/// Height of a Material 3 [FloatingActionButton], regular or extended.
const double kFabHeight = 56;

/// Vertical gap between stacked FABs in this app's two-FAB columns.
const double kFabStackGap = 12;

/// Bottom padding a scroll view owes a single floating action button, before
/// any system inset: the Scaffold's own 16dp FAB margin, the button, and 16dp
/// so the last row is not flush against it.
///
/// Measured, not guessed — `Scaffold` places an end-floating FAB with its
/// bottom `kFloatingActionButtonMargin + minViewPadding.bottom` above the
/// content bottom, so a list with no clearance ends underneath it.
const double kFabScrollClearance = 16 + kFabHeight + 16;

/// Bottom padding for a scroll view that [fabCount] floating action buttons
/// float over.
///
/// The system inset comes from `MediaQuery.padding`, not `viewPadding`, so
/// the number composes: a `SafeArea` above the caller, or a parent `Scaffold`
/// with a `bottomNavigationBar`, has already consumed the nav bar and reports
/// zero — exactly the cases where adding it again would leave a dead band at
/// the end of the list.
double fabScrollClearance(BuildContext context, {int fabCount = 1}) =>
    MediaQuery.paddingOf(context).bottom +
    kFabScrollClearance +
    (fabCount - 1) * (kFabHeight + kFabStackGap);

/// How far a docked centre FAB rises into the page above its bottom bar.
///
/// `FloatingActionButtonLocation.centerDocked` centres the button on the
/// bar's top edge, so half of it overlaps the body: content pinned to the
/// body's bottom edge sits underneath it. The phone shell publishes this
/// through [DockedFabInset]; the rail layout docks nothing and publishes 0.
const double kDockedFabOverhang = kFabHeight / 2;

/// The part of the page bottom a docked FAB covers, for bottom-pinned
/// controls to stay clear of.
///
/// `MediaQuery.padding` can't carry it: the Scaffold's bottom bar has already
/// consumed the bottom inset by the time the body reads it, and the FAB is
/// not a system inset anyway. Absent from the tree means nothing is docked.
class DockedFabInset extends InheritedWidget {
  const DockedFabInset({super.key, required this.height, required super.child});

  final double height;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DockedFabInset>()?.height ?? 0;

  @override
  bool updateShouldNotify(DockedFabInset oldWidget) => oldWidget.height != height;
}
