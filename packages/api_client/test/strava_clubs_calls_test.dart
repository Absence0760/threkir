import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The `strava-clubs` wrappers name the function, its actions and the unlink
/// RPC by hand, and translate the function's refusal bodies into
/// [StravaClubLinkFailure]. The fake sits at the http boundary and answers by
/// path; the functions client, PostgREST builder and ApiClient are real.
/// Mirrors web `fetchMyStravaClubs` / `linkStravaClub` / `unlinkStravaClub`.
class _FakeHttp extends http.BaseClient {
  final List<http.Request> requests = [];
  final Map<String, (int, Object?)> answerByPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    final match = answerByPath.entries
        .where((e) => request.url.path.endsWith(e.key))
        .map((e) => e.value);
    final (status, body) = match.isEmpty ? (200, null) : match.first;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  Iterable<http.Request> to(String pathSuffix) =>
      requests.where((r) => r.url.path.endsWith(pathSuffix));
}

const _fnPath = '/functions/v1/strava-clubs';
const _unlinkPath = '/rest/v1/rpc/unlink_club_strava';

void main() {
  late _FakeHttp fake;
  late SupabaseClient client;
  late ApiClient api;

  setUp(() {
    fake = _FakeHttp();
    client = SupabaseClient(
      'http://127.0.0.1:24321',
      'test-anon-key',
      httpClient: fake,
    );
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  group('fetchMyStravaClubs', () {
    test('asks the function for the list and grades the answer', () async {
      fake.answerByPath[_fnPath] = (
        200,
        {
          'status': 'connected',
          'clubs': [
            {'strava_club_id': 101, 'name': 'Leeds Striders'},
          ],
        },
      );

      final r = await api.fetchMyStravaClubs();

      final req = fake.to(_fnPath).single;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'action': 'list'});
      expect(r.status, StravaClubsStatus.connected);
      expect(r.clubs.single.name, 'Leeds Striders');
    });

    test('not being connected is an answer', () async {
      fake.answerByPath[_fnPath] = (200, {'status': 'not_connected'});
      expect((await api.fetchMyStravaClubs()).status,
          StravaClubsStatus.notConnected);
    });

    test('a body in none of the shapes throws rather than reading as no clubs',
        () async {
      fake.answerByPath[_fnPath] = (200, {'clubs': <Object?>[]});
      await expectLater(api.fetchMyStravaClubs(), throwsFormatException);
    });

    test('a failed call throws', () async {
      fake.answerByPath[_fnPath] = (502, {'error': 'strava_unavailable'});
      await expectLater(
          api.fetchMyStravaClubs(), throwsA(isA<FunctionException>()));
    });
  });

  group('linkStravaClub', () {
    test('posts the link action with both ids', () async {
      fake.answerByPath[_fnPath] = (200, {'ok': true});

      await api.linkStravaClub('club-1', 918273645);

      final req = fake.to(_fnPath).single;
      expect(jsonDecode(req.body), {
        'action': 'link',
        'club_id': 'club-1',
        'strava_club_id': 918273645,
      });
    });

    for (final (status, code, reason) in [
      (403, 'strava_admin_required', StravaClubLinkError.stravaAdminRequired),
      (409, 'strava_club_already_linked',
          StravaClubLinkError.stravaClubAlreadyLinked),
      (403, 'not_club_admin', StravaClubLinkError.notClubAdmin),
      (401, 'refresh_failed', StravaClubLinkError.reconnect),
      (400, 'strava_not_connected', StravaClubLinkError.reconnect),
      (500, 'link_failed', StravaClubLinkError.generic),
    ]) {
      test('a $status $code refusal names ${reason.name}', () async {
        fake.answerByPath[_fnPath] = (status, {'error': code});
        await expectLater(
          api.linkStravaClub('club-1', 1),
          throwsA(isA<StravaClubLinkFailure>()
              .having((f) => f.reason, 'reason', reason)),
        );
      });
    }
  });

  group('unlinkStravaClub', () {
    test('calls the RPC with the club id', () async {
      fake.answerByPath[_unlinkPath] = (200, true);

      await api.unlinkStravaClub('club-1');

      final req = fake.to(_unlinkPath).single;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'p_club_id': 'club-1'});
    });

    test('a false answer is the not-an-admin refusal', () async {
      fake.answerByPath[_unlinkPath] = (200, false);
      await expectLater(
        api.unlinkStravaClub('club-1'),
        throwsA(isA<StravaClubLinkFailure>().having(
            (f) => f.reason, 'reason', StravaClubLinkError.notClubAdmin)),
      );
    });
  });
}
