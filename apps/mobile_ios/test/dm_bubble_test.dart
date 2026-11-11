// Widget smoke tests for DmBubble, the message bubble shared by the 1:1 and
// group threads (decisions § 2468): which side and colour a message takes,
// the edited mark, the unsent placeholder, the group sender name and the
// long-press hook.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/dm_bubble.dart';
import '../lib/widgets/dm_message_text.dart';

Future<ColorScheme> _mount(WidgetTester tester, DmBubble bubble) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ListView(children: [bubble]))),
  );
  return Theme.of(tester.element(find.byType(DmBubble))).colorScheme;
}

Color? _bubbleColor(WidgetTester tester) {
  final box = tester
      .widgetList<Container>(
        find.descendant(
            of: find.byType(DmBubble), matching: find.byType(Container)),
      )
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .first;
  return box.color;
}

Alignment _alignment(WidgetTester tester) => tester
    .widget<Align>(
      find.descendant(of: find.byType(DmBubble), matching: find.byType(Align)),
    )
    .alignment as Alignment;

void main() {
  testWidgets("the viewer's own message sits right in the primary colour",
      (tester) async {
    final scheme = await _mount(
      tester,
      const DmBubble(mine: true, body: 'On my way', time: '7:02'),
    );
    expect(find.text('On my way'), findsOneWidget);
    expect(find.text('7:02'), findsOneWidget);
    expect(_alignment(tester), Alignment.centerRight);
    expect(_bubbleColor(tester), scheme.primary);
  });

  testWidgets("someone else's message sits left with their name and avatar",
      (tester) async {
    final scheme = await _mount(
      tester,
      const DmBubble(
        mine: false,
        body: 'See you at the gate',
        time: '7:03',
        senderName: 'Ana',
        avatar: SizedBox(key: ValueKey('avatar'), width: 24, height: 24),
      ),
    );
    expect(_alignment(tester), Alignment.centerLeft);
    expect(_bubbleColor(tester), scheme.surfaceContainerHighest);
    expect(find.byKey(const ValueKey('dm-sender-name')), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.byKey(const ValueKey('avatar')), findsOneWidget);
  });

  testWidgets('a group never names or pictures the viewer on their own message',
      (tester) async {
    await _mount(
      tester,
      const DmBubble(
        mine: true,
        body: 'Mine',
        time: '7:04',
        senderName: 'Me',
        avatar: SizedBox(key: ValueKey('avatar'), width: 24, height: 24),
      ),
    );
    expect(find.byKey(const ValueKey('dm-sender-name')), findsNothing);
    expect(find.byKey(const ValueKey('avatar')), findsNothing);
  });

  testWidgets('an edited message carries the edited mark beside the time',
      (tester) async {
    await _mount(
      tester,
      const DmBubble(
        mine: false,
        body: 'Fixed typo',
        time: '7:05',
        editedLabel: 'Edited',
      ),
    );
    expect(find.byKey(const ValueKey('dm-edited')), findsOneWidget);
    expect(find.text('Edited'), findsOneWidget);
  });

  testWidgets('no edited mark on a message never edited', (tester) async {
    await _mount(
      tester,
      const DmBubble(mine: false, body: 'Original', time: '7:05'),
    );
    expect(find.byKey(const ValueKey('dm-edited')), findsNothing);
  });

  testWidgets('an unsent message shows the placeholder, never its body',
      (tester) async {
    await _mount(
      tester,
      const DmBubble(
        mine: true,
        body: 'Something I took back',
        time: '7:06',
        unsentLabel: 'You unsent a message',
      ),
    );
    expect(find.text('You unsent a message'), findsOneWidget);
    expect(find.text('Something I took back'), findsNothing);
    expect(find.byType(DmMessageText), findsNothing);
  });

  testWidgets('the seen line sits under the bubble', (tester) async {
    await _mount(
      tester,
      const DmBubble(
          mine: true, body: 'Read?', time: '7:07', seenLabel: 'Seen 7:08'),
    );
    expect(find.byKey(const ValueKey('dm-seen')), findsOneWidget);
    expect(find.text('Seen 7:08'), findsOneWidget);
  });

  testWidgets('a long press reaches the handler', (tester) async {
    var pressed = 0;
    await _mount(
      tester,
      DmBubble(
        mine: false,
        body: 'Hold me',
        time: '7:09',
        onLongPress: () => pressed++,
      ),
    );
    await tester.longPress(find.text('Hold me'));
    expect(pressed, 1);
  });

  testWidgets('a message still sending is dimmed and takes no long press',
      (tester) async {
    var pressed = 0;
    await _mount(
      tester,
      DmBubble(
        mine: true,
        body: 'Sending',
        time: '7:10',
        sending: true,
        sendingLabel: 'Sending',
        onLongPress: () => pressed++,
      ),
    );
    expect(
      find.descendant(
          of: find.byType(DmBubble), matching: find.byType(Opacity)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    await tester.longPress(find.text('Sending'), warnIfMissed: false);
    expect(pressed, 0);
  });
}
