import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../motion.dart';
import '../theme/spacing.dart';
import 'section_header.dart';

enum _ListRowKind { nav, value, toggle }

/// One row of a settings list: a navigation row, a value row or a switch.
///
/// The three shapes every settings page is made of, so a page is declared as
/// rows rather than assembled from `ListTile`s, each with its own trailing
/// chevron, its own disabled rule and its own place for the "(i)" button.
///
/// - [ListRow.nav] opens another page: an optional leading [icon], a one-line
///   description, a chevron (or an open-in-new glyph when [external]).
/// - [ListRow.value] opens a picker: the current [value] is the subtitle, with
///   an optional second line of [hint].
/// - [ListRow.toggle] is a switch that applies at once.
///
/// A nav or value row with a null `onTap`, or `enabled: false`, renders
/// disabled; a disabled nav row says why in its subtitle rather than being a
/// tappable row that silently does nothing (#666 I16). A toggle with a null
/// `onChanged` is disabled the same way.
///
/// [info] is the trailing "(i)" slot: the caller builds it (its tooltip is a
/// localised string, and ui_kit has no catalogue) and the row places it
/// before the chevron, or as the switch row's leading widget.
class ListRow extends StatelessWidget {
  const ListRow.nav({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.onTap,
    this.enabled = true,
    this.external = false,
    this.info,
    this.anchor,
  })  : _kind = _ListRowKind.nav,
        value = null,
        hint = null,
        checked = false,
        onChanged = null;

  const ListRow.value({
    super.key,
    required this.title,
    required String this.value,
    this.hint,
    this.icon,
    this.onTap,
    this.enabled = true,
    this.info,
    this.anchor,
  })  : _kind = _ListRowKind.value,
        subtitle = null,
        external = false,
        checked = false,
        onChanged = null;

  const ListRow.toggle({
    super.key,
    required this.title,
    this.subtitle,
    required bool value,
    required this.onChanged,
    this.info,
    this.anchor,
  })  : _kind = _ListRowKind.toggle,
        checked = value,
        value = null,
        hint = null,
        icon = null,
        onTap = null,
        enabled = true,
        external = false;

  final _ListRowKind _kind;

  /// What the row is called. Settings search matches on it.
  final String title;

  /// A nav or toggle row's one-line description.
  final String? subtitle;

  /// A value row's current value, shown as its subtitle.
  final String? value;

  /// A value row's second line, under the value.
  final String? hint;

  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;

  /// A nav row that leaves the app (a browser tab, the store).
  final bool external;

  final Widget? info;

  /// The row's [SettingsAnchor] id. Set, a search result or a link can land
  /// on this row ([SettingsList.focus]), and the landing announces [title].
  final String? anchor;

  /// A toggle row's state.
  final bool checked;
  final ValueChanged<bool>? onChanged;

  bool get isToggle => _kind == _ListRowKind.toggle;

  @override
  Widget build(BuildContext context) {
    final id = anchor;
    final row = _row(context);
    return id == null ? row : SettingsAnchor(id: id, label: title, child: row);
  }

  Widget _row(BuildContext context) {
    if (_kind == _ListRowKind.toggle) {
      return SwitchListTile(
        secondary: info,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: checked,
        onChanged: onChanged,
      );
    }
    final chevron = Icon(external ? Icons.open_in_new : Icons.chevron_right);
    final hintText = hint;
    final Widget? sub = switch (_kind) {
      _ListRowKind.value when hintText != null => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value!),
            Text(hintText, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      _ListRowKind.value => Text(value!),
      _ => subtitle == null ? null : Text(subtitle!),
    };
    return ListTile(
      enabled: enabled && onTap != null,
      leading: icon == null ? null : Icon(icon),
      title: Text(title),
      subtitle: sub,
      isThreeLine: hintText != null,
      trailing: info == null
          ? chevron
          : Row(mainAxisSize: MainAxisSize.min, children: [info!, chevron]),
      onTap: onTap,
    );
  }
}

/// A labelled group of rows in a [SettingsList].
///
/// [rows] are usually [ListRow]s; a row whose state is read from the server
/// (a switch that must not claim a value it has not seen) or an inline note
/// may be any widget. A section whose rows are all conditional and absent is
/// left out, eyebrow and all.
class SettingsSection {
  const SettingsSection({this.label, required this.rows, this.footer});

  final String? label;
  final List<Widget> rows;

  /// Muted help text under the group's last row.
  final String? footer;
}

/// The settings-list page body: [header] widgets, then grouped rows, each
/// group under a [SectionHeader] eyebrow.
///
/// With [pinnedLabels] each eyebrow stays at the top of its own group's rows
/// while they scroll past (issue #666 C13): nothing on screen otherwise says
/// which group a switch belongs to once the label has gone. The eyebrows pin
/// per group, never stacked on one another.
///
/// The page owns the group inset (gutter beside, the section gap above, a
/// hairline below), so no settings page writes one by hand. It has no app bar
/// and no scaffold: a pushed page puts it under a small app bar, a root page
/// (You) under its own title.
///
/// [focus] names a [SettingsAnchor] to land on: a search result or a link
/// about one setting opens its page with that row scrolled into view and
/// briefly highlighted, not at the top of a page the setting may be several
/// screens down (decisions § 2494, amended). Every row is built up front,
/// never lazily, so a row below the fold exists to be scrolled to; a settings
/// page is a few dozen rows at most.
class SettingsList extends StatelessWidget {
  const SettingsList({
    super.key,
    this.header = const [],
    required this.sections,
    this.pinnedLabels = true,
    this.controller,
    this.padding = const EdgeInsets.only(bottom: AppSpace.md),
    this.focus,
  });

  final List<Widget> header;
  final List<SettingsSection> sections;
  final bool pinnedLabels;
  final ScrollController? controller;
  final EdgeInsets padding;

  /// The [SettingsAnchor.id] of the row to reveal and highlight once, or null.
  final String? focus;

  /// The inset around a group's eyebrow.
  static const EdgeInsets labelPadding = EdgeInsets.fromLTRB(
    AppInsets.gutter,
    AppSpace.lg,
    AppInsets.gutter,
    AppSpace.xs,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Derived, not a constant: the eyebrow is one line of `labelSmall` at
    // whatever the OS text scale is, plus its own inset. A literal extent
    // would clip the label the moment someone raises the scale.
    final probe = TextPainter(
      text: TextSpan(text: 'Hg', style: theme.textTheme.labelSmall),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final extent = probe.height + labelPadding.vertical;
    probe.dispose();
    return _SettingsFocusScope(
      focus: focus,
      child: CustomScrollView(
        controller: controller,
        slivers: [
          if (header.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: header,
              ),
            ),
          // SliverMainAxisGroup, not loose slivers: a bare pinned header pins
          // against the viewport and every group's eyebrow would stack on the
          // one before it. Grouped, a header pins only over its own rows and
          // the next group pushes it out.
          for (final section in sections)
            if (section.rows.isNotEmpty)
              SliverMainAxisGroup(
                slivers: [
                  if (section.label case final label?)
                    SliverPersistentHeader(
                      pinned: pinnedLabels,
                      delegate: _SectionLabelDelegate(
                        label: label,
                        extent: extent,
                        background: theme.scaffoldBackgroundColor,
                      ),
                    ),
                  // A Column, not a lazy SliverList: a row the viewport has
                  // not reached must still be built, or [focus] has nothing
                  // to scroll to.
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: section.rows,
                    ),
                  ),
                  if (section.footer case final footer?)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppInsets.gutter,
                          AppSpace.xs,
                          AppInsets.gutter,
                          0,
                        ),
                        child: Text(
                          footer,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          SliverPadding(padding: padding),
        ],
      ),
    );
  }
}

class _SettingsFocusScope extends InheritedWidget {
  const _SettingsFocusScope({required this.focus, required super.child});

  final String? focus;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsFocusScope>()?.focus;

  @override
  bool updateShouldNotify(_SettingsFocusScope old) => old.focus != focus;
}

/// A settings row that [SettingsList.focus] can land on, by a stable [id].
///
/// The id outlives the row's title, which is translated and reworded, so a
/// search index, a link elsewhere in the app and the row agree on a name that
/// never changes. A [ListRow] with an `anchor` wraps itself in one; any other
/// row widget is wrapped by its page.
///
/// When its id is the list's focus, the anchor scrolls itself into view once,
/// tints its background for [highlight] and fades it out, and tells a screen
/// reader the row's [label], so the landing is not a visual cue alone. Under
/// reduce motion the scroll is a jump and the tint holds still, then clears.
class SettingsAnchor extends StatefulWidget {
  const SettingsAnchor({
    super.key,
    required this.id,
    required this.label,
    required this.child,
  });

  final String id;

  /// What the row is called, as announced on landing.
  final String label;

  final Widget child;

  /// How long a landed-on row stays tinted.
  static const Duration highlight = Duration(milliseconds: 2000);

  /// Where in the viewport a landed-on row is placed: a little below the
  /// top, clear of its group's pinned eyebrow.
  static const double alignment = 0.25;

  @override
  State<SettingsAnchor> createState() => _SettingsAnchorState();
}

class _SettingsAnchorState extends State<SettingsAnchor>
    with SingleTickerProviderStateMixin {
  // Decided once, on the first build: a focus is an arrival, not a state the
  // row keeps re-entering as the page rebuilds.
  bool? _target;
  AnimationController? _fade;
  Timer? _hold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_target != null) return;
    _target = _SettingsFocusScope.of(context) == widget.id;
    if (_target!) {
      _fade = AnimationController(
        vsync: this,
        duration: SettingsAnchor.highlight,
        value: 1,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _land());
    }
  }

  Future<void> _land() async {
    if (!mounted) return;
    final still = reduceMotion(context);
    final view = View.of(context);
    final direction = Directionality.of(context);
    await Scrollable.ensureVisible(
      context,
      alignment: SettingsAnchor.alignment,
      duration: still ? Duration.zero : AppMotion.standard,
      curve: AppMotion.curveStandard,
    );
    if (!mounted) return;
    // Best-effort: an announcer failure must not stop the highlight.
    try {
      SemanticsService.sendAnnouncement(view, widget.label, direction);
    } catch (e) {
      debugPrint('SettingsAnchor announce failed: $e');
    }
    final fade = _fade!;
    if (still) {
      _hold = Timer(SettingsAnchor.highlight, () {
        if (mounted) fade.value = 0;
      });
    } else {
      fade.animateBack(0, curve: AppMotion.curveStandard);
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _fade?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = _fade;
    if (fade == null) return widget.child;
    final tint = Theme.of(context).colorScheme.primaryContainer;
    return AnimatedBuilder(
      animation: fade,
      // A Material, not a ColoredBox: the row's ink splash paints on the
      // nearest Material, under anything drawn between it and the row.
      builder: (context, child) => Material(
        key: const ValueKey('settings-anchor-highlight'),
        color: tint.withValues(alpha: tint.a * fade.value),
        animationDuration: Duration.zero,
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _SectionLabelDelegate extends SliverPersistentHeaderDelegate {
  const _SectionLabelDelegate({
    required this.label,
    required this.extent,
    required this.background,
  });

  final String label;
  final double extent;
  final Color background;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        color: background,
        padding: SettingsList.labelPadding,
        alignment: AlignmentDirectional.centerStart,
        child: SectionHeader(label: label),
      );

  @override
  bool shouldRebuild(_SectionLabelDelegate old) =>
      old.label != label ||
      old.extent != extent ||
      old.background != background;
}
