// Pins lib/organiser_dispute.dart (issue #1363, decisions § 2441) against
// web's lib/social/organiser_dispute.ts and the migration's caps.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/organiser_dispute.dart';
import '../lib/race_service.dart';

void main() {
  const v = OrganiserClub(id: 'v', name: 'Verified Org');
  const w = OrganiserClub(id: 'w', name: 'Second Org');

  test('a club is never offered a dispute against its own content', () {
    expect(organiserDisputeClubsFor([v, w], 'v').map((c) => c.id), ['w']);
    expect(organiserDisputeClubsFor([v, w], null).map((c) => c.id), ['v', 'w']);
    expect(organiserDisputeClubsFor([v], 'v'), isEmpty);
  });

  test('the reason and notes cap match the migration', () {
    final sql = File(
      '../backend/supabase/migrations/20271202000003_organiser_disputes.sql',
    ).readAsStringSync();
    expect(sql, contains("'$kOrganiserDisputeReason'"));
    expect(sql, contains('char_length(v_notes) > $kOrganiserDisputeNotesMax'));
  });

  test('the sheet offers a dispute only on kinds the database takes', () {
    final sql = File(
      '../backend/supabase/migrations/20271202000001_reports_organiser_dispute.sql',
    ).readAsStringSync();
    for (final kind in kOrganiserDisputeSheetKinds) {
      expect(sql, contains("'$kind'"));
    }
  });
}
