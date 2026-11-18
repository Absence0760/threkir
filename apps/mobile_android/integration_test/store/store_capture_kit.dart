import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// How the store capture photographs a screen and says where its sections
/// sit, for assets/store/render_panels.py (README.md, "What the capture suite
/// writes beside its PNGs").
///
/// A capture is the pushed screen's own layer, rendered by
/// [RenderRepaintBoundary.toImage] at the pixel ratio the panel needs, not a
/// platform screenshot: the result is the same on the Android emulator and
/// the iOS simulator, carries no status bar, navigation bar or home
/// indicator, and can be laid out at a logical width the device does not
/// have (the 320 dp run-detail column, spec "Screen scale"). The PNGs, the
/// section bounds and the numbers travel to the host in the test's report
/// data, and store_screenshots_driver.dart writes them out.

/// The run-detail and Progress captures are laid out 320 dp wide and drawn
/// so that column fills the panel card: 960 px for Play, 1173 px for the
/// App Store's 6.9" frame.
const kColumnDp = 320.0;

/// A captured section, in global logical pixels.
typedef SectionRects = Map<String, Rect>;

class StoreCapture {
  StoreCapture({
    required this.name,
    required this.png,
    required this.size,
    required this.pixelRatio,
    required this.theme,
    required this.sections,
    required this.colours,
    required this.forbidden,
  });

  final String name;
  final Uint8List png;
  final Size size; // capture pixels
  final double pixelRatio;
  final String theme;
  final Map<String, Rect> sections; // capture pixels
  final Map<String, String> colours;
  final Map<String, Rect> forbidden; // capture pixels

  static List<double> _box(Rect r) => [
        for (final v in [r.left, r.top, r.width, r.height])
          (v * 10).roundToDouble() / 10,
      ];

  Map<String, Object?> toBounds() => {
        'file': '$name.png',
        'theme': theme,
        'dpr': pixelRatio,
        'size': [size.width.round(), size.height.round()],
        'sections': {
          for (final e in sections.entries) e.key: _box(e.value),
        },
        if (colours.isNotEmpty) 'colours': colours,
        if (forbidden.isNotEmpty)
          'forbidden': {
            for (final e in forbidden.entries) e.key: _box(e.value),
          },
      };
}

/// Every capture of one run, plus numbers.json, as the report data the
/// driver writes out.
class StoreCaptureSet {
  final captures = <StoreCapture>[];

  Map<String, Object?> reportData(Map<String, Object?> numbers) => {
        'store_files': {
          for (final c in captures) '${c.name}.png': base64Encode(c.png),
        },
        'store_bounds': {
          'schema': 1,
          'captures': {for (final c in captures) c.name: c.toBounds()},
        },
        'store_numbers': numbers,
      };
}

/// Wraps a pushed screen so [captureScreen] can render its layer.
Widget captureBoundary(GlobalKey key, Widget screen) =>
    RepaintBoundary(key: key, child: screen);

/// The union of every match of [finders], in global logical pixels. Fails
/// when one of them matches nothing.
Rect unionRect(WidgetTester tester, String section, List<Finder> finders) {
  Rect? out;
  for (final f in finders) {
    final matches = f.evaluate().toList();
    if (matches.isEmpty) {
      fail('section $section: nothing matches $f on screen');
    }
    for (final e in matches) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize) {
        fail('section $section: $f has no laid-out box');
      }
      final r = box.localToGlobal(Offset.zero) & box.size;
      out = out == null ? r : out.expandToInclude(r);
    }
  }
  return out!;
}

/// The first vertical scrollable inside [screen]: its page list, never a
/// horizontal chip row or carousel that happens to come first.
Finder verticalListOf(Type screen) => find
    .descendant(
        of: find.byType(screen),
        matching: find.byWidgetPredicate((w) =>
            w is Scrollable &&
            axisDirectionToAxis(w.axisDirection) == Axis.vertical))
    .first;

/// Scroll [scrollable] down until [target] is built, by moving its position
/// rather than dragging: a drag starts at the list's centre, where a screen's
/// map can take it as a pan and leave the list where it was (run 44312432462
/// spent all 200 drags of `scrollUntilVisible` that way at text scale 1.5).
Future<void> scrollUntilBuilt(
    WidgetTester tester, Finder scrollable, Finder target,
    {double stepDp = 300}) async {
  final position = tester.state<ScrollableState>(scrollable).position;
  while (target.evaluate().isEmpty) {
    if (position.pixels >= position.maxScrollExtent) {
      fail('scrolled to the end of the list (${position.pixels.round()} dp) '
          'without building ${target.toString(describeSelf: true)}');
    }
    position.jumpTo(
        math.min(position.pixels + stepDp, position.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scroll the nearest scrollable so [target] sits [marginDp] below its top,
/// leaving room for a crop's top pad without reaching the app bar.
Future<void> revealNearTop(WidgetTester tester, Finder target,
    {double marginDp = 32}) async {
  final element = target.evaluate().first;
  await Scrollable.ensureVisible(element, alignment: 0);
  await tester.pump();
  final position = Scrollable.of(element).position;
  position.jumpTo(math.max(position.minScrollExtent, position.pixels - marginDp));
  await tester.pump();
}

/// The visible area of the scrollable that holds [inside], global logical.
Rect viewportOf(WidgetTester tester, Finder inside) => tester.getRect(
    find.ancestor(of: inside, matching: find.byType(Scrollable)).first);

/// Render the boundary at [boundary] at [pixelRatio] and record where each
/// section sits in it.
///
/// Every section must lie wholly inside [viewport] (where one is given), so
/// nothing in a crop is clipped by the list or hidden under the app bar.
/// [colourAt] samples a section's fill from the rendered pixels, at a dp
/// offset from its top-left, for the renderer's lifts and callouts.
/// [forbidden] names widgets that must never appear inside a crop, such as
/// the coach's usage banner: each one on screen fails the capture if it
/// overlaps a section, and is recorded so the renderer refuses the same.
Future<StoreCapture> captureScreen(
  WidgetTester tester, {
  required String name,
  required GlobalKey boundary,
  required double pixelRatio,
  required Map<String, List<Finder>> sections,
  Map<String, Rect>? viewports,
  Map<String, (String, Offset)> colourAt = const {},
  Map<String, Finder> forbidden = const {},
}) async {
  final context = boundary.currentContext;
  if (context == null) fail('$name: the capture boundary is not mounted');
  final rb = context.findRenderObject()! as RenderRepaintBoundary;
  final origin = rb.localToGlobal(Offset.zero);
  final local = Offset.zero & rb.size;
  final theme =
      Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';

  Rect toCapture(Rect global) => Rect.fromLTRB(
        (global.left - origin.dx) * pixelRatio,
        (global.top - origin.dy) * pixelRatio,
        (global.right - origin.dx) * pixelRatio,
        (global.bottom - origin.dy) * pixelRatio,
      );

  final logical = <String, Rect>{};
  for (final e in sections.entries) {
    final r = unionRect(tester, e.key, e.value);
    final inBoundary = r.shift(-origin);
    if (!_contains(local, inBoundary)) {
      fail('$name: section ${e.key} ($inBoundary) runs outside the '
          '${rb.size} screen; scroll it into view or make the view taller');
    }
    final viewport = viewports?[e.key];
    if (viewport != null && !_contains(viewport, r)) {
      fail('$name: section ${e.key} ($r) is not wholly inside its scroll '
          'viewport ($viewport), so part of it is clipped or under the app bar');
    }
    logical[e.key] = r;
  }

  final hidden = <String, Rect>{};
  for (final e in forbidden.entries) {
    for (final element in e.value.evaluate()) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (!r.overlaps(local.shift(origin))) continue;
      for (final s in logical.entries) {
        if (r.overlaps(s.value)) {
          fail('$name: ${e.key} is inside section ${s.key}; crop it out, '
              'never hide it in the app (spec, demo data item 2)');
        }
      }
      hidden[e.key] = toCapture(r.intersect(local.shift(origin)));
    }
  }

  final image = await rb.toImage(pixelRatio: pixelRatio);
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final size = Size(image.width.toDouble(), image.height.toDouble());

  final colours = <String, String>{};
  for (final e in colourAt.entries) {
    final (section, insetDp) = e.value;
    final r = logical[section];
    if (r == null) fail('$name: colour ${e.key} samples unknown $section');
    final at = toCapture(r).topLeft + insetDp * pixelRatio;
    final x = at.dx.round().clamp(0, image.width - 1);
    final y = at.dy.round().clamp(0, image.height - 1);
    final i = (y * image.width + x) * 4;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    colours[e.key] =
        '#${hex(rgba.getUint8(i))}${hex(rgba.getUint8(i + 1))}${hex(rgba.getUint8(i + 2))}';
  }
  image.dispose();

  return StoreCapture(
    name: name,
    png: png,
    size: size,
    pixelRatio: pixelRatio,
    theme: theme,
    sections: {
      for (final e in logical.entries)
        e.key: toCapture(e.value).intersect(Offset.zero & size),
    },
    colours: colours,
    forbidden: hidden,
  );
}

bool _contains(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

/// The visible strings under [of], in build order: what the screen says.
List<String> textsUnder(WidgetTester tester, Finder of) => [
      for (final t in tester.widgetList<Text>(
          find.descendant(of: of, matching: find.byType(Text))))
        t.data ?? t.textSpan?.toPlainText() ?? '',
    ];
