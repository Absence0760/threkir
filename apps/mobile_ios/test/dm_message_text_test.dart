// Widget tests for DmMessageText (issue #1216): a message's text drawn as
// written, with a domain chip only for an http(s) link whose host is plain
// ASCII and carries no user-info. Every other scheme, a host in another
// script and a `user@host` look-alike stay plain text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/dm_message_text.dart';

Future<List<String>> _mount(WidgetTester tester, String body) async {
  final opened = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DmMessageText(body: body, onOpenLink: opened.add),
      ),
    ),
  );
  return opened;
}

Finder _link(int i) => find.byKey(ValueKey('dm-link-$i'));
Finder _domain(int i) => find.byKey(ValueKey('dm-link-domain-$i'));

void main() {
  testWidgets('plain text is one Text with no chip', (tester) async {
    await _mount(tester, 'Meet at the gate, 7am <b>sharp</b>');
    expect(find.text('Meet at the gate, 7am <b>sharp</b>'), findsOneWidget);
    expect(_link(0), findsNothing);
  });

  testWidgets('an https link gets its text and a chip naming the domain',
      (tester) async {
    final opened =
        await _mount(tester, 'Route: https://www.example.com/r/1, see you');
    expect(_link(0), findsOneWidget);
    expect(
      find.descendant(
          of: _link(0), matching: find.text('https://www.example.com/r/1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _domain(0), matching: find.text('example.com')),
      findsOneWidget,
    );
    await tester.tap(_link(0));
    expect(opened, ['https://www.example.com/r/1']);
  });

  testWidgets('a plain http link is a link too, each numbered in order',
      (tester) async {
    await _mount(tester, 'a http://one.org then https://two.net:8443/x');
    expect(
      find.descendant(of: _domain(0), matching: find.text('one.org')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _domain(1), matching: find.text('two.net')),
      findsOneWidget,
    );
  });

  for (final body in [
    'ftp://files.example.com/x',
    'mailto:ana@example.com',
    'javascript:alert(1)',
    'https://exämple.com/login',
    'https://раураl.com/',
    'https://example.com@evil.com/',
    'https://localhost/admin',
  ]) {
    testWidgets('stays text: $body', (tester) async {
      await _mount(tester, body);
      expect(_link(0), findsNothing);
      expect(find.text(body), findsOneWidget);
    });
  }

  testWidgets('a refused link next to a good one leaves only the good one',
      (tester) async {
    await _mount(tester, 'https://exämple.com and https://example.com');
    expect(_link(0), findsOneWidget);
    expect(_link(1), findsNothing);
    expect(
      find.descendant(of: _domain(0), matching: find.text('example.com')),
      findsOneWidget,
    );
  });

  testWidgets('with no handler a link draws but taps go nowhere',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DmMessageText(body: 'https://example.com')),
      ),
    );
    expect(_link(0), findsOneWidget);
    await tester.tap(_link(0));
  });
}
