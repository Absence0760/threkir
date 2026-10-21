import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/chat_stick_to_bottom.dart';

// Issue #1214: every streamed coach token scrolled the chat to the bottom,
// so a runner could not scroll up to read the start of a long reply.

class _Harness extends StatefulWidget {
  const _Harness({
    required this.scroll,
    required this.stick,
    required this.count,
  });

  final ScrollController scroll;
  final ChatStickToBottom stick;
  final ValueNotifier<int> count;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox(
        height: 600,
        child: Stack(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: widget.count,
              // Eager layout, unlike the coach's lazy ListView.builder, so
              // maxScrollExtent is exact the frame content grows and the
              // assertions can compare pixels to it.
              builder: (context, n, _) => SingleChildScrollView(
                controller: widget.scroll,
                child: Column(
                  children: [
                    for (var i = 0; i < n; i++)
                      SizedBox(height: 50, child: Text('Line $i')),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: JumpToLatestButton(
                  controller: widget.stick,
                  label: 'Jump to latest',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late ScrollController scroll;
  late ChatStickToBottom stick;
  late ValueNotifier<int> count;

  setUp(() {
    scroll = ScrollController();
    stick = ChatStickToBottom(scroll);
    count = ValueNotifier(40);
  });

  tearDown(() {
    stick.dispose();
    scroll.dispose();
    count.dispose();
  });

  Future<void> pumpHarness(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            disableAnimations: reduceMotion,
          ),
          child: _Harness(scroll: scroll, stick: stick, count: count),
        ),
      ),
    );
  }

  BuildContext ctx(WidgetTester tester) =>
      tester.element(find.byType(SingleChildScrollView));

  // A streamed token: content grows, then the screen asks to follow it.
  Future<void> token(WidgetTester tester, {int lines = 5}) async {
    count.value += lines;
    await tester.pump();
    final done = stick.scrollToBottom(ctx(tester));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    await done;
  }

  double gap() => scroll.position.maxScrollExtent - scroll.position.pixels;

  testWidgets('follows new content while the reader is at the bottom', (
    tester,
  ) async {
    await pumpHarness(tester);
    await token(tester);
    expect(gap(), 0);
    await token(tester);
    expect(gap(), 0);
    expect(stick.isFollowing, isTrue);
    expect(find.text('Jump to latest'), findsNothing);
  });

  testWidgets('scrolling up holds the position and offers Jump to latest', (
    tester,
  ) async {
    await pumpHarness(tester);
    await token(tester);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    final held = scroll.position.pixels;
    expect(gap(), greaterThan(48));
    expect(stick.isFollowing, isFalse);

    await token(tester);
    await token(tester);
    expect(scroll.position.pixels, held);
    expect(find.text('Jump to latest'), findsOneWidget);

    await tester.tap(find.text('Jump to latest'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(gap(), 0);
    expect(stick.isFollowing, isTrue);
    expect(find.text('Jump to latest'), findsNothing);

    await token(tester);
    expect(gap(), 0);
  });

  testWidgets('a small nudge within 48 px of the bottom keeps following', (
    tester,
  ) async {
    await pumpHarness(tester);
    await token(tester);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 30),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();
    expect(gap(), lessThanOrEqualTo(48));

    await token(tester);
    expect(gap(), 0);
    expect(find.text('Jump to latest'), findsNothing);
  });

  testWidgets('scrolling back to the bottom by hand resumes following', (
    tester,
  ) async {
    await pumpHarness(tester);
    await token(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    await token(tester);
    expect(find.text('Jump to latest'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(stick.isFollowing, isTrue);
    expect(find.text('Jump to latest'), findsNothing);

    await token(tester);
    expect(gap(), 0);
  });

  testWidgets("the runner's own turn forces a scroll down", (tester) async {
    await pumpHarness(tester);
    await token(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();

    count.value += 2;
    await tester.pump();
    final done = stick.scrollToBottom(ctx(tester), force: true);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    await done;
    expect(gap(), 0);
    expect(stick.isFollowing, isTrue);
    expect(find.text('Jump to latest'), findsNothing);
  });

  testWidgets('with reduced motion the jump lands without animating', (
    tester,
  ) async {
    await pumpHarness(tester, reduceMotion: true);
    await token(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    await token(tester);

    await tester.tap(find.text('Jump to latest'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(gap(), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
