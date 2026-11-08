import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/club_verification_status_card.dart';

ClubVerificationRequestRow _row({
  String id = 'r1',
  required String status,
  String created = '2026-11-01T00:00:00Z',
  String? proofVerifiedAt,
  String? decisionReason,
  String? closeReason,
}) =>
    ClubVerificationRequestRow.fromJson({
      'id': id,
      'club_id': 'c1',
      'submitted_by': 'u1',
      'organisation': 'Race Org',
      'domain': 'race.example.org',
      'note': null,
      'token': '0123456789abcdef0123456789abcdef',
      'status': status,
      'proof_method': proofVerifiedAt == null ? null : 'dns_txt',
      'proof_verified_at': proofVerifiedAt,
      'proof_detail': null,
      'last_checked_at': null,
      'check_failures': 0,
      'decided_by': null,
      'decided_at': null,
      'decision_reason': decisionReason,
      'closed_by': null,
      'closed_at': null,
      'close_reason': closeReason,
      'created_at': created,
    });

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('a club that never asked says so', () {
    expect(clubVerificationStatusLine(l10n, const [], isVerified: false), 'Not verified.');
  });

  test('a club verified before requests existed reads as verified', () {
    expect(
      clubVerificationStatusLine(l10n, const [], isVerified: true),
      'Verified as an official organisation.',
    );
  });

  test('the approval in force names the organisation and the domain', () {
    expect(
      clubVerificationStatusLine(l10n, [_row(status: 'approved')], isVerified: true),
      'Verified as the official presence of Race Org (race.example.org).',
    );
  });

  test('a pending request says whether the proof was found', () {
    expect(
      clubVerificationStatusLine(l10n, [_row(status: 'pending')], isVerified: false),
      contains('No domain proof found yet'),
    );
    expect(
      clubVerificationStatusLine(
        l10n,
        [_row(status: 'pending', proofVerifiedAt: '2026-11-02T00:00:00Z')],
        isVerified: false,
      ),
      contains('Domain proof found'),
    );
  });

  test('the live request wins over an older closed one', () {
    final rows = [
      _row(id: 'old', status: 'rejected', created: '2026-10-01T00:00:00Z', decisionReason: 'No'),
      _row(id: 'new', status: 'pending', created: '2026-11-01T00:00:00Z'),
    ];
    expect(clubVerificationStatusLine(l10n, rows, isVerified: false), contains('waiting for review'));
  });

  test('the most recent closed request is reported with its reason', () {
    expect(
      clubVerificationStatusLine(
        l10n,
        [_row(status: 'revoked', closeReason: 'Impersonation report upheld')],
        isVerified: false,
      ),
      'The badge was removed: Impersonation report upheld',
    );
    expect(
      clubVerificationStatusLine(l10n, [_row(status: 'rejected', decisionReason: 'Lookalike domain')],
          isVerified: false),
      'The last request was not approved: Lookalike domain',
    );
    expect(
      clubVerificationStatusLine(l10n, [_row(status: 'lapsed', closeReason: 'name_changed')],
          isVerified: false),
      contains('needs a new review'),
    );
    expect(
      clubVerificationStatusLine(l10n, [_row(status: 'withdrawn')], isVerified: false),
      'The last request was withdrawn.',
    );
  });
}
