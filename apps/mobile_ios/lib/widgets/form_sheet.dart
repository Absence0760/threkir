import 'package:flutter/material.dart';

import 'confirm_discard.dart';

/// Opens a bottom sheet that holds typed input. Its builder builds a
/// [SheetDiscardGuard] around the sheet's `SheetScaffold`.
///
/// A plain `showModalBottomSheet` closes on a swipe down through
/// `Navigator.pop`, which never asks a `PopScope`, so a sheet guarding typed
/// text could be swiped away with no prompt (issue #1374 NS-13). This one
/// turns the framework's drag and drag handle off, and [SheetDiscardGuard]
/// draws the handle and drives the slide itself, closing through `maybePop`
/// like Back and a tap on the barrier do. Every way out then reaches the
/// guard's "Discard changes?" prompt while there is something to lose.
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  late final _FormSheetRoute<T> route;
  route = _FormSheetRoute<T>(
    builder: (sheetContext) =>
        _FormSheetScope(route: route, child: builder(sheetContext)),
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
  );
  return navigator.push(route);
}

/// `showModalBottomSheet`'s route with the framework's drag turned off, and
/// its slide controller (which the route still creates and disposes) handed
/// to [SheetDiscardGuard] to drive instead.
class _FormSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _FormSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
  }) : super(
         isScrollControlled: true,
         useSafeArea: true,
         enableDrag: false,
         showDragHandle: false,
       );

  AnimationController? get slide => controller;
}

class _FormSheetScope extends InheritedWidget {
  const _FormSheetScope({required this.route, required super.child});

  final _FormSheetRoute<Object?> route;

  @override
  bool updateShouldNotify(_FormSheetScope old) => old.route != route;
}

/// The unsaved-input guard for a sheet opened with [showFormSheet]. While
/// [isDirty] reports something typed and unsaved, a swipe down, a tap on the
/// barrier and Back each ask "Discard changes?" before the sheet closes;
/// otherwise they close it at once.
///
/// It draws the sheet's drag handle (the theme's would close the sheet
/// without asking) and moves the sheet with the finger. [isDirty] is read at
/// the moment of closing, like [DiscardGuard]'s, so a field's controller
/// needs no `setState` to count. A save path that has written its data closes
/// with `Navigator.pop`, which skips the prompt.
///
/// Opened any other way (a test that pumps the sheet's widget on its own),
/// the swipe still closes through the guard but the sheet does not follow
/// the finger; `sheet_scaffold_guard_test.dart` keeps every sheet in `lib/`
/// on [showFormSheet].
class SheetDiscardGuard extends StatefulWidget {
  const SheetDiscardGuard({
    super.key,
    required this.isDirty,
    required this.child,
    this.confirmBody,
  });

  final bool Function() isDirty;
  final Widget child;

  /// Replaces the generic "You have unsaved changes" message.
  final String? confirmBody;

  @override
  State<SheetDiscardGuard> createState() => _SheetDiscardGuardState();
}

class _SheetDiscardGuardState extends State<SheetDiscardGuard> {
  // The framework's own thresholds for closing a dragged sheet.
  static const _minFlingVelocity = 700.0;
  static const _closeProgressThreshold = 0.5;

  AnimationController? get _controller =>
      context.getInheritedWidgetOfExactType<_FormSheetScope>()?.route.slide;

  double get _height => context.size?.height ?? 1;

  void _dragUpdate(DragUpdateDetails details) {
    final controller = _controller;
    if (controller == null || controller.isAnimating) return;
    controller.value -= details.primaryDelta! / _height;
  }

  void _dragEnd(DragEndDetails details) {
    final controller = _controller;
    final velocity = details.velocity.pixelsPerSecond.dy;
    final closing =
        velocity > _minFlingVelocity ||
        (controller != null && controller.value < _closeProgressThreshold);
    if (closing && !widget.isDirty()) {
      Navigator.of(context).pop();
      return;
    }
    controller?.forward();
    if (closing) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handleSize =
        theme.bottomSheetTheme.dragHandleSize ?? const Size(32, 4);
    return DiscardGuard(
      isDirty: widget.isDirty,
      confirmBody: widget.confirmBody,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _dragUpdate,
        onVerticalDragEnd: _dragEnd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              key: const ValueKey('form-sheet-handle'),
              label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
              container: true,
              button: true,
              onTap: () => Navigator.of(context).maybePop(),
              child: SizedBox(
                height: kMinInteractiveDimension,
                child: Center(
                  child: Container(
                    width: handleSize.width,
                    height: handleSize.height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        handleSize.height / 2,
                      ),
                      color:
                          theme.bottomSheetTheme.dragHandleColor ??
                          theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
            Flexible(child: widget.child),
          ],
        ),
      ),
    );
  }
}

/// What a set of text fields held when a sheet opened, for an `isDirty` that
/// asks whether any of them has changed since. Take it in `initState`, after
/// the controllers have their starting text.
class FieldSnapshot {
  FieldSnapshot(List<TextEditingController> fields)
    : _fields = fields,
      _start = [for (final f in fields) f.text];

  final List<TextEditingController> _fields;
  final List<String> _start;

  bool get changed {
    for (var i = 0; i < _fields.length; i++) {
      if (_fields[i].text.trim() != _start[i].trim()) return true;
    }
    return false;
  }
}
