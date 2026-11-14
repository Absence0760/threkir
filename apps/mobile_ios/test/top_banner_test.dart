import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppTabBar, KeepAliveChild, PinnedHeaderScope, RootPage;

import '../lib/widgets/stale_refresh_banner.dart';
import '../lib/widgets/top_banner.dart';
import 'worst_case_layout.dart';

/// Coverage of the top-banner notification primitive.
///
/// The banner is the canonical replacement for `ScaffoldMessenger`
/// SnackBar across the mobile app. Two load-bearing UX properties
/// the user surfaced as bugs:
///
///   1. EVERY banner must eventually disappear on its own (no
///      "stuck on screen" failure mode, even when a caller passes
///      a weird `Duration.zero` or forgets to plumb a dismiss).
///   2. Banners must be swipe-dismissible — Material SnackBar
///      gesture parity, so users don't have to wait if they've
///      already read the message.
///   3. The transient toast must NOT block taps to the UI beneath it.
///      The pill absorbs taps (for its swipe + optional action button),
///      but the empty band on either side of the centred pill is
///      click-through — otherwise a banner near the top of a screen
///      makes the widgets under it unreachable until it auto-dismisses.
class _BannerHost extends StatelessWidget {
  final void Function(BuildContext) onReady;
  const _BannerHost({required this.onReady});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (ctx) {
          // Defer the showTopBanner call to a post-frame callback so
          // an Overlay is wired up by the time we ask for one.
          WidgetsBinding.instance.addPostFrameCallback((_) => onReady(ctx));
          return Scaffold(
            appBar: AppBar(title: const Text('host')),
            body: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

void main() {
  group('showTopBanner — auto-dismiss timer', () {
    testWidgets(
      'banner disappears after the default 3 s duration',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'auto-dismiss me'),
        ));
        await tester.pump();
        // Banner is on screen.
        expect(find.text('auto-dismiss me'), findsOneWidget);
        // Tick past the 3-second default.
        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await tester.pump(); // let the overlay rebuild
        expect(
          find.text('auto-dismiss me'),
          findsNothing,
          reason: 'Default banner must dismiss after 3 s.',
        );
      },
    );

    testWidgets(
      'a banner still on screen when the test ends leaves no pending timer',
      (tester) async {
        // No assertion here on purpose: the framework's own
        // `A Timer is still pending even after the widget tree was disposed`
        // is the assertion, and it is raised from inside the test body — after
        // the harness unmounts the tree, before any `tearDown` runs. So a
        // dismissal timer that outlives the pill can only be answered by the
        // widget cancelling its own, which is what this pins.
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'left up'),
        ));
        await tester.pump();
        expect(find.text('left up'), findsOneWidget);
      },
    );

    testWidgets(
      'a banner inserted but never rendered arms no timer at all',
      (tester) async {
        // showTopBanner can only insert an OverlayEntry; the pill is built on
        // the next frame. A caller that shows one on a path the test never
        // pumps again left a timer behind for a banner nobody ever saw.
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'never rendered'),
        ));
      },
    );

    testWidgets(
      'unmounting the tree under a live banner cancels its dismissal timer',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'about to lose its tree'),
        ));
        await tester.pump();
        expect(find.text('about to lose its tree'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(find.text('about to lose its tree'), findsNothing);
      },
    );

    testWidgets(
      'banner with custom duration (1 s) dismisses on its own clock',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(
            ctx,
            'short-lived',
            duration: const Duration(seconds: 1),
          ),
        ));
        await tester.pump();
        expect(find.text('short-lived'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
        expect(find.text('short-lived'), findsNothing);
      },
    );

    testWidgets(
      'custom duration > max ceiling is clamped — banner never sticks '
      'past kTopBannerMaxDuration',
      (tester) async {
        // The hard ceiling defence against a degenerate caller (a
        // refactor that drops a `Duration(days: 1)` accidentally).
        // The clamp guarantees the banner always disappears in
        // bounded time regardless of caller mistakes.
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(
            ctx,
            'long-but-clamped',
            duration: const Duration(days: 1),
          ),
        ));
        await tester.pump();
        expect(find.text('long-but-clamped'), findsOneWidget);
        // Pump past the max ceiling (6 s + a bit).
        await tester.pump(kTopBannerMaxDuration);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(
          find.text('long-but-clamped'),
          findsNothing,
          reason:
              'Banner must NOT outlive kTopBannerMaxDuration even if the '
              'caller passed a 1-day duration.',
        );
      },
    );

    testWidgets(
      'kTopBannerMaxDuration constant pinned at 6 s',
      (tester) async {
        // Source-pinned so a refactor that silently widens it
        // (defeating the "always eventually dismiss" property) gets
        // caught at test time.
        expect(kTopBannerMaxDuration, const Duration(seconds: 6));
      },
    );

    testWidgets(
      'a new banner coalesces — the old one disappears immediately, '
      'the new one starts its own timer',
      (tester) async {
        late BuildContext savedCtx;
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) {
            savedCtx = ctx;
            showTopBanner(ctx, 'first');
          },
        ));
        await tester.pump();
        expect(find.text('first'), findsOneWidget);

        // Fire a second banner — single-banner semantics mirror
        // SnackBar; the user shouldn't see two stacked.
        showTopBanner(savedCtx, 'second');
        await tester.pump();
        expect(find.text('first'), findsNothing);
        expect(find.text('second'), findsOneWidget);

        // The second banner has its OWN fresh 3 s timer.
        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await tester.pump();
        expect(find.text('second'), findsNothing);
      },
    );
  });

  group('showTopBanner — swipe-to-dismiss', () {
    testWidgets(
      'horizontal fling dismisses the banner before its timer fires',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(
            ctx,
            'swipe me away',
            duration: const Duration(seconds: 10),
          ),
        ));
        await tester.pump();
        expect(find.text('swipe me away'), findsOneWidget);

        // Fling left across the banner.
        await tester.fling(
          find.text('swipe me away'),
          const Offset(-400, 0),
          1000,
        );
        // Let the Dismissible animation complete.
        await tester.pumpAndSettle();
        expect(
          find.text('swipe me away'),
          findsNothing,
          reason: 'A horizontal fling must dismiss the banner — Material '
              'SnackBar gesture parity.',
        );
      },
    );

    testWidgets(
      'swipe right also dismisses (DismissDirection.horizontal)',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(
            ctx,
            'rightward swipe',
            duration: const Duration(seconds: 10),
          ),
        ));
        await tester.pump();
        await tester.fling(
          find.text('rightward swipe'),
          const Offset(400, 0),
          1000,
        );
        await tester.pumpAndSettle();
        expect(find.text('rightward swipe'), findsNothing);
      },
    );
  });

  group('showTopBanner — taps pass through the empty band', () {
    testWidgets(
      'a tap in the banner band but outside the pill reaches the widget '
      'below',
      (tester) async {
        var underlyingTapped = 0;
        // No AppBar: the banner (topInset ~ 12 with no Scaffold app bar in
        // scope) renders over the top of the body, so the full-area
        // tappable genuinely underlies the pill's band. An AppBar here
        // would sit beneath the pill and absorb the pass-through tap,
        // masking the behaviour under test.
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (ctx) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => showTopBanner(ctx, 'hi'));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => underlyingTapped++,
                child: const SizedBox.expand(),
              );
            },
          ),
        ));
        await tester.pump(); // run the post-frame callback → insert entry
        await tester.pump(); // let the overlay build the pill
        expect(find.text('hi'), findsOneWidget);

        // The pill is centred within the left:16/right:16 band, so there
        // is an empty band to its left. Before the fix the two
        // Dismissibles wrapped the full-width Center, sizing their opaque
        // hit area to the whole band and swallowing this tap; now they
        // wrap only the pill, so the band is click-through.
        final pillRect = tester.getRect(
          find.byKey(const ValueKey('top_banner:up:hi')),
        );
        expect(
          pillRect.left,
          greaterThan(40),
          reason: 'pill should be centred, leaving an empty left band',
        );

        await tester.tapAt(Offset(20, pillRect.center.dy));
        await tester.pump();
        expect(
          underlyingTapped,
          1,
          reason:
              'A tap in the empty banner band must reach the widget beneath '
              'the banner — the transient toast must not block the UI.',
        );

        // A tap ON the pill is absorbed (the Dismissible is opaque over
        // the pill), so it must NOT also fire the widget beneath.
        await tester.tapAt(pillRect.center);
        await tester.pump();
        expect(
          underlyingTapped,
          1,
          reason: 'A tap on the pill itself is absorbed, not passed through.',
        );
      },
    );
  });

  group('showTopBanner — position', () {
    // 24 logical px of status bar: the app bar spans it, and the pill
    // sits the gap under the app bar, not the status bar again lower.
    void statusBar(WidgetTester tester) {
      tester.view.padding = FakeViewPadding(top: 24 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetPadding);
    }

    testWidgets('under a status bar, the pill sits 12 px under the app bar',
        (tester) async {
      statusBar(tester);
      late BuildContext screen;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('host')),
          body: Builder(builder: (ctx) {
            screen = ctx;
            return const SizedBox.expand();
          }),
        ),
      ));
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(appBarBottom, 24 + kToolbarHeight);

      showTopBanner(screen, 'here');
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('top_banner:up:here'))).dy,
          appBarBottom + 12);
      hideTopBanner();
      await tester.pump();
    });

    testWidgets('under a status bar, said from the root navigator, the pill '
        'sits 12 px under the top screen\'s app bar', (tester) async {
      statusBar(tester);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          appBar: AppBar(title: const Text('host')),
          body: const SizedBox.expand(),
        ),
      ));
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;

      showTopBanner(navigator.currentContext!, 'root');
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('top_banner:up:root'))).dy,
          appBarBottom + 12);
      hideTopBanner();
      await tester.pump();
    });

    testWidgets('under a status bar with no app bar, the pill sits 12 px '
        'under the status bar', (tester) async {
      statusBar(tester);
      late BuildContext screen;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) {
            screen = ctx;
            return const SizedBox.expand();
          }),
        ),
      ));

      showTopBanner(screen, 'bare');
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('top_banner:up:bare'))).dy,
          24 + 12);
      hideTopBanner();
      await tester.pump();
    });

    testWidgets('an AppBar-less screen whose body is in a SafeArea keeps the '
        'pill under the status bar', (tester) async {
      statusBar(tester);
      late BuildContext screen;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Builder(builder: (ctx) {
              screen = ctx;
              return const SizedBox.expand();
            }),
          ),
        ),
      ));
      expect(MediaQuery.paddingOf(screen).top, 0,
          reason: 'the SafeArea strips the caller\'s top padding');

      showTopBanner(screen, 'safe');
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('top_banner:up:safe'))).dy,
          24 + 12);
      hideTopBanner();
      await tester.pump();
    });

    testWidgets('a Scaffold nested in another one\'s body puts the pill under '
        'the outer app bar', (tester) async {
      statusBar(tester);
      late BuildContext tab;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('shell')),
          body: Scaffold(
            body: Builder(builder: (ctx) {
              tab = ctx;
              return const SizedBox.expand();
            }),
          ),
        ),
      ));
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(appBarBottom, 24 + kToolbarHeight);

      showTopBanner(tab, 'nested');
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('top_banner:up:nested'))).dy,
          appBarBottom + 12);
      hideTopBanner();
      await tester.pump();
    });

    testWidgets('a nested Scaffold with its own app bar puts the pill under the '
        'lower one', (tester) async {
      statusBar(tester);
      late BuildContext tab;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('shell')),
          body: Scaffold(
            appBar: AppBar(title: const Text('tab')),
            body: Builder(builder: (ctx) {
              tab = ctx;
              return const SizedBox.expand();
            }),
          ),
        ),
      ));
      final inner =
          tester.getBottomLeft(find.widgetWithText(AppBar, 'tab')).dy;
      expect(inner, 24 + 2 * kToolbarHeight);

      showTopBanner(tab, 'inner');
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('top_banner:up:inner'))).dy,
          inner + 12);
      hideTopBanner();
      await tester.pump();
    });

    testWidgets('a screen State\'s own context, above the Scaffold it builds, '
        'puts the pill under that Scaffold\'s app bar', (tester) async {
      statusBar(tester);
      late BuildContext screen;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          screen = ctx;
          return Scaffold(
            appBar: AppBar(title: const Text('host')),
            body: const SizedBox.expand(),
          );
        }),
      ));
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;

      showTopBanner(screen, 'above');
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('top_banner:up:above'))).dy,
          appBarBottom + 12);
      hideTopBanner();
      await tester.pump();
    });

    testWidgets(
      'said from the root navigator, the pill sits under the app bar of the '
      'screen on top',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            appBar: AppBar(title: const Text('host')),
            body: const SizedBox.expand(),
          ),
        ));
        navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('pushed')),
            body: const SizedBox.expand(),
          ),
        ));
        await tester.pumpAndSettle();

        showTopBanner(navigator.currentContext!, 'late');
        await tester.pump();
        final pill = find.byKey(const ValueKey('top_banner:up:late'));
        expect(tester.getTopLeft(pill).dy,
            greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppBar).last).dy));
        expect(navigator.currentState!.canPop(), isTrue,
            reason: 'reading the top route must not pop it');
        hideTopBanner();
        await tester.pump();
      },
    );
  });

  // Decisions § 2517 put each root page's title row under the status bar,
  // with no app bar above it. A banner said from anywhere but the root
  // page's own body — a pushed page, the navigator after a screen closed, a
  // service, a root kept alive but hidden in the shell — found no header and
  // sat under the status bar, over the visible page's title row; or it found
  // a hidden root's header and sat under that one (issue #1374).
  group('showTopBanner — under a root page', () {
    void statusBar(WidgetTester tester) {
      tester.view.padding = FakeViewPadding(
        top: 24 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
    }

    // The bottom of [page]'s pinned header: its title row, or its tab strip.
    double headerBottom(WidgetTester tester, Finder page) {
      final scope = tester.widget<PinnedHeaderScope>(
        find.descendant(of: page, matching: find.byType(PinnedHeaderScope)),
      );
      final box =
          scope.headerKey.currentContext!.findRenderObject()! as RenderBox;
      return box.localToGlobal(Offset(0, box.size.height)).dy;
    }

    double pillTop(WidgetTester tester, String message) =>
        tester.getTopLeft(find.byKey(ValueKey('top_banner:up:$message'))).dy;

    Future<void> hide(WidgetTester tester) async {
      hideTopBanner();
      await tester.pump();
    }

    Widget plainRoot({
      String title = 'You',
      void Function(BuildContext)? onBody,
    }) => RootPage(
      title: title,
      body: Builder(
        builder: (ctx) {
          onBody?.call(ctx);
          return ListView(children: const [Text('row')]);
        },
      ),
    );

    testWidgets('said from the root page, the pill sits under its title row', (
      tester,
    ) async {
      statusBar(tester);
      late BuildContext body;
      await tester.pumpWidget(
        MaterialApp(home: plainRoot(onBody: (ctx) => body = ctx)),
      );
      final edge = headerBottom(tester, find.byType(RootPage));
      expect(edge, greaterThan(tester.getRect(find.text('You').first).bottom));

      showTopBanner(body, 'root');
      await tester.pump();
      expect(pillTop(tester, 'root'), edge + 12);
      await hide(tester);
    });

    testWidgets('said from the navigator with a root page on top, the pill '
        'sits under its title row', (tester) async {
      statusBar(tester);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: plainRoot()),
      );
      final edge = headerBottom(tester, find.byType(RootPage));

      showTopBanner(navigator.currentContext!, 'service');
      await tester.pump();
      expect(pillTop(tester, 'service'), edge + 12);
      await hide(tester);
    });

    testWidgets('said from a page pushed over a root page, the pill sits under '
        'the pushed page\'s header, not the hidden root\'s', (tester) async {
      statusBar(tester);
      final navigator = GlobalKey<NavigatorState>();
      // A title that wraps, so the root's header is taller than an app bar.
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: plainRoot(
            title:
                'A root page title long enough to wrap onto several '
                'lines of the large heading',
          ),
        ),
      );
      final rootEdge = headerBottom(tester, find.byType(RootPage));
      expect(
        rootEdge,
        greaterThan(24 + kToolbarHeight),
        reason:
            'the root header must reach below the pushed app bar for '
            'this case to tell them apart',
      );

      late BuildContext pushed;
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('detail')),
            body: Builder(
              builder: (ctx) {
                pushed = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      showTopBanner(pushed, 'detail');
      await tester.pump();
      expect(
        pillTop(tester, 'detail'),
        tester.getBottomLeft(find.byType(AppBar)).dy + 12,
      );
      await hide(tester);
    });

    testWidgets('said from a bare page pushed over a root page, the pill sits '
        'under the status bar, not the hidden root\'s title', (tester) async {
      statusBar(tester);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: plainRoot()),
      );
      late BuildContext pushed;
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Builder(
              builder: (ctx) {
                pushed = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(RootPage),
        findsNothing,
        reason: 'the root is under an opaque route',
      );

      showTopBanner(pushed, 'bare');
      await tester.pump();
      expect(pillTop(tester, 'bare'), 24 + 12);
      await hide(tester);
    });

    testWidgets('said after the screen that started the work has closed, the '
        'pill sits under the root page left showing', (tester) async {
      statusBar(tester);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: plainRoot()),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('detail')),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      final edge = headerBottom(tester, find.byType(RootPage));

      // What a save that finishes after its screen is popped does: it has
      // only the navigator's context left.
      showTopBanner(navigator.currentContext!, 'late');
      await tester.pump();
      expect(pillTop(tester, 'late'), edge + 12);
      await hide(tester);
    });

    testWidgets('with several roots kept alive, only the visible one\'s header '
        'counts, whichever root the banner is said from', (tester) async {
      statusBar(tester);
      final navigator = GlobalKey<NavigatorState>();
      final pages = PageController();
      addTearDown(pages.dispose);
      late BuildContext hiddenTab;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: PageView(
              controller: pages,
              children: [
                KeepAliveChild(
                  child: DefaultTabController(
                    length: 2,
                    child: Builder(
                      builder: (context) => RootPage.tabbed(
                        title: 'Fitness',
                        controller: DefaultTabController.of(context),
                        labels: const ['Runs', 'Routes'],
                        children: [
                          Builder(
                            builder: (ctx) {
                              hiddenTab = ctx;
                              return const SizedBox.expand();
                            },
                          ),
                          const SizedBox.expand(),
                        ],
                      ),
                    ),
                  ),
                ),
                KeepAliveChild(child: plainRoot()),
              ],
            ),
          ),
        ),
      );
      final hubEdge = headerBottom(
        tester,
        find.widgetWithText(RootPage, 'Fitness'),
      );
      pages.jumpToPage(1);
      await tester.pump();
      expect(
        find.byType(AppTabBar, skipOffstage: false),
        findsOneWidget,
        reason: 'the hub is kept alive, header and all',
      );
      final edge = headerBottom(tester, find.widgetWithText(RootPage, 'You'));
      expect(
        hubEdge,
        greaterThan(edge),
        reason:
            'the hidden hub\'s strip reaches lower than the visible '
            'root\'s title row, so measuring it would show',
      );

      showTopBanner(navigator.currentContext!, 'from the navigator');
      await tester.pump();
      expect(pillTop(tester, 'from the navigator'), edge + 12);

      // A load in the hidden hub that fails while another root shows.
      showTopBanner(hiddenTab, 'from the hidden hub');
      await tester.pump();
      expect(pillTop(tester, 'from the hidden hub'), edge + 12);
      await hide(tester);
    });
  });

  group('hideTopBanner', () {
    testWidgets('programmatic dismiss works alongside the timer / swipe',
        (tester) async {
      await tester.pumpWidget(_BannerHost(
        onReady: (ctx) {
          showTopBanner(
            ctx,
            'imperative dismiss',
            duration: const Duration(seconds: 10),
          );
        },
      ));
      await tester.pump();
      expect(find.text('imperative dismiss'), findsOneWidget);
      hideTopBanner();
      await tester.pump();
      expect(find.text('imperative dismiss'), findsNothing);
    });

    testWidgets('hideTopBanner is a no-op when nothing is on screen',
        (tester) async {
      await tester.pumpWidget(_BannerHost(onReady: (_) {}));
      await tester.pump();
      // Should not throw.
      hideTopBanner();
      await tester.pump();
    });
  });

  group('showTopBanner — accessibility', () {
    testWidgets(
      'the banner message is a live region so screen readers announce it',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'sync failed'),
        ));
        await tester.pump();

        final liveRegion = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        );
        expect(
          liveRegion,
          findsOneWidget,
          reason: 'The transient banner must be a live region — it replaced '
              'Material SnackBar, which auto-announced to TalkBack/VoiceOver; '
              'without it a blind user gets no feedback on the failures that '
              'flow through here.',
        );
        // The announced node carries the message.
        expect(
          find.descendant(of: liveRegion, matching: find.text('sync failed')),
          findsOneWidget,
        );

        // Drain the auto-dismiss timer so no pending timer trips the framework.
        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await tester.pump();
      },
    );
  });

  // #1374 A11Y-15: the Undo / Retry action was a shrink-wrapped TextButton
  // about 28 dp tall, on a banner that times out.
  testWidgets('the banner action is a 48 dp target', (tester) async {
    await tester.pumpWidget(_BannerHost(
      onReady: (ctx) => showTopBanner(ctx, 'Run deleted',
          actionLabel: 'Undo', onAction: () {}),
    ));
    await tester.pump();
    final action = find.byKey(const Key('topBannerAction'));
    expect(action, findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    await tester.pump(kTopBannerMaxDuration);
    await tester.pump(const Duration(milliseconds: 500));
  });

  // Issue #1374: on a hub the tab strip sits under the large title, not in
  // the app bar, so the offline banner placed under the bar alone covered the
  // strip at 2x text.
  worstCaseTestWidgets('Offline banner on a hub', (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: DefaultTabController(
        length: 2,
        child: Builder(
          builder: (context) => RootPage.tabbed(
            title: 'Fitness',
            controller: DefaultTabController.of(context),
            labels: const ['Runs', 'Routes'],
            children: [
              Builder(
                builder: (tab) => Center(
                  child: TextButton(
                    onPressed: () =>
                        showStaleRefreshBanner(tab, TimeoutException('x')),
                    child: const Text('refresh'),
                  ),
                ),
              ),
              const SizedBox(),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('refresh'));
    await tester.pump();
    final pill = find.text(l10nFor(locale).commonStaleOffline);
    expect(pill, findsOneWidget);
    expect(tester.getRect(pill).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppTabBar)).bottom),
        reason: 'the banner starts below the tab strip');
    await tester.pump(kTopBannerMaxDuration);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
