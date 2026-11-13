// The Fitness and Social hubs each own the only app bar and the one FAB;
// every tab body is ui_kit's `HubTabBody`, which inside the hub draws no app
// bar or title and hands its primary action to the hub (issue #1374). Before
// it each Fitness tab brought its own Scaffold, AppBar and FAB, so a second
// title bar sat under the strip on every tab, two of them renaming it, and
// the primary action moved on every swipe; the Social tabs forked on an
// `embedded` flag and the hub fished their FABs out through GlobalKeys.
//
// The scan reads the tab bodies off each hub's `_body` rather than a list
// here, so a new tab is checked the day it is added.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [source] with comments removed and string literals emptied.
String _codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
    } else if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
    } else if (source[i] == "'" || source[i] == '"') {
      final triple = source.startsWith(source[i] * 3, i);
      final quote = triple ? source[i] * 3 : source[i];
      final raw = i > 0 && source[i - 1] == 'r';
      var j = i + quote.length;
      while (j < source.length && !source.startsWith(quote, j)) {
        if (!raw && source[j] == r'\') j++;
        j++;
      }
      out.write("''");
      i = j + quote.length;
    } else {
      out.write(source[i]);
      i++;
    }
  }
  return out.toString();
}

int _close(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return s.length - 1;
}

/// Every class in lib/, by name, as code only.
Map<String, String> _classes() {
  final out = <String, String>{};
  final decl = RegExp(r'^(?:abstract\s+)?class\s+(\w+)[^{]*\{', multiLine: true);
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final s = _codeOnly(f.readAsStringSync());
    for (final m in decl.allMatches(s)) {
      out[m.group(1)!] = s.substring(m.start, _close(s, m.end - 1) + 1);
    }
  }
  return out;
}

/// The screens a hub's `_body` mounts as tab bodies.
List<String> _tabBodies(String hub) {
  final start = hub.indexOf('Widget _body(');
  if (start < 0) throw StateError('a hub\'s _body moved; update the scan');
  final body = hub.substring(start, _close(hub, hub.indexOf('{', start)));
  return {
    for (final m in RegExp(r'\b([A-Z]\w*Screen)\(').allMatches(body)) m.group(1)!,
  }.toList();
}

/// Screens a tab body mounts in place as one of its views, which are hub
/// tab bodies too: Routes' Explore views (issue #1374, owner decision 1).
/// Listed rather than scanned, because a body's build also names the screens
/// it pushes; the test below fails if an entry stops being mounted.
const _tabViews = {
  'RoutesScreen': ['ExploreRoutesScreen', 'GlobalSegmentsScreen'],
};

/// [name]'s widget class with its state class.
String _withState(Map<String, String> classes, String name) {
  final widget = classes[name];
  if (widget == null) return '';
  final stateName =
      RegExp(r'createState\(\)\s*=>\s*(\w+)\(').firstMatch(widget)?.group(1);
  return [widget, if (stateName != null) classes[stateName] ?? ''].join();
}

void main() {
  final classes = _classes();
  final hubs = {
    'Fitness': (
      state: '_FitnessHubScreenState',
      expected: ['RunsScreen', 'PlansScreen', 'GymScreen'],
    ),
    'Social': (
      state: '_SocialScreenState',
      expected: [
        'FeedScreen',
        'ClubsScreen',
        'DiscoverScreen',
        'ChallengesScreen',
        'PeopleScreen',
      ],
    ),
  };

  for (final MapEntry(key: name, value: spec) in hubs.entries) {
    final hub = classes[spec.state];
    final tabs = hub == null ? const <String>[] : _tabBodies(hub);
    final bodies = [
      ...tabs,
      for (final MapEntry(key: host, value: views) in _tabViews.entries)
        if (tabs.contains(host)) ...views,
    ];
    group('$name hub', () {
      test('the scan finds the hub\'s tab bodies', () {
        expect(hub, isNotNull, reason: 'no class ${spec.state} in lib/');
        expect(tabs, containsAll(spec.expected));
      });

      test('the hub hosts each tab in a HubTabScope and shows the one FAB', () {
        expect(hub, contains('HubTabScope('));
        expect(hub, contains('HubFab('));
        expect(hub, contains('floatingActionButtonLocation: pageFabLocation('));
      });

      // Issue #1374 NS-2 / NS-3: the shell's pages share one route, so a tab
      // body's own PopScope ran on every Back beside the shell's, and a hidden
      // tab's selection vetoed Back elsewhere. The hub answers Back for its
      // showing tab through the shell's registry instead.
      test('the hub answers the shell\'s Back for its showing tab', () {
        expect(hub, contains('ShellBackHandler'));
        expect(hub, contains('consumeBack('));
      });

      for (final name in bodies) {
        test('$name is a HubTabBody with no app bar or Scaffold of its own', () {
          expect(classes[name], isNotNull, reason: 'no class $name in lib/');
          final source = _withState(classes, name);
          expect(source, contains('HubTabBody('),
              reason: '$name should build its tab through ui_kit\'s HubTabBody');
          expect(RegExp(r'\bPopScope\b').hasMatch(source), isFalse,
              reason: '$name has a PopScope of its own. A tab body shares the '
                  'shell\'s route, so its scope runs on every Back, hidden or '
                  'not (issue #1374 NS-2). Pass the selection to HubTabBody, '
                  'which hands Back to the hub only while the tab is showing.');
          for (final banned in ['AppBar(', 'Scaffold(', 'FloatingActionButton']) {
            expect(RegExp('\\b${RegExp.escape(banned)}').hasMatch(source), isFalse,
                reason: '$name builds its own $banned: in the hub the strip is '
                    'the only app bar and the hub draws the FAB. Pass the title, '
                    'actions and primary action to HubTabBody instead.');
          }
        });
      }
    });
  }

  final fitness = classes['_FitnessHubScreenState']!;
  for (final MapEntry(key: host, value: views) in _tabViews.entries) {
    test('$host mounts its views in place', () {
      expect(_tabBodies(fitness), contains(host));
      final source = _withState(classes, host);
      for (final view in views) {
        expect(source, contains('$view('),
            reason: '$host no longer mounts $view; drop it from _tabViews');
      }
    });
  }
}
