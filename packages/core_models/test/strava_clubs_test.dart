import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// Mirror of `apps/web/src/lib/integrations/strava_clubs.test.ts`. Two web
/// cases have no twin here, by design: the `strava_club` URL parameter, which
/// the phone never reads, and the prefill clamp, which the form applies and
/// `club_form_sheet_test.dart` pins.
const _wire = <String, Object?>{
  'strava_club_id': 101,
  'name': 'Richmond Run Club',
  'city': 'Richmond',
  'state': 'Virginia',
  'country': 'United States',
  'sport_type': 'running',
  'member_count': 42,
  'profile_url': 'https://dgalywyr863hv.cloudfront.net/x.jpg',
  'viewer_is_admin': true,
  'linked_club': {
    'id': 'c-1',
    'slug': 'richmond-run-club',
    'name': 'Richmond RC',
  },
};

void main() {
  test('a connected answer is graded club by club', () {
    final r = parseStravaClubsResult({
      'status': 'connected',
      'clubs': [
        _wire,
        {..._wire, 'strava_club_id': 'x'},
        {'strava_club_id': 7, 'name': 'Seven', 'viewer_is_admin': 'yes'},
      ],
    });
    expect(r.status, StravaClubsStatus.connected);
    expect(r.clubs, hasLength(2));
    expect(
      r.clubs[0],
      const StravaClub(
        stravaClubId: 101,
        name: 'Richmond Run Club',
        city: 'Richmond',
        state: 'Virginia',
        country: 'United States',
        sportType: 'running',
        memberCount: 42,
        viewerIsAdmin: true,
        linkedClub: StravaLinkedClub(
          id: 'c-1',
          slug: 'richmond-run-club',
          name: 'Richmond RC',
        ),
      ),
    );
    expect(r.clubs[1].viewerIsAdmin, isNull);
    expect(r.clubs[1].linkedClub, isNull);
    expect(r.clubs[1].memberCount, isNull);
  });

  test('not connected and a dead grant are answers, not errors', () {
    expect(parseStravaClubsResult({'status': 'not_connected'}).status,
        StravaClubsStatus.notConnected);
    expect(parseStravaClubsResult({'status': 'reconnect_required'}).status,
        StravaClubsStatus.reconnectRequired);
  });

  test('a body in none of the three shapes throws rather than reading as "no clubs"',
      () {
    expect(() => parseStravaClubsResult(null), throwsFormatException);
    expect(() => parseStravaClubsResult({'status': 'connected'}),
        throwsFormatException);
    expect(() => parseStravaClubsResult({'clubs': <Object?>[]}),
        throwsFormatException);
  });

  test('the location joins what Strava filled in and drops an exact repeat',
      () {
    expect(
        stravaClubLocation(
            city: 'Richmond', state: 'Virginia', country: 'United States'),
        'Richmond, Virginia, United States');
    expect(
        stravaClubLocation(
            city: 'Singapore', state: 'Singapore', country: 'Singapore'),
        'Singapore');
    expect(stravaClubLocation(country: 'France'), 'France');
    expect(stravaClubLocation(), '');
  });

  test('setting up a Strava club on Threkir carries its name, place and id to the form',
      () {
    final setup = stravaClubSetup(const StravaClub(
      stravaClubId: 101,
      name: 'Run & Done',
      city: 'Leeds',
      country: 'United Kingdom',
    ));
    expect(setup.name, 'Run & Done');
    expect(setup.location, 'Leeds, United Kingdom');
    expect(setup.stravaClubId, 101);
    final bare =
        stravaClubSetup(const StravaClub(stravaClubId: 5, name: 'X'));
    expect(bare.location, '');
  });

  test('each link refusal maps to the sentence that explains it', () {
    expect(stravaClubLinkError('strava_admin_required'),
        StravaClubLinkError.stravaAdminRequired);
    expect(stravaClubLinkError('strava_club_already_linked'),
        StravaClubLinkError.stravaClubAlreadyLinked);
    expect(stravaClubLinkError('not_club_admin'),
        StravaClubLinkError.notClubAdmin);
    expect(stravaClubLinkError('refresh_failed'),
        StravaClubLinkError.reconnect);
    expect(stravaClubLinkError('strava_not_connected'),
        StravaClubLinkError.reconnect);
    expect(stravaClubLinkError('link_failed'), StravaClubLinkError.generic);
    expect(stravaClubLinkError(null), StravaClubLinkError.generic);
  });

  test('a whole-number double reads as the id web would read, a fraction does not',
      () {
    final r = parseStravaClubsResult({
      'status': 'connected',
      'clubs': [
        {'strava_club_id': 9.0, 'name': 'Nine', 'member_count': 3.0},
        {'strava_club_id': 1.5, 'name': 'Half'},
        {'strava_club_id': 0, 'name': 'Zero'},
      ],
    });
    expect(r.clubs.map((c) => c.stravaClubId), [9]);
    expect(r.clubs.single.memberCount, 3);
  });
}
