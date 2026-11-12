// The Fitness hub owns the only app bar (the strip, no title) and the one
// FAB, as the Social hub does; every tab body is ui_kit's `HubTabBody`, which
// inside the hub draws no app bar or title and hands its primary action to
// the hub (issue #1374). Before it each tab brought its own Scaffold, AppBar
// and FAB, so a second title bar sat under the strip on every tab, two of
// them renaming it, and the primary action moved on every swipe.
//
// The scan reads the tab bodies off `FitnessHubScreen._body` rather than a
// list here, so a new tab is checked the day it is added.

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

/// The screens `FitnessHubScreen._body` mounts as tab bodies.
List<String> _tabBodies(String hub) {
  final start = hub.indexOf('Widget _body(');
  if (start < 0) throw StateError('FitnessHubScreen._body moved; update the scan');
  final body = hub.substring(start, _close(hub, hub.indexOf('{', start)));
  return {
    for (final m in RegExp(r'\b([A-Z]\w*Screen)\(').allMatches(body)) m.group(1)!,
  }.toList();
}

void main() {
  final classes = _classes();
  final hub = classes['_FitnessHubScreenState']!;
  final bodies = _tabBodies(hub);

  test('the scan finds the hub\'s tab bodies', () {
    expect(bodies, containsAll(['RunsScreen', 'PlansScreen', 'GymScreen']));
  });

  test('the hub hosts each tab in a HubTabScope and shows the one FAB', () {
    expect(hub, contains('HubTabScope('));
    expect(hub, contains('HubFab('));
    expect(hub, contains('floatingActionButtonLocation: pageFabLocation('));
  });

  for (final name in bodies) {
    test('$name is a HubTabBody with no app bar or Scaffold of its own', () {
      final widget = classes[name];
      expect(widget, isNotNull, reason: 'no class $name in lib/');
      final stateName =
          RegExp(r'createState\(\)\s*=>\s*(\w+)\(').firstMatch(widget!)?.group(1);
      final source = [widget, if (stateName != null) classes[stateName]!].join();
      expect(source, contains('HubTabBody('),
          reason: '$name should build its tab through ui_kit\'s HubTabBody');
      for (final banned in ['AppBar(', 'Scaffold(', 'FloatingActionButton']) {
        expect(RegExp('\\b${RegExp.escape(banned)}').hasMatch(source), isFalse,
            reason: '$name builds its own $banned: in the hub the strip is '
                'the only app bar and the hub draws the FAB. Pass the title, '
                'actions and primary action to HubTabBody instead.');
      }
    });
  }
}
