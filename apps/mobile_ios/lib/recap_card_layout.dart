/// Where everything sits on the recap share image, for both aspects. Mirrors
/// `apps/web/src/lib/share/recap_card_layout.ts`, which the web SVG reads, so
/// a square card and a story look the same on either platform. Every y is a
/// text baseline in a canvas [RecapCardLayout.width] x
/// [RecapCardLayout.height] pixels across.
///
/// The story keeps its content clear of the top and bottom bands a story
/// viewer draws its own UI over, and carries the site address in the space
/// below the grid; the square card has no footer.
library;

enum RecapCardAspect { square, story }

class RecapCardLayout {
  final double width;
  final double height;
  final double pad;
  final double brandY;
  final double kickerY;
  final double heroY;
  final double subheadY;
  final double gridTop;
  final double colW;
  final double rowH;

  /// Gap from a cell's label baseline down to its value baseline.
  final double valueDy;
  final double? footerY;

  const RecapCardLayout._({
    required this.width,
    required this.height,
    required this.pad,
    required this.brandY,
    required this.kickerY,
    required this.heroY,
    required this.subheadY,
    required this.gridTop,
    required this.colW,
    required this.rowH,
    required this.valueDy,
    required this.footerY,
  });
}

const double _width = 1080;
const double _pad = 72;

RecapCardLayout recapCardLayout(RecapCardAspect aspect) {
  final story = aspect == RecapCardAspect.story;
  final height = story ? 1920.0 : _width;
  final top = story ? 360.0 : _pad;
  final gridGap = story ? 160.0 : 0.0;
  return RecapCardLayout._(
    width: _width,
    height: height,
    pad: _pad,
    brandY: top + 28,
    kickerY: top + 110,
    heroY: top + 280,
    subheadY: top + 350,
    gridTop: top + 440 + gridGap,
    colW: (_width - _pad * 2) / 2,
    rowH: story ? 200 : 150,
    valueDy: 58,
    footerY: story ? height - 300 : null,
  );
}

/// The label and value baselines of stat cell [index] in the two-column grid.
({double x, double labelY, double valueY}) recapCellOrigin(
  RecapCardLayout layout,
  int index,
) {
  final col = index % 2;
  final row = index ~/ 2;
  final labelY = layout.gridTop + row * layout.rowH;
  return (
    x: layout.pad + col * layout.colW,
    labelY: labelY,
    valueY: labelY + layout.valueDy,
  );
}
