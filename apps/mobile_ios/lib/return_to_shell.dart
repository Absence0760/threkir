import 'package:flutter/widgets.dart';

/// Brings the shell back to the front by popping every route above it one at
/// a time through `maybePop`, so each route's `PopScope` is asked first: a
/// `DiscardGuard` form shows its "Discard changes?" prompt and a live gym
/// session its leave dialog. Resolves true once [isShell] is on top, false
/// as soon as a route keeps itself (the user chose Cancel), with every route
/// from that one down left in place.
///
/// `Navigator.popUntil` calls `pop`, which never consults a `PopScope`, so a
/// notification tap or a help link used to close a half-filled form with no
/// prompt (issue #1374 NS-1). Every "go back to the shell" goes through here;
/// `return_to_shell_guard_test.dart` fails on a `popUntil` anywhere else.
Future<bool> returnToShell(
  NavigatorState navigator, {
  RoutePredicate? isShell,
}) async {
  final atShell = isShell ?? (Route<dynamic> r) => r.isFirst;
  for (var step = 0; step < 64; step++) {
    if (!navigator.mounted) return false;
    final top = topRoute(navigator);
    if (top == null || atShell(top)) return true;
    await navigator.maybePop();
    if (!top.isActive) continue;
    // The route refused the pop. A guard that asks shows its question as a
    // route above it; wait for the answer, then let the guard act on it.
    final question = topRoute(navigator);
    if (question == null || identical(question, top)) return false;
    await question.popped;
    await Future<void>.delayed(Duration.zero);
    if (top.isActive) return false;
  }
  return false;
}

/// The route on top of [navigator], read without popping anything: a
/// predicate that holds at once makes `popUntil` a peek.
Route<dynamic>? topRoute(NavigatorState navigator) {
  Route<dynamic>? top;
  navigator.popUntil((r) {
    top = r;
    return true;
  });
  return top;
}
