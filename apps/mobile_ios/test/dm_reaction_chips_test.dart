// Widget smoke tests for DmReactionChips, the reaction chips under one
// message: a chip per reaction used with its count, the viewer's own one
// highlighted and announced as selected, and a tap that sets or clears the
// viewer's reaction.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_reactions.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/widgets/dm_reaction_chips.dart';

final _l10n = AppLocalizationsEn();

const _rows = [
  DmReactionRow(messageId: 'm1', userId: 'me', reaction: 'heart'),
  DmReactionRow(messageId: 'm1', userId: 'ana', reaction: 'heart'),
  DmReactionRow(messageId: 'm1', userId: 'ben', reaction: 'thumbs_up'),
  DmReactionRow(messageId: 'm2', userId: 'ana', reaction: 'fire'),
];

Finder _chip(String reaction) =>
    find.byKey(ValueKey('dm-reaction-chip-$reaction'));

Future<List<String?>> _mount(
  WidgetTester tester, {
  List<DmReactionRow> rows = _rows,
  bool canReact = true,
}) async {
  final calls = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DmReactionChips(
          messageId: 'm1',
          rows: rows,
          viewerId: 'me',
          canReact: canReact,
          onSet: calls.add,
        ),
      ),
    ),
  );
  return calls;
}

/// What a screen reader's double-tap sends: the node's own tap action.
void _srTap(WidgetTester tester, Finder finder) {
  final node = tester.getSemantics(finder);
  node.owner!.performAction(node.id, SemanticsAction.tap);
}

Color? _chipColor(WidgetTester tester, String reaction) {
  final c = tester.widget<Container>(
    find.descendant(of: _chip(reaction), matching: find.byType(Container)),
  );
  return (c.decoration! as BoxDecoration).color;
}

void main() {
  testWidgets("one chip per reaction on this message, with its count",
      (tester) async {
    await _mount(tester);
    expect(_chip('thumbs_up'), findsOneWidget);
    expect(_chip('heart'), findsOneWidget);
    expect(_chip('fire'), findsNothing, reason: 'that row is on m2');
    expect(
      find.descendant(of: _chip('heart'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _chip('thumbs_up'), matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: _chip('heart'), matching: find.text(dmReactionGlyph('heart'))),
      findsOneWidget,
    );
  });

  testWidgets("the viewer's own reaction is highlighted and announced",
      (tester) async {
    await _mount(tester);
    final scheme = Theme.of(tester.element(_chip('heart'))).colorScheme;
    expect(_chipColor(tester, 'heart'), scheme.primaryContainer);
    expect(_chipColor(tester, 'thumbs_up'), scheme.surfaceContainerHighest);

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(_chip('heart')),
      matchesSemantics(
        label: _l10n.messagesReactionChipLabel(_l10n.messagesReactionHeart, 2),
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a screen reader can toggle a chip, and pick from the picker',
      (tester) async {
    final handle = tester.ensureSemantics();
    final calls = await _mount(tester);
    _srTap(tester, _chip('thumbs_up'));
    _srTap(tester, _chip('heart'));
    expect(calls, ['thumbs_up', null]);

    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  picked = await showDmReactionPicker(context, current: 'fire'),
              child: const Text('react'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('react'));
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('dm-reaction-option-laugh'));
    expect(
      tester.getSemantics(option),
      matchesSemantics(
        label: _l10n.messagesReactionLaugh,
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    _srTap(tester, option);
    await tester.pumpAndSettle();
    expect(picked, 'laugh');
    handle.dispose();
  });

  testWidgets("tapping someone else's reaction makes it the viewer's",
      (tester) async {
    final calls = await _mount(tester);
    await tester.tap(_chip('thumbs_up'));
    expect(calls, ['thumbs_up']);
  });

  testWidgets("tapping the viewer's own reaction clears it", (tester) async {
    final calls = await _mount(tester);
    await tester.tap(_chip('heart'));
    expect(calls, [null]);
  });

  testWidgets('a viewer who cannot react sees the chips but cannot tap them',
      (tester) async {
    final calls = await _mount(tester, canReact: false);
    expect(_chip('heart'), findsOneWidget);
    await tester.tap(_chip('heart'));
    expect(calls, isEmpty);
  });

  testWidgets('no reactions draws nothing', (tester) async {
    await _mount(tester, rows: const []);
    expect(find.byType(InkWell), findsNothing);
  });
}
