// Organiser name disputes (issue #1363, decisions § 2441).
//
// `submit_organiser_dispute` is the gate: it refuses anyone who is not an
// active owner or admin of a verified, public, unhidden club. This file only
// decides what the report sheet offers. Mirrors web's
// `lib/social/organiser_dispute.ts`.

import 'race_service.dart';

/// The report reason an organiser dispute is filed with.
const kOrganiserDisputeReason = 'organiser_dispute';

/// The kinds the report sheet offers a dispute on. The database also takes
/// plans, routines, challenges and race listings; on mobile the report menu
/// exists only on clubs and routes, so those are reported from the web.
const kOrganiserDisputeSheetKinds = <String>{'club', 'route'};

/// Mirrors `submit_organiser_dispute`'s notes cap.
const kOrganiserDisputeNotesMax = 600;

/// The clubs the runner may file for: their verified clubs other than the one
/// the content belongs to (the RPC refuses disputing your own content).
List<OrganiserClub> organiserDisputeClubsFor(
  List<OrganiserClub> myOrganiserClubs,
  String? targetClubId,
) =>
    myOrganiserClubs.where((c) => c.id != targetClubId).toList();
