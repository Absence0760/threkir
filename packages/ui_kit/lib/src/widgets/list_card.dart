import 'package:flutter/material.dart';

import '../theme/corner_radii.dart';
import '../theme/spacing.dart';

enum _ListCardKind { content, row, flush }

/// A card in a list, and the only place the app builds a `Card`.
///
/// Issue #1374 counted about 120 hand-built `Card > Padding` blocks with 29
/// different inner paddings, 20 `Card > ListTile`s and 21 `Card > InkWell >
/// Padding` taps, each with its own idea of a selected state and of what a
/// screen reader hears. The card's shape (theme), inner padding
/// ([AppInsets.card], or [AppInsets.cardDense] when [dense]), tap target,
/// selected tint and semantics are this widget's, so a list states what is in
/// a card rather than how to draw one. `card_padding_guard_test` fails a
/// `Card(` built anywhere else.
///
/// Three forms:
///
/// - [ListCard] holds any [child] inside the standard padding: a summary
///   panel, a run row with its own anatomy (the app's `RunListTile`).
/// - [ListCard.row] is the list item: optional [leading], a [title] with an
///   optional [badge] beside it, a [subtitle], a [meta] block under them, and
///   a [trailing] widget or a [chevron]. It owns the typography, so every
///   list's title is the same size and weight.
/// - [ListCard.flush] has no padding, for a card whose content runs to its
///   edges (a full-width map or photo above the text).
///
/// Every form takes [actions]: buttons laid out in a row under the content,
/// each its own tap target and outside the card's own tap.
///
/// **Selection.** [selected] tints the card and marks its node selected; on
/// [ListCard.row], [selecting] swaps the leading slot for the selection
/// glyph, so a list in a selection mode (the hub's `HubSelection` bar) shows
/// which rows are in it without each list drawing its own checkbox.
///
/// **Semantics.** The tappable part of the card is one node: a button when
/// [onTap] is set, carrying [onTap] and [onLongPress]. With [semanticLabel]
/// that node reads the label alone (for a row whose visible text is
/// abbreviated: "5.2 km" read as "5.2 km run, …"); without it, the node reads
/// the texts inside. [trailing] and [actions] stay separate nodes, so a
/// switch or a button in a card is never merged into the row's label.
class ListCard extends StatelessWidget {
  /// Any [child] inside the standard inner padding.
  const ListCard({
    super.key,
    required Widget this.child,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.semanticLabel,
    this.semanticHint,
    this.enabled = true,
    this.dense = false,
    this.actions = const [],
    this.margin,
    this.color,
    this.outline,
  }) : _kind = _ListCardKind.content,
       leading = null,
       leadingWidth = null,
       title = null,
       titleMaxLines = 2,
       badge = null,
       subtitle = null,
       subtitleMaxLines = 2,
       meta = null,
       trailing = null,
       chevron = false,
       selecting = false;

  /// A list item: leading, title and badge, subtitle, meta, trailing.
  const ListCard.row({
    super.key,
    required String this.title,
    this.titleMaxLines = 2,
    this.leading,
    this.leadingWidth,
    this.badge,
    this.subtitle,
    this.subtitleMaxLines = 2,
    this.meta,
    this.trailing,
    this.chevron = false,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selecting = false,
    this.semanticLabel,
    this.semanticHint,
    this.enabled = true,
    this.dense = false,
    this.actions = const [],
    this.margin,
    this.color,
    this.outline,
  }) : _kind = _ListCardKind.row,
       child = null;

  /// A card whose [child] runs to its edges; the child owns its own insets.
  const ListCard.flush({
    super.key,
    required Widget this.child,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.semanticLabel,
    this.semanticHint,
    this.enabled = true,
    this.actions = const [],
    this.margin,
    this.color,
    this.outline,
  }) : _kind = _ListCardKind.flush,
       dense = false,
       leading = null,
       leadingWidth = null,
       title = null,
       titleMaxLines = 2,
       badge = null,
       subtitle = null,
       subtitleMaxLines = 2,
       meta = null,
       trailing = null,
       chevron = false,
       selecting = false;

  final _ListCardKind _kind;

  final Widget? child;

  /// The row's name, in `titleMedium` weight 600.
  final String? title;
  final int titleMaxLines;

  /// The row's picture or icon. Replaced by the selection glyph while
  /// [selecting].
  final Widget? leading;

  /// A fixed width for the leading slot, so rows whose leading differs
  /// (a thumbnail, an icon, the selection glyph) keep their titles aligned.
  final double? leadingWidth;

  /// A status beside the title (a `StatusPill`). Wraps under the title when
  /// the two do not fit on one line.
  final Widget? badge;

  /// One line of facts under the title, muted.
  final String? subtitle;
  final int subtitleMaxLines;

  /// Anything under the subtitle: a row of meta items, a progress bar.
  final Widget? meta;

  /// A value or control at the row's end. Not part of the row's tap node.
  final Widget? trailing;

  /// A chevron at the row's end, for a row that opens a page.
  final bool chevron;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Tints the card and marks its node selected.
  final bool selected;

  /// The list is in a selection mode: the leading slot shows whether this row
  /// is in the selection.
  final bool selecting;

  /// What a screen reader reads for the card's tap node, in place of the
  /// texts inside it.
  final String? semanticLabel;

  /// What a screen reader reads after the label: what the tap will do, when
  /// the visible prompt would read the same on every card.
  final String? semanticHint;

  /// False draws a tappable card that cannot be tapped right now (another
  /// write is in flight): still a button, announced disabled, no ripple.
  final bool enabled;

  /// The dense inner padding, [AppInsets.cardDense].
  final bool dense;

  /// Buttons under the content, each its own target.
  final List<Widget> actions;

  /// Defaults to the theme's card margin.
  final EdgeInsetsGeometry? margin;

  /// Defaults to the theme's card colour. Ignored while [selected].
  final Color? color;

  /// The border's colour, in place of the theme's hairline: a card that
  /// must read as tappable beside read-only ones of the same shape.
  final Color? outline;

  /// The most of the row's width the leading slot may take.
  static const double maxLeadingFraction = 0.4;

  /// The most of the card's width the trailing slot may take.
  static const double maxTrailingFraction = 0.45;

  /// The margin of a card in a list that has no horizontal padding of its
  /// own: the page gutter beside, half the item gap above and below, so two
  /// cards sit [AppInsets.itemGap] apart.
  static const EdgeInsets listMargin = EdgeInsets.symmetric(
    horizontal: AppInsets.gutter,
    vertical: AppInsets.itemGap / 2,
  );

  /// The width of the selection glyph's slot when no [leadingWidth] is set.
  static const double selectionGlyphWidth = 40;

  EdgeInsets get _padding => switch (_kind) {
    _ListCardKind.flush => EdgeInsets.zero,
    _ when dense => AppInsets.cardDense,
    _ => AppInsets.card,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A disabled card is still a button, one that cannot be pressed now.
    final isButton = onTap != null || !enabled;
    final tappable = isButton || onLongPress != null;
    final padding = _padding;
    final hasActions = actions.isNotEmpty;

    final Widget body;
    Widget? end;
    if (_kind == _ListCardKind.row) {
      body = _rowBody(theme);
      end = _rowEnd(theme);
    } else {
      body = child!;
    }

    // The tap area: the content and its padding, minus [trailing], which
    // claims its own taps. One node carries the button, its state and the
    // taps; with [semanticLabel] it reads that label alone.
    Widget tapArea = Padding(
      padding: padding.copyWith(
        right: end == null ? padding.right : 0,
        bottom: hasActions && padding.bottom > 0 ? AppSpace.xs : padding.bottom,
      ),
      child: body,
    );
    if (semanticLabel != null) tapArea = ExcludeSemantics(child: tapArea);
    if (tappable) {
      tapArea = InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: tapArea,
      );
    }
    // semantics-children: with [semanticLabel] the content is already behind
    // ExcludeSemantics above; without one there is no label to read twice.
    tapArea = Semantics(
      button: isButton ? true : null,
      enabled: isButton ? enabled : null,
      selected: selected ? true : null,
      label: semanticLabel,
      hint: semanticHint,
      // A selected card with no tap of its own would otherwise lend its
      // selected flag to whatever node is above it.
      container: selected && !tappable,
      child: tapArea,
    );
    // A row's leading and texts are one reading. A content card's child may
    // hold controls of its own, which merging would swallow into the label.
    if (_kind == _ListCardKind.row) tapArea = MergeSemantics(child: tapArea);

    final Widget top = end == null
        ? tapArea
        // The trailing slot is capped, so a wide value or tag wraps or
        // ellipsizes inside it rather than pushing the row off a narrow
        // phone at large text.
        : LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(child: tapArea),
                Padding(
                  padding: EdgeInsets.only(
                    left: AppSpace.smPlus,
                    right: padding.right,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * maxTrailingFraction,
                    ),
                    child: end,
                  ),
                ),
              ],
            ),
          );

    return Card(
      margin: margin,
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : color,
      shape: outline == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: outline!),
            ),
      clipBehavior: Clip.antiAlias,
      child: hasActions
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                top,
                // Inset by the buttons' own padding, so their labels line up
                // with the content above.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding.left > AppSpace.sm
                        ? padding.left - AppSpace.sm
                        : AppSpace.sm,
                    0,
                    padding.right > AppSpace.sm
                        ? padding.right - AppSpace.sm
                        : AppSpace.sm,
                    AppSpace.xs,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpace.sm,
                    children: actions,
                  ),
                ),
              ],
            )
          : top,
    );
  }

  Widget _rowBody(ThemeData theme) {
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final titleText = Text(
      title!,
      maxLines: titleMaxLines,
      overflow: TextOverflow.ellipsis,
      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge case final badge?)
          // A Wrap rather than a Row: a long title and a pill share one line
          // when they fit and the pill drops under the title when they do
          // not, which at 320 dp and 2x text is most of the time.
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [titleText, badge],
          )
        else
          titleText,
        if (subtitle case final subtitle?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(
              subtitle,
              maxLines: subtitleMaxLines,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: muted),
            ),
          ),
        if (meta case final meta?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: meta,
          ),
      ],
    );

    final lead = selecting
        ? Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          )
        : leading;
    if (lead == null) return texts;
    final width = leadingWidth ?? (selecting ? selectionGlyphWidth : null);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (width != null)
            SizedBox(
              width: width,
              child: Center(child: lead),
            )
          else
            // Capped like the trailing slot: a date lane or a label at 2x
            // must not leave the title no room.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * maxLeadingFraction,
              ),
              child: lead,
            ),
          const SizedBox(width: AppSpace.md),
          Expanded(child: texts),
        ],
      ),
    );
  }

  Widget? _rowEnd(ThemeData theme) {
    final chevronIcon = chevron
        ? ExcludeSemantics(
            child: Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : null;
    if (trailing == null) return chevronIcon;
    if (chevronIcon == null) return trailing;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Flexible(child: trailing!), chevronIcon],
    );
  }
}
