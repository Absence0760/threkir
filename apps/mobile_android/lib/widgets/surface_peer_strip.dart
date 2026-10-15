import 'package:flutter/material.dart';

/// One entry in a [SurfacePeerStrip]. A null [onTap] marks the peer the user is
/// already on — it stays focusable and announces as selected rather than being
/// disabled, so a screen-reader user can still hear where they are.
class SurfacePeer {
  const SurfacePeer({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  bool get isCurrent => onTap == null;
}

/// The labelled in-body strip of sibling surfaces a screen sits beside — the
/// mobile mirror of web's `RunSurfaceTabs.svelte` and the `/gym` header links.
///
/// Planning tools used to hang off icon-only AppBar actions whose names existed
/// only as tooltips, which is undiscoverable on a touch device (the same field
/// finding that produced `routes_screen.dart`'s labelled Discover strip — that
/// one fans out to sub-surfaces of Routes and has no current-peer concept, so
/// it stays its own thing). The strip WRAPS rather than scrolling sideways:
/// measured in Manrope, the five run-surface peers need 480 dp in English and
/// 538 dp in French against a 360-412 dp phone, so a scrolling row always hid
/// the last peer (Races) past the edge with nothing saying it was there. A
/// second line keeps every destination on screen (decisions § 1954).
class SurfacePeerStrip extends StatelessWidget {
  const SurfacePeerStrip({
    super.key,
    required this.label,
    required this.peers,
  });

  /// Accessibility label for the strip as a whole.
  final String label;

  final List<SurfacePeer> peers;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final peer in peers)
              ChoiceChip(
                label: Text(
                  peer.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: peer.isCurrent,
                onSelected: (_) => peer.onTap?.call(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ),
    );
  }
}
