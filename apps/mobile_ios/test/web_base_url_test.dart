import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/web_base_url.dart';

void main() {
  tearDown(dotenv.clean);

  test('reads WEB_BASE_URL and drops trailing slashes', () {
    dotenv.loadFromString(
      envString: 'WEB_BASE_URL=https://preview.threkir.com//',
    );
    expect(resolveWebBaseUrl(), 'https://preview.threkir.com');
  });

  test('an unloaded dotenv falls back to production instead of throwing', () {
    dotenv.clean();
    expect(dotenv.isInitialized, isFalse);
    expect(resolveWebBaseUrl(), kDefaultWebBaseUrl);
  });

  test('a blank or whitespace WEB_BASE_URL falls back to production', () {
    dotenv.loadFromString(envString: 'WEB_BASE_URL=');
    expect(resolveWebBaseUrl(), kDefaultWebBaseUrl);
    dotenv.loadFromString(envString: 'WEB_BASE_URL=   ');
    expect(resolveWebBaseUrl(), kDefaultWebBaseUrl);
  });

  test('a missing key falls back to production', () {
    dotenv.loadFromString(envString: 'OTHER=1');
    expect(resolveWebBaseUrl(), kDefaultWebBaseUrl);
  });

  test('an override wins over dotenv and is normalised the same way', () {
    dotenv.loadFromString(
      envString: 'WEB_BASE_URL=https://preview.threkir.com',
    );
    expect(
      resolveWebBaseUrl(override: ' https://local.test/ '),
      'https://local.test',
    );
    expect(resolveWebBaseUrl(override: ''), kDefaultWebBaseUrl);
  });

  test('webPageUrl joins a path onto the resolved origin', () {
    dotenv.loadFromString(
      envString: 'WEB_BASE_URL=https://preview.threkir.com/',
    );
    expect(webPageUrl('/settings/upgrade'),
        'https://preview.threkir.com/settings/upgrade');
    expect(webPageUrl('/privacy', override: ''), '$kDefaultWebBaseUrl/privacy');
  });

  test('no surface under lib/ reads WEB_BASE_URL except through the resolver',
      () {
    // An inline read is how six surfaces came to turn a blank value into a
    // relative URL. main.dart only forwards the build-time define to dotenv.
    final key = RegExp(r"""['"]WEB_BASE_URL['"]""");
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\\', '/');
      if (path == 'lib/web_base_url.dart' || path == 'lib/main.dart') continue;
      if (key.hasMatch(f.readAsStringSync())) offenders.add(path);
    }
    expect(offenders, isEmpty);
  });

  test('no code under lib/ hardcodes the production web origin', () {
    // A literal origin sends a preview build's runner to production: the
    // upgrade page and the Strava connect fallback both did. Comments are
    // skipped; an inbound-link host check matches 'threkir.com' without a
    // scheme and is not an outbound link, so it never matches.
    final origin = RegExp(r'https?://(www\.)?threkir\.com(?![\w.-])');
    const allowed = {
      'lib/web_base_url.dart':
          'the production fallback itself, used only when no origin is set',
    };
    final offenders = <String>[];
    final seen = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\\', '/');
      final code = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (!origin.hasMatch(code)) continue;
      if (allowed.containsKey(path)) {
        seen.add(path);
      } else {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'build the URL with webPageUrl / resolveWebBaseUrl');
    expect(seen, allowed.keys.toSet(),
        reason: 'an allowlist entry no longer holds the literal; remove it');
  });
}
