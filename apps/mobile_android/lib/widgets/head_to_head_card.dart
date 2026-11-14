import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart'
    show ChoiceChipOption, ChoiceChipRow, SheetScaffold;

import '../head_to_head.dart';
import '../l10n/gen/app_localizations.dart';
import '../share_sheet.dart';
import 'capture_png.dart';
import 'error_state.dart';
import 'run_share_card.dart' show RunShareImageSaver, ShareSaveDenied, saveShareImageToGallery;
import 'run_share_overlays.dart' show ThrekirShareBrand, shareImageExportWidthPx;
import 'top_banner.dart';

// The web card's dark palette (`og_card_palette.ts` OG_CARD_DARK), so both
// platforms post the same picture.
const _bg = Color(0xFF121117);
const _brand = Color(0xFFF08A5D);
const _hero = Color(0xFFFFFFFF);
const _label = Color(0xFFA9A4B6);
const _stat = Color(0xFFE4E1EA);

/// Loads the `head_to_head` rows for one target.
typedef HeadToHeadLoader = Future<List<Map<String, dynamic>>> Function();

/// The head-to-head share card: "Me vs @friend" on one route or segment, both
/// times, who won and by how much, and the Threkir mark. Twin of web's
/// `head_to_head_canvas.ts`, on the same 360 x 450 logical canvas. It draws no
/// line and no map, so it reads no track and owes no tile credit (decisions
/// § 2267).
class HeadToHeadCard extends StatelessWidget {
  static const Size canvas = Size(360, 450);

  final HeadToHeadRow row;

  const HeadToHeadCard({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final friend =
        headToHeadName(row.friendHandle, row.friendDisplayName) ??
            l10n.headToHeadFriendFallback;
    final outcome = headToHeadOutcome(row.mySeconds, row.friendSeconds);
    final margin = formatHeadToHeadTime(outcome.marginSeconds);
    final line = switch (outcome.winner) {
      HeadToHeadWinner.me => l10n.headToHeadIWon(margin),
      HeadToHeadWinner.friend => l10n.headToHeadFriendWon(friend, margin),
      HeadToHeadWinner.tie => l10n.headToHeadTie,
    };
    const base = TextStyle(height: 1.1);
    Widget side(String name, num seconds, bool won) => Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(name,
                    maxLines: 1,
                    style: base.copyWith(
                        color: _label,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(formatHeadToHeadTime(seconds),
                    maxLines: 1,
                    style: base.copyWith(
                        color: won ? _brand : _stat,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
              ),
            ],
          ),
        );
    return SizedBox.fromSize(
      size: canvas,
      child: ColoredBox(
        color: _bg,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.headToHeadTitle.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: base.copyWith(
                      color: _label,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6)),
              const SizedBox(height: 10),
              Text(row.targetName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: base.copyWith(
                      color: _hero,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 28 / 22)),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  side(l10n.headToHeadMe, row.mySeconds,
                      outcome.winner == HeadToHeadWinner.me),
                  SizedBox(
                    width: 44,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l10n.headToHeadVs.toUpperCase(),
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: base.copyWith(
                              color: _label,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.6)),
                    ),
                  ),
                  side(friend, row.friendSeconds,
                      outcome.winner == HeadToHeadWinner.friend),
                ],
              ),
              const SizedBox(height: 40),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(line,
                      maxLines: 1,
                      style: base.copyWith(
                          color: _hero,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const Spacer(),
              const Center(child: ThrekirShareBrand(color: _hero)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the head-to-head card for one target in a bottom sheet: pick a
/// mutual-follow friend, see the card, share it or save it to Photos.
Future<void> showHeadToHeadSheet(
  BuildContext context, {
  required ApiClient api,
  required String kind,
  required String targetId,
  String activityType = 'run',
  @visibleForTesting HeadToHeadLoader? loadOverride,
  @visibleForTesting RunShareImageSaver? saveImageOverride,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SheetScaffold.floating(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppLocalizations.of(ctx).headToHeadTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            HeadToHeadPanel(
              load: loadOverride ??
                  () => api.fetchHeadToHead(kind, targetId,
                      activityType: activityType),
              fileName: 'threkir-head-to-head-$kind-$targetId',
              saveImage: saveImageOverride ?? saveShareImageToGallery,
            ),
          ],
        ),
      );
    },
  );
}

/// The picker, preview and export, shared by [showHeadToHeadSheet] and the
/// Versus style of the run share sheet. Only friends the `head_to_head` read
/// admits come back, so the picker never offers one it would then refuse.
class HeadToHeadPanel extends StatefulWidget {
  final HeadToHeadLoader load;
  final String fileName;
  final RunShareImageSaver saveImage;

  const HeadToHeadPanel({
    super.key,
    required this.load,
    required this.fileName,
    required this.saveImage,
  });

  @override
  State<HeadToHeadPanel> createState() => _HeadToHeadPanelState();
}

class _HeadToHeadPanelState extends State<HeadToHeadPanel> {
  final GlobalKey _cardKey = GlobalKey();
  List<HeadToHeadRow>? _rows;
  bool _failed = false;
  String? _friendId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _failed = false;
    });
    try {
      final rows = parseHeadToHeadRows(await widget.load());
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _friendId = rows.isEmpty ? null : rows.first.friendId;
      });
    } catch (e) {
      debugPrint('head_to_head failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  HeadToHeadRow? get _selected {
    for (final r in _rows ?? const <HeadToHeadRow>[]) {
      if (r.friendId == _friendId) return r;
    }
    return null;
  }

  Future<Uint8List> _render() async {
    await WidgetsBinding.instance.endOfFrame;
    return capturePngBytes(
      _cardKey,
      pixelRatio: shareImageExportWidthPx / HeadToHeadCard.canvas.width,
    );
  }

  Future<void> _share() async {
    final row = _selected;
    if (_busy || row == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/${widget.fileName}.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await shareFilesFrom(
        context,
        files: [XFile(file.path, mimeType: 'image/png')],
        text: row.targetName,
      );
    } catch (e) {
      debugPrint('Failed to share head-to-head image: $e');
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).shareCardImageError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _selected == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      await widget.saveImage(bytes, widget.fileName);
      if (!mounted) return;
      showTopBanner(context, AppLocalizations.of(context).shareCardSaved);
    } on ShareSaveDenied {
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).shareCardSaveDenied);
      }
    } catch (e) {
      debugPrint('Failed to save head-to-head image: $e');
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).shareCardSaveError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (_failed) {
      return AppErrorState(message: l10n.headToHeadLoadFailed, onRetry: _load);
    }
    final rows = _rows;
    if (rows == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(l10n.headToHeadLoading,
                textAlign: TextAlign.center, style: muted),
          ],
        ),
      );
    }
    final row = _selected;
    if (rows.isEmpty || row == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(l10n.headToHeadEmpty,
            key: const Key('head-to-head-empty'),
            textAlign: TextAlign.center,
            style: muted),
      );
    }
    final previewHeight =
        (MediaQuery.of(context).size.height * 0.42).clamp(220.0, 440.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.headToHeadFriend,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        ChoiceChipRow<String>(
          options: [
            for (final r in rows)
              ChoiceChipOption(
                value: r.friendId,
                label: headToHeadName(r.friendHandle, r.friendDisplayName) ??
                    l10n.headToHeadFriendFallback,
              ),
          ],
          selected: row.friendId,
          onChanged: _busy ? null : (v) => setState(() => _friendId = v),
        ),
        const SizedBox(height: 12),
        Semantics(
          excludeSemantics: true,
          label: l10n.headToHeadPreview,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: previewHeight,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                fit: BoxFit.contain,
                // The OS text size is the viewer's setting, not part of the
                // picture, so it is pinned off inside the canvas.
                child: MediaQuery.withNoTextScaling(
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: HeadToHeadCard(row: row),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.headToHeadPrivacy,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _share,
          icon: const Icon(Icons.ios_share),
          label: Text(l10n.shareCardImage),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.shareCardSave),
        ),
      ],
    );
  }
}
