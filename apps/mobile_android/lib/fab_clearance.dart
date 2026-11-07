import 'package:flutter/material.dart';

/// Height of a Material 3 [FloatingActionButton], regular or extended.
const double kFabHeight = 56;

/// Height a [FloatingActionButton.small] takes in a column: its 40dp button
/// padded out to the 48dp minimum tap target.
const double kSmallFabSlot = 48;

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
/// the end of the list. A page inside the phone shell adds [DockedFabInset],
/// because [pageFabLocation] lifts its button by that much.
double fabScrollClearance(BuildContext context, {int fabCount = 1}) =>
    MediaQuery.paddingOf(context).bottom +
    DockedFabInset.of(context) +
    kFabScrollClearance +
    (fabCount - 1) * (kFabHeight + kFabStackGap);

/// Where every page puts its floating action button: end-floating, lifted
/// by [DockedFabInset] so it clears the shell's docked centre button.
///
/// A page's own `Scaffold` knows nothing of the shell's: at plain `endFloat`
/// its button sits 16dp above the bar while the centre button rises 28dp
/// into the page, and a long extended label reaches across the middle into
/// it. Pushed routes and the rail layout read an inset of 0 and get plain
/// `endFloat` back, unchanged.
FloatingActionButtonLocation pageFabLocation(BuildContext context) {
  final lift = DockedFabInset.of(context);
  return lift == 0
      ? FloatingActionButtonLocation.endFloat
      : _LiftedEndFloat(lift);
}

class _LiftedEndFloat extends StandardFabLocation
    with FabEndOffsetX, FabFloatOffsetY {
  const _LiftedEndFloat(this.lift);

  final double lift;

  @override
  double getOffsetY(
          ScaffoldPrelayoutGeometry scaffoldGeometry, double adjustment) =>
      super.getOffsetY(scaffoldGeometry, adjustment) - lift;

  // Scaffold animates the button whenever its location stops being equal,
  // and every rebuild makes a new instance.
  @override
  bool operator ==(Object other) =>
      other is _LiftedEndFloat && other.lift == lift;

  @override
  int get hashCode => lift.hashCode;

  @override
  String toString() => 'pageFabLocation(lift: $lift)';
}

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
