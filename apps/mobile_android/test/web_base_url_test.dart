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
}
