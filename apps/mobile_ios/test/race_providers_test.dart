import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../lib/race_service.dart';

/// The link half of the person flow without a Supabase: what the service does
/// with the stored link and with a lookup refusal is the subject here, so the
/// ApiClient underneath answers whatever the case needs.
class _LinkApi extends ApiClient {
  Object? lookupError;
  int linkReads = 0;

  _LinkApi({this.lookupError});

  @override
  Future<UltraSignUpPersonLink?> fetchUltraSignUpLink() async {
    linkReads++;
    return null;
  }

  @override
  Future<List<UltraSignUpCandidate>> lookupUltraSignUpPeople(
      String firstName, String lastName) async {
    final error = lookupError;
    if (error != null) throw error;
    return const [];
  }
}

/// The import-provider vocabulary. `race-results-import` is the third rail
/// here — the phone can only reach a leg it names, and can only name a token
/// the function accepts, so the two lists are read against each other.
void main() {
  test('every catalogue entry resolves back by its own token', () {
    for (final spec in raceImportProviders) {
      expect(raceImportProviderFor(spec.provider), same(spec));
    }
  });

  test('a listing provider with no import leg resolves to no spec', () {
    // Not gaps: parkrun / manual / raceresult listings are real rows of the
    // `race_listings.provider` CHECK that no bib-import leg exists for, and
    // `paste` is the universal manual fallback rather than a listing provider.
    for (final token in ['parkrun', 'manual', 'raceresult', 'paste', '']) {
      expect(raceImportProviderFor(token), isNull, reason: token);
    }
  });

  test('each provider carries its own fail-closed exception', () {
    // A surface showing a peer's explainer would tell a runner the wrong
    // credential is missing.
    final types = raceImportProviders.map((p) => p.unavailable.runtimeType).toSet();
    expect(types.length, raceImportProviders.length);
  });

  test('a provider with no leg is reported unconfigured without a call', () async {
    // RaceService has no Supabase behind it here, so reaching the client would
    // throw rather than answer — the null spec has to short-circuit first.
    expect(await RaceService().isProviderConfigured('parkrun'), isFalse);
  });

  group('a probe reports configured only on a 200', () {
    // decisions § 1073. The grader this replaced reported a readable non-429
    // 4xx as CONFIGURED, on the theory that such a status proved the function
    // ran PAST its credential gate. The theory is refuted by the endpoint
    // itself, twice, so these read the function rather than restating it.
    final fn =
        File('../backend/supabase/functions/race-results-import/handler.ts')
            .readAsStringSync();

    int at(String needle) {
      final i = fn.indexOf(needle);
      expect(i, greaterThan(-1),
          reason: 'race-results-import no longer contains `$needle` — reread '
              'it and re-anchor this guard');
      return i;
    }

    test('401 is answered before any provider credential is read', () {
      // So a signed-out or expired session probes every provider and is told
      // nothing about any of them. Under the old grader a 401 was a readable
      // non-429 4xx, so it lit EVERY card as live.
      final probeBranch = at('if (isProbe) {');
      final firstUnauthorized =
          at("return Response.json({ error: 'unauthorized' }, { status: 401 })");
      expect(firstUnauthorized, lessThan(probeBranch),
          reason: 'the auth gate must precede the probe branch, or a probe '
              'could answer about a provider for an unauthenticated caller');

      // And before any PROVIDER credential — SUPABASE_URL is infrastructure the
      // client needs to check the caller at all, not an answer about a leg.
      for (final key in const [
        'RUNSIGNUP_API_KEY',
        'CHRONOTRACK_CLIENT_ID',
      ]) {
        expect(firstUnauthorized, lessThan(at(key)),
            reason: '$key is read before the caller is authenticated');
      }
    });

    test('an undispatched leg is answered 400, which the function itself '
        'introduces as "not configured"', () {
      final probeBranch = at('if (isProbe) {');
      final unknown =
          at("return Response.json({ error: 'unknown_provider' }, { status: 400 })");
      final configured = at("return Response.json({ configured: true })");
      expect(unknown, greaterThan(probeBranch));
      expect(unknown, lessThan(configured),
          reason: 'the unknown-provider refusal must be inside the probe '
              'branch, ahead of its single affirmative answer');
      // The client used to read this 400 as "configured" while the function
      // wrote it to mean the opposite — one response, two readings.
      expect(fn.contains('An unrecognised provider is not "configured"'), isTrue,
          reason: "the function's own statement of what its 400 means moved — "
              'reread it; if it now means something else, this whole grading '
              'decision needs revisiting');
    });

    test('the probe branch has exactly one affirmative answer', () {
      // Which is why "configured iff the invoke did not throw" is not a
      // simplification: `functions_client` throws for every status outside
      // 200-299, so "did not throw" IS "2xx", and the branch has one 2xx.
      final probeBranch = at('if (isProbe) {');
      final afterBranch = at("const listingId =");
      final body = fn.substring(probeBranch, afterBranch);
      expect('Response.json('.allMatches(body).length, greaterThan(1),
          reason: 're-anchor: the probe branch no longer returns responses');
      final affirmatives = RegExp(r'Response\.json\(\{ configured: true \}\)')
          .allMatches(body)
          .length;
      expect(affirmatives, 1);
      // Every other return in the branch carries an `error`.
      final errors = RegExp(r"error: '").allMatches(body).length;
      expect(errors, greaterThan(2));
    });

    test('the client grades no status at all — every throw is unavailable', () {
      // The guard that would have failed against the old code. A grader that
      // maps a status to "available" is the § 1007 defect returning; there is
      // no status this endpoint can answer that means "configured".
      final src = File('../../apps/mobile_android/lib/race_service.dart')
          .readAsStringSync();
      final sig = src.indexOf('Future<bool> isProviderConfigured(');
      expect(sig, greaterThan(-1), reason: 'isProviderConfigured moved');
      var depth = 0;
      var i = src.indexOf('{', sig);
      final open = i;
      while (i < src.length) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') {
          depth--;
          if (depth == 0) break;
        }
        i++;
      }
      final body = src.substring(open, i);
      expect(body.contains('return false;'), isTrue);
      expect(body.contains('status'), isFalse,
          reason: 'isProviderConfigured inspects a status again. Only a 200 '
              'answers a probe (§ 1073) — a status-reading grader is how the '
              'phone came to report 401 and 400 as configured.');
    });
  });

  test('web states the same probe rule, which is why there is no Dart twin',
      () {
    // The rule is stated natively on each platform rather than registered as a
    // parity pair (decisions § 1095): `@supabase/functions-js` RETURNS
    // `{data, error}` so web's half is one expression over a nullable error,
    // while `functions_client` THROWS so Dart's is control flow, and a Dart
    // `provider_probe.dart` would take an error value no Dart caller holds.
    // What a registered pair would have bought is the two halves read against
    // each other — which is this, and it costs one file read instead of a
    // module with one call site and rows in two registries.
    final web =
        File('../web/src/lib/core/provider_probe.ts').readAsStringSync();
    expect(web.contains('export function probeSaysConfigured('), isTrue,
        reason: 're-anchor: web renamed or moved the probe grader');
    expect(
      RegExp(r'return error === null \|\| error === undefined;').hasMatch(web),
      isTrue,
      reason: "web's grader no longer reports configured iff the call did not "
          'fail. RaceService.isProviderConfigured states the same rule '
          'natively and has to move with it.',
    );
    final webCode = web
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('///'))
        .join('\n');
    expect(webCode.contains('status'), isFalse,
        reason: 'web grades a status again — the § 1073 defect returning on '
            'the platform this one cannot see.');
  });

  test('a probe that cannot reach Supabase answers unconfigured', () async {
    // RaceService has no Supabase behind it here, so `_c` throws a StateError
    // before any call is made. That used to answer `true` — the phone offered
    // an import leg it had never confirmed exists.
    expect(await RaceService().isProviderConfigured('runsignup'), isFalse);
    expect(await RaceService().isProviderConfigured('ultrasignup'), isFalse);
    expect(await RaceService().isProviderConfigured('chronotrack'), isFalse);
  });

  test('the leg with a refusal beyond its credential is probed on its own leg', () {
    // `race-listings-sync` gates UltraSignup on ULTRASIGNUP_API_KEY alone.
    // `race-results-import` reads a keyless feed and answers on its own opt-in
    // and on whether the caller speaks the person flow (decisions § 1841), so
    // the two legs disagree, and the tile is about the results one — probing
    // the sync would advertise an import the results leg then refuses.
    final src =
        File('../backend/supabase/functions/race-results-import/handler.ts')
            .readAsStringSync();
    final probeBranch = src.indexOf('if (isProbe) {');
    expect(probeBranch, greaterThan(-1),
        reason: 'race-results-import no longer has a probe branch — reread it '
            'and re-anchor this guard');
    final listingId = src.indexOf('listingId required', probeBranch);
    final branch = src.substring(probeBranch, listingId);
    expect(
      RegExp(r"provider === 'ultrasignup'[\s\S]*ultraSignUpProbe\(")
          .hasMatch(branch),
      isTrue,
      reason: 'the probe branch no longer answers UltraSignup through its own '
          'gate (§ 1841). Re-decide which function the tile should probe '
          'rather than deleting the assertion below',
    );
    expect(
      raceImportProviderFor('ultrasignup')!.probeFunction,
      'race-results-import',
      reason: 'the UltraSignup tile must ask the leg that would actually run',
    );
    expect(
      raceImportProviderFor('ultrasignup')!.probeBody['probe'],
      isTrue,
      reason: 'race-results-import only reports configuration in probe mode; '
          'without the flag this becomes a real import with no listing',
    );
  });

  test('the catalogue names exactly the tokens the Edge Function accepts', () {
    final src =
        File('../backend/supabase/functions/race-results-import/handler.ts')
            .readAsStringSync();
    final m = RegExp(r'\[([^\]]*)\]\.includes\(provider\)').firstMatch(src);
    expect(m, isNotNull,
        reason: 'race-results-import no longer declares its provider vocabulary '
            'as an array literal — reread it and re-anchor this guard');
    final accepted = RegExp(r"'([a-z]+)'")
        .allMatches(m!.group(1)!)
        .map((g) => g.group(1)!)
        .toSet();
    expect(
      {...raceImportProviders.map((p) => p.provider), 'paste'},
      accepted,
      reason: 'a leg the function builds that the catalogue does not name is '
          'unreachable from the phone; a token the catalogue names that the '
          'function refuses is a 400 the runner reads as a failed import',
    );
  });

  test('every leg is probed on the function that would run it', () {
    // § 1008 moved UltraSignup and left RunSignUp probing `race-listings-sync`
    // as an explicit compromise: while `race-results-import` charged a probe to
    // its 8/hour import bucket, a third probe per settings load would have cost
    // a free runner the ability to import at all. The bucket split removed the
    // reason, so no client asks the sync about a leg it does not own.
    for (final p in raceImportProviders) {
      expect(p.probeFunction, 'race-results-import', reason: p.provider);
      expect(p.probeBody['probe'], isTrue, reason: p.provider);
      expect(p.probeBody['provider'], p.provider, reason: p.provider);
    }
  });

  test('a credential probe is charged to its own bucket, not the import allowance',
      () {
    // The premise the move above rests on, read off the function rather than
    // restated: a probe reads env vars and returns, an import spends a shared
    // per-application credential and writes rows. If the two are ever collapsed
    // back onto one bucket the client change becomes the § 1008 defect again —
    // and an exhausted bucket answers 429, which is not a 200 and so reports
    // the provider unavailable (§ 1007, § 1073), making the failure silent and
    // total rather than a limit the runner can see.
    final src =
        File('../backend/supabase/functions/race-results-import/handler.ts')
            .readAsStringSync();
    expect(src.contains('const denied = isProbe'), isTrue,
        reason: 'race-results-import no longer selects its bucket on the probe '
            'flag — reread it and re-anchor this guard');
    List<int> limitsFor(String bucket) {
      final m = RegExp(
        "'${RegExp.escape(bucket)}',\\s*(\\d+),\\s*(\\d+),",
      ).firstMatch(src);
      expect(m, isNotNull, reason: 'no checkRateLimitTiered call for $bucket');
      return [int.parse(m!.group(1)!), int.parse(m.group(2)!)];
    }

    final probe = limitsFor('race-results-import:probe');
    final import = limitsFor('race-results-import');
    expect(probe[0], greaterThan(import[0]),
        reason: 'the probe bucket is no more generous than the import one, so '
            'opening Settings still spends imports');
    expect(probe[1], greaterThan(import[1]),
        reason: 'the Pro probe bucket is no more generous than the import one');
  });

  group('UltraSignup is scoped by the linked person (decisions § 1841)', () {
    test('the probe says this client speaks the person flow', () {
      // The function answers 503 `client_unsupported` to a probe without the
      // flag, on purpose, so a build still sending the retired athlete id
      // stays dark. This build does not, so it must say so or its tile never
      // lights.
      final body = raceImportProviderFor('ultrasignup')!.probeBody;
      expect(body['ultraSignUpFlow'], 'person');
      final lib = File('../backend/supabase/functions/race-results-import/lib.ts')
          .readAsStringSync();
      expect(lib.contains("if (flow !== 'person')"), isTrue,
          reason: 'ultraSignUpProbe no longer gates on the person flow token — '
              'reread it and re-anchor this guard');
    });

    test('the person scope asks for nothing typed per race', () {
      expect(raceImportProviderFor('ultrasignup')!.scope,
          RaceImportScope.linkedPerson);
    });

    test('an unlinked runner is refused before any call is made', () async {
      final api = _LinkApi();
      // No Supabase is initialised, so reaching the function would throw a
      // StateError rather than the refusal asserted here.
      final service = RaceService(api: api);
      await expectLater(
        service.importRaceResult(provider: 'ultrasignup', listingId: 'l1'),
        throwsA(isA<UltraSignUpNotLinked>()),
      );
      expect(api.linkReads, 1,
          reason: 'with no person handed in, the stored link is read first');
    });

    test('a person handed in is used without reading the stored link', () async {
      final api = _LinkApi();
      final service = RaceService(api: api);
      await expectLater(
        service.importRaceResult(
          provider: 'ultrasignup',
          listingId: 'l1',
          ultraSignUpPerson: const UltraSignUpPersonLink(
              personId: '1', firstName: 'A', lastName: 'B'),
        ),
        throwsA(isA<StateError>()),
        reason: 'past the link gate the call reaches for Supabase, which this '
            'test has not initialised',
      );
      expect(api.linkReads, 0);
    });

    test('another provider never reads the UltraSignup link', () async {
      final api = _LinkApi();
      final service = RaceService(api: api);
      await expectLater(
        service.importRaceResult(provider: 'runsignup', listingId: 'l1', bib: '7'),
        throwsA(isA<StateError>()),
      );
      expect(api.linkReads, 0);
    });

    test('a lookup the deployment has switched off is UltraSignup\'s explainer',
        () async {
      final service = RaceService(
        api: _LinkApi(
          lookupError: const FunctionException(
            status: 503,
            details: {'error': 'provider_not_configured'},
          ),
        ),
      );
      await expectLater(
        service.lookupUltraSignUpPeople('Ada', 'Lovelace'),
        throwsA(same(raceImportProviderFor('ultrasignup')!.unavailable)),
      );
    });

    test('any other lookup refusal is passed through, not relabelled', () async {
      final service = RaceService(
        api: _LinkApi(
          lookupError: const FunctionException(
            status: 400,
            details: {'error': 'ultrasignup_name_required'},
          ),
        ),
      );
      await expectLater(
        service.lookupUltraSignUpPeople('Ada', ''),
        throwsA(isA<FunctionException>()),
      );
    });
  });
}
