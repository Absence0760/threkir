import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/shell_page_controller.dart';

void main() {
  Widget pages(Key key, PageController controller) => Directionality(
        textDirection: TextDirection.ltr,
        child: PageView(
          key: key,
          controller: controller,
          children: [for (var i = 0; i < 3; i++) Text('page $i')],
        ),
      );

  testWidgets('a PageView attaching opens on the page the shell has selected',
      (tester) async {
    var selected = 0;
    final controller = ShellPageController(currentPage: () => selected);
    addTearDown(controller.dispose);

    await tester.pumpWidget(pages(const ValueKey('first'), controller));
    expect(find.text('page 0'), findsOneWidget);

    selected = 2;
    controller.jumpToPage(2);
    await tester.pump();
    expect(find.text('page 2'), findsOneWidget);

    // A new PageView element on the same controller, as an ancestor changing
    // shape produces.
    await tester.pumpWidget(pages(const ValueKey('second'), controller));
    expect(controller.page, 2,
        reason: 'the remounted PageView opens on the selected page, not on '
            'the page the controller was built with');
    expect(find.text('page 2'), findsOneWidget);
    expect(find.text('page 0'), findsNothing);
  });

  testWidgets('a later selection is where the next PageView opens',
      (tester) async {
    var selected = 1;
    final controller = ShellPageController(currentPage: () => selected);
    addTearDown(controller.dispose);
    expect(controller.initialPage, 1);

    selected = 2;
    expect(controller.initialPage, 2);
    await tester.pumpWidget(pages(const ValueKey('only'), controller));
    expect(controller.page, 2);
    expect(find.text('page 2'), findsOneWidget);
  });
}
