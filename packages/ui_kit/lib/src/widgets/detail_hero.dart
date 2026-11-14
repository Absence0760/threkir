import 'package:flutter/material.dart';

import '../theme/spacing.dart';
import 'pushed_page.dart';

/// The one primary action of a detail page: Join, RSVP, Start, Follow.
///
/// A value the [DetailHero] places, full width under the hero's meta, so a
/// detail page has exactly one primary action and it is always in the same
/// place (issue #1374 report 5 § 6.4).
class HeroCta {
  const HeroCta({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.outlined = false,
    this.secondary,
    this.key,
  });

  /// While [busy] it should name the work in progress ("Joining…"): a spinner
  /// alone says nothing to a screen reader.
  final String label;

  /// Null draws the button disabled.
  final VoidCallback? onPressed;

  final IconData? icon;

  /// Draws a spinner beside [label] and disables the button.
  final bool busy;

  /// An outlined button, for the action that undoes membership (Leave,
  /// Cancel RSVP), which should not read as the page's invitation.
  final bool outlined;

  /// A lesser action under the button (Invite, Add to calendar), as a text
  /// button.
  final Widget? secondary;

  final Key? key;
}

/// One icon-and-text pair of a [DetailHero]'s meta row: a date, a place, a
/// member count.
class DetailMeta extends StatelessWidget {
  const DetailMeta({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The link from a detail page up to what it belongs to: an event's club, a
/// course's park. A link to a screen reader, announced as [semanticsLabel]
/// when the chip's short [label] needs saying where it goes.
class DetailParentChip extends StatelessWidget {
  const DetailParentChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.semanticsLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      link: true,
      label: semanticsLabel ?? label,
      onTap: onPressed,
      excludeSemantics: true,
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onPressed,
      ),
    );
  }
}

/// The top of a detail page's body: an optional [parent] chip, the [title]
/// beside an optional [leading] avatar or date block, [badges] under the
/// title, one [meta] row, an optional [description], any [children] the page
/// needs there, and the page's one primary action as [cta] (or [status] when
/// the action is not the viewer's to take, such as "Owner").
///
/// The title is the page's [PageHeading]: it wraps rather than being cut, and
/// the [DetailPage] bar shows the name only once it has scrolled away.
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.title,
    this.titleMaxLines,
    this.leading,
    this.badges = const [],
    this.parent,
    this.meta = const [],
    this.description,
    this.children = const [],
    this.cta,
    this.status,
    this.padding = const EdgeInsets.fromLTRB(
      AppInsets.gutter,
      AppSpace.md,
      AppInsets.gutter,
      AppSpace.sm,
    ),
  });

  final String title;

  /// See [PageHeading.maxLines]: for an unbounded name a person typed.
  final int? titleMaxLines;

  final Widget? leading;

  /// Small markers about the entity (DNF, Official, Private), wrapped under
  /// the title.
  final List<Widget> badges;

  final Widget? parent;

  /// Usually [DetailMeta]s. They wrap onto as many lines as they need.
  final List<Widget> meta;

  final Widget? description;
  final List<Widget> children;
  final HeroCta? cta;
  final Widget? status;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    final parent = this.parent;
    final description = this.description;
    final cta = this.cta;
    final status = this.status;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PageHeading(title, maxLines: titleMaxLines),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: badges,
          ),
        ],
      ],
    );
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (parent != null) ...[
            Align(alignment: AlignmentDirectional.centerStart, child: parent),
            const SizedBox(height: AppSpace.sm),
          ],
          if (leading == null)
            heading
          else
            Row(
              children: [
                leading,
                const SizedBox(width: AppSpace.smPlus),
                Expanded(child: heading),
              ],
            ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.xs,
              children: meta,
            ),
          ],
          if (description != null) ...[
            const SizedBox(height: AppSpace.smPlus),
            description,
          ],
          ...children,
          if (status != null) ...[
            const SizedBox(height: AppSpace.smPlus),
            Align(alignment: AlignmentDirectional.centerStart, child: status),
          ],
          if (cta != null) ...[
            const SizedBox(height: AppSpace.md),
            _HeroCtaButton(cta: cta),
          ],
        ],
      ),
    );
  }
}

class _HeroCtaButton extends StatelessWidget {
  const _HeroCtaButton({required this.cta});

  final HeroCta cta;

  @override
  Widget build(BuildContext context) {
    final icon = cta.icon;
    final label = Text(cta.label, textAlign: TextAlign.center);
    final Widget child = cta.busy
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: label),
            ],
          )
        : icon == null
            ? label
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(child: label),
                ],
              );
    final onPressed = cta.busy ? null : cta.onPressed;
    final button = cta.outlined
        ? OutlinedButton(key: cta.key, onPressed: onPressed, child: child)
        : FilledButton(key: cta.key, onPressed: onPressed, child: child);
    final secondary = cta.secondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        if (secondary != null) ...[
          const SizedBox(height: AppSpace.xs),
          Align(alignment: AlignmentDirectional.center, child: secondary),
        ],
      ],
    );
  }
}
