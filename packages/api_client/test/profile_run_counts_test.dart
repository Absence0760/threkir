import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// fetchProfileRunCounts gives the profile header a total instead of the
/// length of the capped run page. The public figure must come from the same
/// `public_runs` view the Runs tab lists (so private profiles and
/// followers-only audiences are honoured), and only the owner may cost the
/// second, base-table count of their non-public runs.
class _FakeHttp extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final Map<String, (int, String)> rangeByPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    var reply = (200, '*/0');
    for (final e in rangeByPath.entries) {
      if (request.url.path.endsWith(e.key)) reply = e.value;
    }
    return http.StreamedResponse(
      const Stream.empty(),
      reply.$1,
      headers: {'content-type': 'application/json', 'content-range': reply.$2},
      request: request,
    );
  }

  Iterable<http.BaseRequest> to(String path) =>
      requests.where((r) => r.url.path.endsWith(path));
}

const _publicPath = '/rest/v1/public_runs';
const _runsPath = '/rest/v1/runs';

void main() {
  late _FakeHttp fake;
  late SupabaseClient client;
  late ApiClient api;

  setUp(() {
    fake = _FakeHttp()
      ..rangeByPath[_publicPath] = (200, '0-0/142')
      ..rangeByPath[_runsPath] = (200, '0-0/7');
    client = SupabaseClient(
      'http://127.0.0.1:24321',
      'test-anon-key',
      httpClient: fake,
    );
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  test('the owner gets the public total and the count of the rest', () async {
    final counts = await api.fetchProfileRunCounts('user-1', isSelf: true);

    expect(counts.publicCount, 142);
    expect(counts.privateCount, 7);

    final pub = fake.to(_publicPath).single;
    expect(pub.method, 'HEAD');
    expect(pub.headers['Prefer'], contains('count=exact'));
    expect(pub.url.queryParameters['user_id'], 'eq.user-1');

    final priv = fake.to(_runsPath).single;
    expect(priv.method, 'HEAD');
    expect(priv.url.queryParameters['user_id'], 'eq.user-1');
    expect(
      priv.url.queryParameters['or'],
      '(is_public.is.null,is_public.eq.false)',
      reason:
          'a null is_public is a run that was never made public, so it '
          'is not on the profile either',
    );
  });

  test(
    'another viewer gets the public total only, and no base-table read',
    () async {
      final counts = await api.fetchProfileRunCounts('user-2', isSelf: false);

      expect(counts.publicCount, 142);
      expect(counts.privateCount, isNull);
      expect(
        fake.to(_runsPath),
        isEmpty,
        reason: 'RLS empties a non-owner read of runs; the call is wasted',
      );
    },
  );

  test('a refused count throws rather than reading as zero', () async {
    fake.rangeByPath[_publicPath] = (403, '*/*');

    await expectLater(
      api.fetchProfileRunCounts('user-1', isSelf: true),
      throwsA(isA<PostgrestException>()),
    );
  });
}
