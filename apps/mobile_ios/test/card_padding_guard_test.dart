// Every card is ui_kit's `ListCard` (issue #1374). Before it, the app built
// about 160 `Card(`s by hand: about 120 `Card > Padding` blocks with 29
// different inner paddings, 20 `Card > ListTile`s and 20 `Card > InkWell`
// taps, each with its own margin, selected state and idea of what a screen
// reader hears. `ListCard` owns the shape, the padding (`AppInsets.card` /
// `cardDense`), the tap node and the selected tint, so a list says what is in
// a card and not how to draw one.
//
// In `lib/` this fails on:
//   1. a `Card(` built outside `ListCard`;
//   2. an outlined card look-alike: a `BoxDecoration` with both a
//      `borderRadius` and a `border`, the way a hand-built card fakes the
//      theme's card shape.
// Each is counted per file against a map whose entries carry the reason the
// file still has them. The counts may only shrink: a file over its count
// fails, and so does a file under it until the entry is lowered or removed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `Card(`s left, and why each is not a `ListCard`.
const _cardsLeft = <String, (int, String)>{
  'lib/screens/run_detail_screen.dart': (
    2,
    'the "Loading GPS" and "GPS unavailable" chips laid over the hero map; '
        'they belong to the detail hero, which moves to DetailPage',
  ),
  'lib/screens/run_screen.dart': (
    2,
    'the "to start line" and race-status pills floating over the recorder '
        'map: pills, not cards; a card inset would move the recording '
        'screen, so they wait for an overlay chip',
  ),
};

/// Outlined card look-alikes left, and why each is not a `ListCard`.
const _lookAlikesLeft = <String, (int, String)>{
  'lib/help_illustration.dart': (1, 'a drawing of a screen in a help guide'),
  'lib/screens/club_detail_screen.dart': (
    2,
    'the next-event card is a gradient, which ListCard has no slot for; the '
        'post composer is a text field, not a list item',
  ),
  'lib/screens/clubs_screen.dart': (1, 'a small outlined tag inside the club row'),
  'lib/screens/coach_screen.dart': (3, 'context, plan and suggestion chips'),
  'lib/screens/event_detail_screen.dart': (
    2,
    'attendee chips, and the inline post form',
  ),
  'lib/screens/live_spectator_screen.dart': (
    1,
    'the broadcast-concluded panel, which moves to DetailPage with the '
        'spectator page',
  ),
  'lib/screens/nutrition_meal_detail_screen.dart': (
    3,
    'the meal detail page\'s macro, items and trend panels, tinted '
        'surfaceContainerHighest; they move with the page to DetailPage',
  ),
  'lib/screens/plan_detail_screen.dart': (
    1,
    'a workout row\'s kind-coloured inset inside the week grid',
  ),
  'lib/screens/route_builder_screen.dart': (2, 'two panels over the builder map'),
  'lib/screens/run_detail_screen.dart': (
    2,
    'the route-suggestion banner and the map-match pill over the hero map',
  ),
  'lib/screens/runs_screen.dart': (
    2,
    'the month / year navigation group and the date-range endpoint chips',
  ),
  'lib/widgets/activity_heatmap.dart': (1, 'a heatmap cell'),
  'lib/widgets/badge_grid.dart': (1, 'a badge tile in a grid, drawn as Ink'),
  'lib/widgets/coach_share_card.dart': (
    1,
    'a shared plan inside a message bubble',
  ),
  'lib/widgets/cutoff_card.dart': (
    1,
    'the cutoff panel over the recorder and spectator maps',
  ),
  'lib/widgets/dm_reaction_chips.dart': (2, 'reaction chips'),
  'lib/widgets/gym_execution_band.dart': (
    1,
    'the translucent band pinned over the gym session',
  ),
  'lib/widgets/missing_map_tiles_hint.dart': (
    1,
    'a dev-only hint over the map',
  ),
  'lib/widgets/pacing_strategy_section.dart': (
    1,
    'the split table\'s frame inside a detail section',
  ),
  'lib/widgets/plan_card.dart': (
    1,
    'planCardDecoration, the plan week grid\'s emphasised day frame',
  ),
  'lib/widgets/plan_day_cell.dart': (2, 'a plan calendar day cell'),
  'lib/widgets/plan_import_sheet.dart': (
    1,
    'the import preview inside a sheet',
  ),
  'lib/widgets/plan_races_list.dart': (
    1,
    'a tinted panel holding the plan\'s races as rows',
  ),
  'lib/widgets/race_banner.dart': (1, 'the race banner on the recorder'),
  'lib/widgets/segments_panel.dart': (
    1,
    'the crown banner over the leaderboard',
  ),
  'lib/widgets/this_week_strip.dart': (1, 'a day cell in the week strip'),
  'lib/widgets/undo_bar.dart': (1, 'the floating undo bar'),
  'lib/widgets/upcoming_event_card.dart': (
    1,
    'a gradient event card, which ListCard has no slot for',
  ),
  'lib/widgets/workout_execution_band.dart': (
    1,
    'the translucent band pinned over the recorder',
  ),
  'lib/widgets/workout_review_section.dart': (
    1,
    'the review table\'s frame inside a detail section',
  ),
};

final _card = RegExp(r'(?<![A-Za-z_.])Card\(');

/// The source with line comments removed, so a comment naming a widget is
/// not counted as one.
String _code(File f) => f
    .readAsLinesSync()
    .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
    .join('\n');

/// `BoxDecoration(...)` calls whose arguments name both a `borderRadius` and
/// a `border`.
int lookAlikes(String src) {
  var n = 0;
  for (final m in RegExp(r'BoxDecoration\(').allMatches(src)) {
    var depth = 1;
    var i = m.end;
    while (depth > 0 && i < src.length) {
      final c = src[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      i++;
    }
    final args = src.substring(m.end, i);
    if (args.contains('borderRadius') && RegExp(r'\bborder:').hasMatch(args)) {
      n++;
    }
  }
  return n;
}

Map<String, String> _sources() => {
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') && !f.path.contains('/l10n/gen/')))
        f.path.replaceAll(r'\', '/'): _code(f),
    };

List<String> _check(
  Map<String, int> found,
  Map<String, (int, String)> left,
  String what,
  String fix,
) {
  final problems = <String>[];
  for (final e in found.entries) {
    final allowed = left[e.key]?.$1 ?? 0;
    if (e.value > allowed) {
      problems.add('${e.key}: ${e.value} $what, $allowed allowed — $fix');
    }
  }
  for (final e in left.entries) {
    final n = found[e.key] ?? 0;
    if (n < e.value.$1) {
      problems.add('${e.key}: $n $what, ${e.value.$1} listed — lower the '
          'count or remove the entry');
    }
    if (e.value.$2.trim().isEmpty) problems.add('${e.key}: needs a reason');
  }
  return problems;
}

void main() {
  final sources = _sources();

  test('the matchers count a card and a look-alike and spare the rest', () {
    expect(_card.allMatches('Card(child: x)').length, 1);
    expect(_card.allMatches('ListCard(child: x)').length, 0);
    expect(_card.allMatches('ListCard.row(title: x)').length, 0);
    expect(_card.allMatches('_RouteCard(route: r)').length, 0);
    expect(
      lookAlikes('BoxDecoration(borderRadius: r, border: Border.all())'),
      1,
    );
    expect(lookAlikes('BoxDecoration(color: c, borderRadius: r)'), 0);
    expect(lookAlikes('BoxDecoration(border: Border(top: b))'), 0);
    expect(
      lookAlikes('BoxDecoration(border: Border.all(width: f(1)), '
          'borderRadius: BorderRadius.circular(g(2)))'),
      1,
    );
  });

  test('no Card( outside ListCard past the counts left', () {
    final found = {
      for (final e in sources.entries)
        if (_card.allMatches(e.value).isNotEmpty)
          e.key: _card.allMatches(e.value).length,
    };
    expect(
      _check(found, _cardsLeft, 'Card(s)',
          'use ListCard / ListCard.row / ListCard.flush'),
      isEmpty,
    );
  });

  test('no outlined card look-alike past the counts left', () {
    final found = {
      for (final e in sources.entries)
        if (lookAlikes(e.value) > 0) e.key: lookAlikes(e.value),
    };
    expect(
      _check(found, _lookAlikesLeft, 'outlined BoxDecoration(s)',
          'a card in a list is a ListCard'),
      isEmpty,
    );
  });
}
