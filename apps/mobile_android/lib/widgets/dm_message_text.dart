import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../dm_link.dart';

/// A direct message's text, with each http(s) link drawn as its text plus a
/// chip naming its domain ([dmTextSegments]). Nothing is fetched for a
/// preview, and the text is never read as markup. Mirrors web's
/// `DmMessageText.svelte`.
class DmMessageText extends StatelessWidget {
  const DmMessageText({
    super.key,
    required this.body,
    this.style,
    this.onOpenLink,
  });

  final String body;
  final TextStyle? style;
  final void Function(String href)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final segments = dmTextSegments(body);
    if (segments.every((s) => s is DmTextRun)) return Text(body, style: style);
    final color = style?.color ?? DefaultTextStyle.of(context).style.color;
    var links = 0;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final seg in segments)
            switch (seg) {
              DmLink() => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _Link(
                  index: links++,
                  link: seg,
                  style: style,
                  color: color,
                  onOpen: onOpenLink,
                ),
              ),
              DmTextRun() => TextSpan(text: seg.text),
            },
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({
    required this.index,
    required this.link,
    required this.style,
    required this.color,
    required this.onOpen,
  });

  final int index;
  final DmLink link;
  final TextStyle? style;
  final Color? color;
  final void Function(String href)? onOpen;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: color);
    return Semantics(
      link: true,
      label: '${link.text}, ${link.domain}',
      excludeSemantics: true,
      onTap: onOpen == null ? null : () => onOpen!(link.href),
      child: GestureDetector(
        key: ValueKey('dm-link-$index'),
        onTap: onOpen == null ? null : () => onOpen!(link.href),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              link.text,
              style:
                  style?.copyWith(decoration: TextDecoration.underline) ??
                  const TextStyle(decoration: TextDecoration.underline),
            ),
            Container(
              key: ValueKey('dm-link-domain-$index'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: (color ?? Colors.black).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link, size: AppIconSize.dense, color: color),
                  const SizedBox(width: 2),
                  Text(link.domain, style: labelStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
