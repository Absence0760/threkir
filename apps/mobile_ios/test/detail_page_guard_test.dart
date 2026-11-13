// A detail page lays out through ui_kit's `DetailPage` (issue #1374, conventions
// § Mobile page titles and detail pages): the scaffold owns the small app bar,
// the toolbar budget (two actions beside the overflow; Report and destructive
// actions only in it), and the rule that the page's name is said in its body,
// in a `DetailHero` or `PageHeader` that wraps, with the bar repeating it only
// once that heading has scrolled away (TO-12).
//
// Four checks:
//   * Every file that hosts a detail page (`*_detail_screen.dart` and the
//     files in `_hosts`) builds a `DetailPage`, and counts the `AppBar(` /
//     `SliverAppBar(` it still builds by hand. The counts left are pinned in
//     `_handBuilt`, each with why; the list may only shrink.
//   * Nowhere in lib/ is a page title hand-built: a `Semantics(header: true`
//     around a `headline` style is what `PageHeading` is for.
//   * The pushed pages whose titles were cut in fr/de (TO-12) and the root
//     pages are `PushedPage`s / `PageHeader`s and build no `AppBar(`.
//   * Anywhere in lib/, an `AppBar(` / `SliverAppBar(` built by hand is
//     counted per file against `_barsLeft`, each with why the page keeps a
//     bar of its own; the map may only shrink.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files hosting a detail page that are not named `*_detail_screen.dart`.
const _hosts = <String>{
  'lib/screens/guided_runs_screen.dart',
  'lib/screens/park_courses_screen.dart',
  'lib/screens/plan_library_screen.dart',
  'lib/screens/profile_screen.dart',
  'lib/screens/public_route_screen.dart',
  'lib/screens/public_run_screen.dart',
  'lib/screens/routine_public_library_screen.dart',
};

const _handBuilt = <String, ({int count, String why})>{
  'lib/screens/session_detail_screen.dart': (
    count: 1,
    why: 'the follow-along runner is a full-screen execution page whose '
        'close button abandons the session, not a detail page',
  ),
};

/// Hand-built app bars left anywhere in lib/, and why each page is not a
/// `PushedPage`. The counts may only shrink.
const _barsLeft = <String, ({int count, String why})>{
  'lib/screens/avatar_crop_screen.dart': (
    count: 1,
    why: 'a full-screen crop with a close button; the image takes the body',
  ),
  'lib/screens/coach_screen.dart': (
    count: 1,
    why: 'the chat is a conversation, with its history drawer opened from '
        'the bar; its signed-out and consent states are PushedPages',
  ),
  'lib/screens/group_thread_screen.dart': (
    count: 1,
    why: 'a conversation: its name stays in the bar (ThreadTitle, with a '
        'tooltip holding the whole name) above the messages',
  ),
  'lib/screens/gym_session_screen.dart': (
    count: 1,
    why: 'a live execution screen: the room goes to the entry fields and '
        'the band pinned under them, like the session runner',
  ),
  'lib/screens/live_spectator_screen.dart': (
    count: 1,
    why: 'a MapFirstPage, which takes its bar as a slot over the map',
  ),
  'lib/screens/message_thread_screen.dart': (
    count: 1,
    why: 'a conversation: its name stays in the bar (ThreadTitle, with a '
        'tooltip holding the whole name) above the messages',
  ),
  'lib/screens/parkrun_barcode_screen.dart': (
    count: 1,
    why: 'a barcode held up to a scanner on a fixed light surface: the code '
        'must stay in view, so nothing sits above it',
  ),
  'lib/screens/privacy_zones_screen.dart': (
    count: 1,
    why: 'a MapFirstPage, which takes its bar as a slot over the map',
  ),
  'lib/screens/route_builder_screen.dart': (
    count: 1,
    why: 'a full-screen map whose place search is the bar title',
  ),
  'lib/screens/routes_heatmap_screen.dart': (
    count: 1,
    why: 'a full-screen map whose place search is the bar title',
  ),
  'lib/screens/run_heatmap_screen.dart': (
    count: 1,
    why: 'a full-screen map: the map is the body, with no heading to hold',
  ),
  'lib/screens/session_detail_screen.dart': (
    count: 1,
    why: 'the follow-along runner is a full-screen execution page whose '
        'close button abandons the session',
  ),
  'lib/screens/setup_wizard_screen.dart': (
    count: 1,
    why: 'the wizard has no Back; it is in a PageTitleScope and says its '
        'title in the step, the bar repeating it as a PushedPage would',
  ),
  'lib/widgets/collapsing_tab_host.dart': (
    count: 1,
    why: 'the pinned zero-height bar that holds the club and profile tabs',
  ),
  'lib/widgets/nutrition_log_sheet.dart': (
    count: 1,
    why: 'the barcode scanner: a full-screen camera preview',
  ),
};

/// Pushed pages whose app-bar titles were cut in fr/de (TO-12, and the pages
/// the list-card worst-case runs found cut), each of which says its title in
/// the body.
const _titledInBody = <String>{
  'lib/screens/checkpoint_checkin_screen.dart',
  'lib/screens/coaching_athlete_screen.dart',
  'lib/screens/coaching_screen.dart',
  'lib/screens/course_drive_screen.dart',
  'lib/screens/devices_screen.dart',
  'lib/screens/gear_screen.dart',
  'lib/screens/gear_rotations_screen.dart',
  'lib/screens/guided_runs_screen.dart',
  'lib/screens/gym_records_screen.dart',
  'lib/screens/import_screen.dart',
  'lib/screens/nearby_area_screen.dart',
  'lib/screens/nutrition_targets_screen.dart',
  'lib/screens/period_summary_screen.dart',
  'lib/screens/plan_calendar_feed_screen.dart',
  'lib/screens/progress_screen.dart',
  'lib/screens/recap_screen.dart',
  'lib/screens/watch_live_screen.dart',
  'lib/screens/watch_screens_editor_screen.dart',
  'lib/screens/your_shares_screen.dart',
};

String _code(String s) => s
    .split('\n')
    .map((l) => l.trimLeft().startsWith('//') ? '' : l)
    .join('\n');

int appBarsIn(String s) =>
    RegExp(r'\b(?:Sliver)?AppBar\(').allMatches(_code(s)).length;

int handBuiltTitlesIn(String s) {
  final code = _code(s);
  var n = 0;
  for (final m in RegExp(r'Semantics\(\s*header:\s*true,').allMatches(code)) {
    final end = (m.end + 240).clamp(0, code.length);
    if (code.substring(m.end, end).contains('headline')) n++;
  }
  return n;
}

List<File> _lib() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/gen/'))
    .toList();

void main() {
  test('every detail page is a DetailPage; hand-built bars only shrink', () {
    final hosts = {
      for (final f in Directory('lib/screens').listSync().whereType<File>())
        if (f.path.endsWith('_detail_screen.dart')) f.path.replaceAll(r'\', '/'),
      ..._hosts,
    };
    final notDetailPage = <String>[];
    final grew = <String>[];
    final stale = <String>[];
    for (final path in hosts) {
      final s = File(path).readAsStringSync();
      if (!RegExp(r'\bDetailPage(?:\.placeholder)?\(').hasMatch(_code(s))) {
        notDetailPage.add(path);
      }
      final n = appBarsIn(s);
      final allowed = _handBuilt[path]?.count ?? 0;
      if (n > allowed) grew.add('$path: $n (allowed $allowed)');
      if (n < allowed) stale.add('$path: $allowed -> $n');
    }
    for (final path in _handBuilt.keys) {
      if (!hosts.contains(path)) stale.add('$path is no longer a host');
    }
    expect(notDetailPage, isEmpty,
        reason: 'lay the page out with DetailPage and a DetailHero');
    expect(grew, isEmpty,
        reason: 'a detail page takes its app bar from DetailPage');
    expect(stale, isEmpty,
        reason: 'a hand-built bar went away; lower its count in _handBuilt '
            '(drop the entry at zero)');
  });

  test('no page title is hand-built outside PageHeading', () {
    final found = <String>[];
    for (final f in _lib()) {
      final n = handBuiltTitlesIn(f.readAsStringSync());
      if (n > 0) found.add('${f.path}: $n');
    }
    expect(found, isEmpty,
        reason: "use PageHeader / DetailHero / PageHeading, which wrap the "
            "title and tell the page's bar when it has scrolled away");
  });

  test('the TO-12 pages, Progress and the four root tabs say their title '
      'in the body', () {
    final bad = <String>[];
    for (final path in _titledInBody) {
      final s = _code(File(path).readAsStringSync());
      if (appBarsIn(s) > 0 ||
          !s.contains('PushedPage(') ||
          !s.contains('PageHeader(')) {
        bad.add(path);
      }
    }
    // The four bottom-nav roots are ui_kit RootPages, which own the large
    // title, its collapse into the bar and the bar's actions; the two with a
    // scroll view of their own open it with the PageHeader.
    for (final path in const [
      'lib/screens/today_screen.dart',
      'lib/screens/you_screen.dart',
    ]) {
      final s = _code(File(path).readAsStringSync());
      if (!s.contains('RootPage(') || !s.contains('PageHeader(')) {
        bad.add('$path (root page without a RootPage and a PageHeader)');
      }
    }
    for (final path in const [
      'lib/screens/fitness_hub_screen.dart',
      'lib/screens/social_screen.dart',
    ]) {
      if (!_code(File(path).readAsStringSync()).contains('RootPage.tabbed(')) {
        bad.add('$path (root hub without a RootPage.tabbed)');
      }
    }
    expect(bad, isEmpty);
  });

  test('a hand-built app bar anywhere in lib/ only shrinks', () {
    final problems = <String>[];
    final found = <String, int>{};
    for (final f in _lib()) {
      final n = appBarsIn(f.readAsStringSync());
      if (n > 0) found[f.path.replaceAll(r'\', '/')] = n;
    }
    for (final e in found.entries) {
      final allowed = _barsLeft[e.key]?.count ?? 0;
      if (e.value > allowed) {
        problems.add('${e.key}: ${e.value} bars, $allowed allowed — lay the '
            'page out with PushedPage and a PageHeader');
      }
    }
    for (final e in _barsLeft.entries) {
      final n = found[e.key] ?? 0;
      if (n < e.value.count) {
        problems.add('${e.key}: $n bars, ${e.value.count} listed — lower the '
            'count in _barsLeft (drop the entry at zero)');
      }
      if (e.value.why.trim().isEmpty) problems.add('${e.key}: needs a reason');
    }
    expect(problems, isEmpty);
  });

  test('the scans see what they are for', () {
    expect(appBarsIn('Scaffold(appBar: AppBar(title: t))'), 1);
    expect(appBarsIn('// AppBar( in a comment'), 0);
    expect(
        handBuiltTitlesIn('''
          Semantics(
            header: true,
            child: Text(name, style: theme.textTheme.headlineSmall),
          )'''),
        1);
    expect(
        handBuiltTitlesIn('''
          Semantics(
            header: true,
            child: Text(section, style: theme.textTheme.titleMedium),
          )'''),
        0,
        reason: 'a section heading is SectionHeader.title, not a page title');
  });
}
