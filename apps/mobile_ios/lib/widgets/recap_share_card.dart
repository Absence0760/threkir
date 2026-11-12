import 'dart:async' show unawaited;
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart' show ChoiceChipOption, ChoiceChipRow;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../preferences.dart';
import '../recap.dart';
import '../recap_card_layout.dart';
import '../share_sheet.dart';
import '../web_base_url.dart';
import 'capture_png.dart';
import 'top_banner.dart';

// The web card's dark palette (`og_card_palette.ts` OG_CARD_DARK), so the two
// platforms post the same picture.
const _bg = Color(0xFF121117);
const _brand = Color(0xFFF08A5D);
const _hero = Color(0xFFFFFFFF);
const _label = Color(0xFFA9A4B6);
const _stat = Color(0xFFE4E1EA);

/// One labelled number on the recap image.
typedef RecapCardCell = ({String label, String value});

/// The text the recap image prints, already localised and formatted. Built by
/// [recapCardText] so the painter only places strings.
class RecapCardText {
  final String kicker;
  final String hero;
  final String subhead;
  final List<RecapCardCell> cells;
  final String footer;

  const RecapCardText({
    required this.kicker,
    required this.hero,
    required this.subhead,
    required this.cells,
    required this.footer,
  });
}

String _wholeDistance(double metres, DistanceUnit unit) {
  final v = unit == DistanceUnit.mi ? metres / kMetresPerMile : metres / 1000;
  return '${formatFixed(v, 0, activeLocaleTag)} ${UnitFormat.distanceLabel(unit)}';
}

String _hoursMinutes(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// The same six cells, in the same order, as the web card
/// (`recap_share_image.ts`).
RecapCardText recapCardText(
  AppLocalizations l10n,
  YearInRunningRecap recap,
  DistanceUnit unit,
  String periodLabel,
) {
  final activeMonths = recap.monthly.where((m) => m.runCount > 0).length;
  return RecapCardText(
    kicker: l10n.recapCardKicker(periodLabel).toUpperCase(),
    hero: _wholeDistance(recap.totalDistanceM, unit),
    subhead: l10n.recapCardAcrossRuns(recap.runCount),
    cells: [
      (
        label: l10n.recapLongestRunLabel,
        value: _wholeDistance(recap.longestRunM, unit),
      ),
      (label: l10n.recapCardOnFoot, value: _hoursMinutes(recap.totalDurationS)),
      (
        label: l10n.recapBestStreakLabel,
        value: l10n.recapCardStreakDays(recap.bestStreakDays),
      ),
      (
        label: l10n.recapTopWeekLabel,
        value: _wholeDistance(recap.topWeek?.distanceM ?? 0, unit),
      ),
      (
        label: l10n.recapCardClimbed,
        value: UnitFormat.elevation(recap.totalElevationM, unit),
      ),
      (label: l10n.recapCardActiveMonths, value: '$activeMonths / 12'),
    ],
    footer: 'threkir.com',
  );
}

/// The recap share image at its fixed canvas size, laid out by
/// [recapCardLayout]. Rasterise at pixel ratio 1 for a 1080 px wide PNG.
class RecapShareCard extends StatelessWidget {
  final RecapCardText text;
  final RecapCardAspect aspect;

  const RecapShareCard({super.key, required this.text, required this.aspect});

  @override
  Widget build(BuildContext context) {
    final layout = recapCardLayout(aspect);
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: CustomPaint(painter: _RecapCardPainter(text, layout)),
    );
  }
}

class _RecapCardPainter extends CustomPainter {
  final RecapCardText text;
  final RecapCardLayout layout;

  _RecapCardPainter(this.text, this.layout);

  void _text(
    Canvas canvas,
    String value,
    double x,
    double baseline, {
    required double size,
    required FontWeight weight,
    required Color color,
    double spacing = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: spacing,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: layout.width - x - layout.pad / 2);
    final ascent = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.paint(canvas, Offset(x, baseline - ascent));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    canvas.drawRect(
      Offset.zero & Size(l.width, l.height),
      Paint()..color = _bg,
    );
    _text(
      canvas,
      'Threkir',
      l.pad,
      l.brandY,
      size: 40,
      weight: FontWeight.w800,
      color: _brand,
    );
    _text(
      canvas,
      text.kicker,
      l.pad,
      l.kickerY,
      size: 34,
      weight: FontWeight.w700,
      color: _label,
      spacing: 3,
    );
    _text(
      canvas,
      text.hero,
      l.pad,
      l.heroY,
      size: 200,
      weight: FontWeight.w900,
      color: _hero,
    );
    _text(
      canvas,
      text.subhead,
      l.pad,
      l.subheadY,
      size: 44,
      weight: FontWeight.w600,
      color: _stat,
    );
    for (var i = 0; i < text.cells.length; i++) {
      final o = recapCellOrigin(l, i);
      final cell = text.cells[i];
      _text(
        canvas,
        cell.label.toUpperCase(),
        o.x,
        o.labelY,
        size: 28,
        weight: FontWeight.w700,
        color: _label,
        spacing: 2,
      );
      _text(
        canvas,
        cell.value,
        o.x,
        o.valueY,
        size: 64,
        weight: FontWeight.w800,
        color: _stat,
      );
    }
    final footerY = l.footerY;
    if (footerY != null) {
      _text(
        canvas,
        text.footer,
        l.pad,
        footerY,
        size: 36,
        weight: FontWeight.w700,
        color: _brand,
      );
    }
  }

  @override
  bool shouldRepaint(_RecapCardPainter old) =>
      old.text != text || old.layout != layout;
}

/// The web recap page the Video option opens, with `video=1` asking it to
/// start the slideshow export (decisions § 2269): the phone has no video
/// encoder of its own, and the browser hands the file to the OS share sheet.
Uri recapVideoExportUrl(int year, {int? month, String? webBase}) =>
    Uri.parse(webPageUrl(
        month == null ? '/recap/$year?video=1' : '/recap/$year/$month?video=1',
        override: webBase));

/// Opens a URL outside the app; returns whether anything took it.
typedef RecapShareUrlOpener = Future<bool> Function(Uri url);

Future<bool> _openExternally(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Opens a sheet that shares the recap as a square or story image, as a video
/// made on the web ([videoUrl]), or as the text summary it shared before there
/// was an image. [shareText] is that text path, kept as the caller wrote it.
Future<void> showRecapShareSheet(
  BuildContext context, {
  required RecapCardText text,
  required String fileStem,
  required String subject,
  required Future<void> Function() shareText,
  required Uri videoUrl,
  RecapShareUrlOpener openUrl = _openExternally,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RecapShareSheet(
      text: text,
      fileStem: fileStem,
      subject: subject,
      shareText: shareText,
      videoUrl: videoUrl,
      openUrl: openUrl,
    ),
  );
}

enum _RecapShareStyle { square, story, video }

class _RecapShareSheet extends StatefulWidget {
  final RecapCardText text;
  final String fileStem;
  final String subject;
  final Future<void> Function() shareText;
  final Uri videoUrl;
  final RecapShareUrlOpener openUrl;

  const _RecapShareSheet({
    required this.text,
    required this.fileStem,
    required this.subject,
    required this.shareText,
    required this.videoUrl,
    required this.openUrl,
  });

  @override
  State<_RecapShareSheet> createState() => _RecapShareSheetState();
}

class _RecapShareSheetState extends State<_RecapShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  _RecapShareStyle _style = _RecapShareStyle.square;
  bool _busy = false;

  RecapCardAspect get _aspect => _style == _RecapShareStyle.story
      ? RecapCardAspect.story
      : RecapCardAspect.square;

  Future<void> _openVideoExport() async {
    var opened = false;
    try {
      opened = await widget.openUrl(widget.videoUrl);
    } catch (e) {
      debugPrint('Failed to open the recap video export: $e');
    }
    if (!opened && mounted) {
      showTopBanner(context, AppLocalizations.of(context).shareCardVideoError);
    }
  }

  Future<void> _shareImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await capturePngBytes(_cardKey, pixelRatio: 1);
      final tmp = await getTemporaryDirectory();
      final suffix = _aspect == RecapCardAspect.story ? '-story' : '';
      final file = File('${tmp.path}/${widget.fileStem}$suffix.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await shareFilesFrom(
        context,
        files: [XFile(file.path, mimeType: 'image/png')],
        subject: widget.subject,
      );
    } catch (e) {
      debugPrint('Failed to share recap image: $e');
      if (mounted) {
        showTopBanner(
          context,
          AppLocalizations.of(context).recapShareImageError,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final previewHeight = (mq.size.height * 0.45).clamp(220.0, 460.0);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.recapShareSheetTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ChoiceChipRow<_RecapShareStyle>(
              alignment: WrapAlignment.center,
              options: [
                ChoiceChipOption(
                  value: _RecapShareStyle.square,
                  label: l10n.recapShareAspectSquare,
                  icon: Icons.crop_square,
                ),
                ChoiceChipOption(
                  value: _RecapShareStyle.story,
                  label: l10n.recapShareAspectStory,
                  icon: Icons.crop_portrait,
                ),
                ChoiceChipOption(
                  value: _RecapShareStyle.video,
                  label: l10n.recapShareStyleVideo,
                  icon: Icons.movie_outlined,
                ),
              ],
              selected: _style,
              onChanged: _busy ? null : (v) => setState(() => _style = v),
            ),
            const SizedBox(height: 12),
            if (_style == _RecapShareStyle.video) ...[
              Container(
                constraints: BoxConstraints(minHeight: previewHeight * 0.6),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.movie_outlined,
                        size: 40, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      l10n.recapShareVideoBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openVideoExport,
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.shareCardVideoOpen),
              ),
            ] else ...[
              // Fixed canvas scaled into the preview, text scaling pinned off:
              // the OS text size is the viewer's setting, not part of the image.
              Semantics(
                label: l10n.recapSharePreviewLabel,
                child: SizedBox(
                  height: previewHeight,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: MediaQuery.withNoTextScaling(
                      child: RepaintBoundary(
                        key: _cardKey,
                        child: RecapShareCard(text: widget.text, aspect: _aspect),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _shareImage,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(l10n.recapShareImage),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      unawaited(widget.shareText());
                    },
              icon: const Icon(Icons.notes),
              label: Text(l10n.recapShareAsText),
            ),
          ],
        ),
      ),
    );
  }
}
