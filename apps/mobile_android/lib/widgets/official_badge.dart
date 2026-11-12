import 'package:flutter/material.dart';

import '../provenance.dart';
import 'provenance_badge.dart';

/// "Official" mark on content published by a verified organiser: a route,
/// plan, gym routine, challenge or session plan whose club is verified and
/// whose author is an owner/admin of it. The flag is derived server-side
/// (`is_official`, migration 20271021000030) and never stored per row; this
/// is the official kind of [ProvenanceBadge], kept as its own name for the
/// content surfaces. Twin of the Svelte `OfficialBadge` component.
class OfficialBadge extends StatelessWidget {
  final double size;
  final bool parkCourse;

  const OfficialBadge({super.key, this.size = 14, this.parkCourse = false});

  @override
  Widget build(BuildContext context) => ProvenanceBadge(
        provenance: Provenance.official,
        size: size,
        parkCourse: parkCourse,
      );
}
