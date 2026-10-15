import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/ai_disclosure.dart';

/// Dart twin of web's `core/ai_disclosure.test.ts` (the client half — web's
/// `gateAiDisclosure` / `aiDisclosureDenialBody` are server-side and have no
/// mobile counterpart).

const _accepted = '2026-01-01T00:00:00Z';

void main() {
  group('checkAiDisclosure', () {
    test('a v1 Coach acceptance does NOT satisfy the widened route-AI scope',
        () {
      // Issue #734. This is the whole point of versioning the record:
      // treating the Coach stamp as covering the route endpoints
      // retroactively broadens what an existing user agreed to.
      const record = AiDisclosureRecord(
        version: kAiDisclosureVersionCoach,
        acceptedAt: _accepted,
      );
      final coach = checkAiDisclosure(record, kAiDisclosureVersionCoach);
      expect(coach.ok, isTrue);
      expect(coach.version, 1);
      final routeAi = checkAiDisclosure(record, kAiDisclosureVersionRouteAi);
      expect(routeAi.ok, isFalse);
      expect(routeAi.reason, AiDisclosureDenial.stale);
    });

    test('the route-AI acceptance satisfies the Coach and route scopes', () {
      const record = AiDisclosureRecord(
        version: kAiDisclosureVersionRouteAi,
        acceptedAt: _accepted,
      );
      expect(checkAiDisclosure(record, kAiDisclosureVersionCoach).ok, isTrue);
      expect(checkAiDisclosure(record, kAiDisclosureVersionRouteAi).ok, isTrue);
    });

    test('a v2 route-AI acceptance does NOT satisfy the plan-assistant scope',
        () {
      // The plan assistant sends the typed plan description for a purpose
      // the v2 copy never described (decisions § 571). A v2 holder must
      // re-accept, not be quietly widened.
      for (final version in [
        kAiDisclosureVersionCoach,
        kAiDisclosureVersionRouteAi,
      ]) {
        final check = checkAiDisclosure(
          AiDisclosureRecord(version: version, acceptedAt: _accepted),
          kAiDisclosureVersionPlanAi,
        );
        expect(check.ok, isFalse);
        expect(check.reason, AiDisclosureDenial.stale);
      }
    });

    test('the v3 acceptance satisfies the Coach, route and plan scopes', () {
      const record = AiDisclosureRecord(
        version: kAiDisclosureVersionPlanAi,
        acceptedAt: _accepted,
      );
      for (final minimum in [
        kAiDisclosureVersionCoach,
        kAiDisclosureVersionRouteAi,
        kAiDisclosureVersionPlanAi,
      ]) {
        final check = checkAiDisclosure(record, minimum);
        expect(check.ok, isTrue);
        expect(check.version, 3);
      }
    });

    test('a v3 plan-assistant acceptance does NOT satisfy the plate-photo scope',
        () {
      const record = AiDisclosureRecord(
        version: kAiDisclosureVersionPlanAi,
        acceptedAt: _accepted,
      );
      final check = checkAiDisclosure(record, kAiDisclosureVersionFoodPhotoAi);
      expect(check.ok, isFalse);
      expect(check.reason, AiDisclosureDenial.stale);
    });

    test('the v5 acceptance satisfies the plate-photo scope', () {
      const record = AiDisclosureRecord(
        version: kAiDisclosureVersionFoodPhotoAi,
        acceptedAt: _accepted,
      );
      final check = checkAiDisclosure(record, kAiDisclosureVersionFoodPhotoAi);
      expect(check.ok, isTrue);
      expect(check.version, 5);
    });

    test('no record at all denies as missing', () {
      final check = checkAiDisclosure(const AiDisclosureRecord(), 1);
      expect(check.ok, isFalse);
      expect(check.reason, AiDisclosureDenial.missing);
    });

    test('half a record is not a record — either half missing denies', () {
      // The DB CHECK forbids this pairing, so reaching it means a corrupt
      // row or a caller reading a partial projection. Deny either way.
      for (final record in const [
        AiDisclosureRecord(version: 2),
        AiDisclosureRecord(acceptedAt: _accepted),
        AiDisclosureRecord(version: 2, acceptedAt: ''),
      ]) {
        final check = checkAiDisclosure(record, 1);
        expect(check.ok, isFalse);
        expect(check.reason, AiDisclosureDenial.missing);
      }
    });

    test("a version outside this build's ladder denies as unknown", () {
      // A disclosure this build cannot render is one it cannot prove was
      // made.
      for (final version in [kAiDisclosureCurrentVersion + 1, 0, -3]) {
        final check = checkAiDisclosure(
          AiDisclosureRecord(version: version, acceptedAt: _accepted),
          1,
        );
        expect(check.ok, isFalse, reason: 'version $version must not grant');
        expect(check.reason, AiDisclosureDenial.unknown);
      }
    });

    test('a non-integer / non-numeric version denies as unknown', () {
      for (final version in <Object>['2', 2.5, true, <String, Object>{}, []]) {
        final check = checkAiDisclosure(
          AiDisclosureRecord(version: version, acceptedAt: _accepted),
          1,
        );
        expect(check.ok, isFalse, reason: 'version $version must not grant');
        expect(check.reason, AiDisclosureDenial.unknown);
      }
    });

    test('a non-string acceptance timestamp denies as missing', () {
      for (final acceptedAt in <Object>[0, 1735689600000, true, {}]) {
        final check = checkAiDisclosure(
          AiDisclosureRecord(version: 2, acceptedAt: acceptedAt),
          1,
        );
        expect(check.ok, isFalse);
        expect(check.reason, AiDisclosureDenial.missing);
      }
    });
  });

  group('aiDisclosureFromProfileRow', () {
    test('reads both halves off a profile row', () {
      final record = aiDisclosureFromProfileRow(<String, Object?>{
        'ai_disclosure_version': 2,
        'coach_consent_at': _accepted,
        'display_name': 'Test Runner',
      });
      expect(record.version, 2);
      expect(record.acceptedAt, _accepted);
    });

    test('a null / non-map row yields an empty record that denies', () {
      for (final row in <Object?>[null, 'nope', 7]) {
        final record = aiDisclosureFromProfileRow(row);
        expect(record.version, isNull);
        expect(record.acceptedAt, isNull);
        expect(checkAiDisclosure(record, 1).ok, isFalse);
      }
    });
  });

  group('the ladder', () {
    test('is ordered and the current version is its top rung', () {
      expect(kAiDisclosureVersionCoach, lessThan(kAiDisclosureVersionRouteAi));
      expect(
          kAiDisclosureVersionRouteAi, lessThan(kAiDisclosureVersionPlanAi));
      expect(kAiDisclosureVersionPlanAi,
          lessThan(kAiDisclosureVersionFoodPhotoAi));
      expect(kAiDisclosureCurrentVersion, kAiDisclosureVersionFoodPhotoAi);
    });

    test('matches ai_disclosure_current_version() in SQL', () {
      // The DB refuses to record a version above its own maximum and the
      // gate refuses to trust one above the build's. If the two drift, a
      // runner can be asked to accept a version that cannot be stored, or a
      // stored version stops being honoured.
      // The NEWEST definition is the live one: each rung is a fresh
      // `create or replace` in its own migration, and migrations apply in
      // filename order.
      final re = RegExp(
        r'create or replace function ai_disclosure_current_version\(\)'
        r'[\s\S]*?select\s+(\d+)::smallint',
      );
      final files = Directory('../backend/supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      RegExpMatch? match;
      for (final f in files) {
        for (final m in re.allMatches(f.readAsStringSync())) {
          match = m;
        }
      }
      expect(match, isNotNull,
          reason: 'ai_disclosure_current_version() must be in a migration');
      expect(int.parse(match!.group(1)!), kAiDisclosureCurrentVersion);
    });
  });
}
