import 'package:flutter/widgets.dart';

/// Who answers the system Back on the shell before the shell itself.
///
/// The shell is `MaterialApp.home`, so its pages share one route, and every
/// `PopScope` on that route is called on every Back: a tab body's own scope
/// cleared its selection while the shell's moved to Home in the same press,
/// and a kept-alive tab still selecting vetoed Back on a page the runner
/// could not see (issue #1374 NS-2). Instead the shell keeps the one
/// `PopScope`, and on Back asks the page that is showing, through this
/// registry, whether it has something to undo first. A hub registers one
/// handler for its page and passes the question to its active tab
/// (`HubPrimaryActions.consumeBack`), so a tab body never needs a raw
/// `PopScope`; `shell_back_guard_test.dart` holds that line.
class ShellBack {
  final Map<int, bool Function()> _handlers = {};

  /// [handler] answers true when it used the Back. One per page.
  void register(int page, bool Function() handler) =>
      _handlers[page] = handler;

  void unregister(int page, bool Function() handler) {
    if (_handlers[page] == handler) _handlers.remove(page);
  }

  /// Offers Back to [page]'s handler; true when it was used.
  bool consume(int page) => _handlers[page]?.call() ?? false;
}

/// Places a shell page in the registry, so the page can register itself
/// without knowing its index.
class ShellBackScope extends InheritedWidget {
  const ShellBackScope({
    super.key,
    required this.back,
    required this.page,
    required super.child,
  });

  final ShellBack back;
  final int page;

  static ShellBackScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellBackScope>();

  @override
  bool updateShouldNotify(ShellBackScope oldWidget) =>
      oldWidget.back != back || oldWidget.page != page;
}

/// Registers a page's Back handler with the enclosing [ShellBackScope] for
/// as long as the state is mounted. Mix into a hub's `State` and implement
/// [handleShellBack].
mixin ShellBackHandler<T extends StatefulWidget> on State<T> {
  ShellBackScope? _shellBack;

  /// True when this page used the Back (closed a selection, say).
  bool handleShellBack();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ShellBackScope.maybeOf(context);
    if (identical(scope, _shellBack)) return;
    _shellBack?.back.unregister(_shellBack!.page, handleShellBack);
    _shellBack = scope;
    scope?.back.register(scope.page, handleShellBack);
  }

  @override
  void dispose() {
    _shellBack?.back.unregister(_shellBack!.page, handleShellBack);
    super.dispose();
  }
}
