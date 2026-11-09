import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/provenance.dart';

/// The Dart reader of `fixtures/provenance_cases.json`, the case table the
/// `provenance` pair shares with web's `provenance.test.ts`.
final Map<String, dynamic> _fixture = jsonDecode(
        File('../../fixtures/provenance_cases.json').readAsStringSync())
    as Map<String, dynamic>;

const _sections = ['content', 'listing', 'course', 'badge'];
const _metaKeys = {'spec', 'reference', 'readers', 'schema', 'kinds'};

List<Map<String, dynamic>> _section(String name) =>
    (_fixture[name] as List).cast<Map<String, dynamic>>();

String? _token(Provenance? p) => p == null ? null : provenanceTokens[p];

Provenance _kind(String token) =>
    provenanceTokens.entries.firstWhere((e) => e.value == token).key;

void main() {
  test('the fixture has no section this reader does not run', () {
    final unknown = _fixture.keys
        .where((k) => !_metaKeys.contains(k) && !_sections.contains(k))
        .toList();
    expect(unknown, isEmpty);
    for (final s in _sections) {
      expect(_section(s), isNotEmpty, reason: '$s has cases');
    }
  });

  test('the kinds list matches the fixture', () {
    expect(provenanceKinds.map(_token).toList(), _fixture['kinds']);
  });

  test('content provenance', () {
    for (final c in _section('content')) {
      expect(_token(contentProvenance(c['isOfficial'] as bool?)), c['out'],
          reason: jsonEncode(c));
    }
  });

  test('race listing provenance', () {
    for (final c in _section('listing')) {
      final got = raceListingProvenance(
        organiserIsOfficial: c['organiserIsOfficial'] as bool?,
        provider: c['provider'] as String?,
        isVerified: c['isVerified'] as bool?,
      );
      expect(_token(got), c['out'], reason: jsonEncode(c));
    }
  });

  test('race course provenance', () {
    for (final c in _section('course')) {
      final got = raceCourseProvenance(
        hasCourse: c['hasCourse'] as bool,
        organiserIsOfficial: c['organiserIsOfficial'] as bool?,
        courseSource: c['courseSource'] as String?,
      );
      expect(_token(got), c['out'], reason: jsonEncode(c));
    }
  });

  test('which provenance shows a badge', () {
    for (final c in _section('badge')) {
      expect(provenanceShowsBadge(_kind(c['kind'] as String)), c['out'],
          reason: jsonEncode(c));
    }
  });
}
