import 'package:flutter/widgets.dart';

/// A [PageController] whose starting page is read from [currentPage] each
/// time a [PageView] attaches to it, instead of being fixed at construction.
///
/// A fixed `initialPage` is where a PageView opens whenever it is mounted,
/// which after the first page change is no longer the page the shell has
/// selected. A remounted PageView then showed Home while the shell's index
/// still said Run, so the nav marked Run selected and the Log button answered
/// "already on Run" over a recording nobody could reach (decisions § 2351).
/// `keepPage` is off because the shell's index is the one record of the
/// selected page, and a PageStorage copy of it could only disagree.
class ShellPageController extends PageController {
  ShellPageController({required int Function() currentPage})
      : _currentPage = currentPage,
        super(keepPage: false);

  final int Function() _currentPage;

  @override
  int get initialPage => _currentPage();
}
