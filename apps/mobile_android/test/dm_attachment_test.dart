import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_attachment.dart';

/// Mirror of `apps/web/src/lib/social/dm_attachment.test.ts` — one case per
/// web case, same inputs, same answers.
void main() {
  const card = DmRouteCard(
    id: 'r1',
    name: 'Cliff Trail Loop',
    distanceM: 8200,
    waypoints: [(lat: 1, lng: 1), (lat: 2, lng: 2)],
  );

  test('a message with no attachment renders as plain text', () {
    expect(dmAttachmentView(null, null), isA<DmAttachmentText>());
  });

  test('a blank route id is not an attachment', () {
    expect(dmAttachmentView('', const DmAttachmentPending()),
        isA<DmAttachmentText>());
    expect(dmAttachmentView('   ', const DmAttachmentPending()),
        isA<DmAttachmentText>());
  });

  test('an unresolved attachment is pending, never an empty card', () {
    expect(dmAttachmentView('r1', null), isA<DmAttachmentLoading>());
    expect(dmAttachmentView('r1', const DmAttachmentPending()),
        isA<DmAttachmentLoading>());
  });

  test('a resolved route renders the card', () {
    final view = dmAttachmentView('r1', const DmAttachmentResolved(card));
    expect(view, isA<DmAttachmentCard>());
    expect((view as DmAttachmentCard).route, same(card));
  });

  test('a route the reader cannot see says so instead of falling back to text',
      () {
    expect(dmAttachmentView('r1', const DmAttachmentResolved(null)),
        isA<DmAttachmentUnavailable>());
  });

  test('a blank route name resolves to null so the render can localize a '
      'fallback', () {
    expect(dmRouteCardFrom(id: 'r1', name: '   ').name, isNull);
    expect(dmRouteCardFrom(id: 'r1', name: null).name, isNull);
    expect(dmRouteCardFrom(id: 'r1', name: ' Ridge ').name, 'Ridge');
  });

  test('distance comes back as a number, and an unusable one as null', () {
    expect(dmRouteCardFrom(id: 'r1', distanceM: '8200.00').distanceM, 8200);
    expect(dmRouteCardFrom(id: 'r1', distanceM: null).distanceM, isNull);
    expect(dmRouteCardFrom(id: 'r1', distanceM: 'nope').distanceM, isNull);
    expect(dmRouteCardFrom(id: 'r1', distanceM: 0).distanceM, isNull);
  });

  test('waypoints keep only usable points and default to an empty line', () {
    final kept = dmRouteCardFrom(id: 'r1', waypoints: [
      {'lat': 1, 'lng': 1},
      {'lat': 'x', 'lng': 2},
      null,
      {'lat': 2, 'lng': 2},
    ]);
    expect(kept.waypoints, [(lat: 1.0, lng: 1.0), (lat: 2.0, lng: 2.0)]);
    expect(dmRouteCardFrom(id: 'r1').waypoints, isEmpty);
    expect(dmRouteCardFrom(id: 'r1', waypoints: 'nope').waypoints, isEmpty);
  });

  test('a clipped-to-nothing line still renders the card, only without a '
      'trace', () {
    final clippedAway =
        dmRouteCardFrom(id: 'r1', name: 'Ridge', distanceM: 5000);
    expect(dmRouteCardHasTrace(clippedAway), isFalse);
    expect(dmAttachmentView('r1', DmAttachmentResolved(clippedAway)),
        isA<DmAttachmentCard>());
    expect(dmRouteCardHasTrace(card), isTrue);
    expect(
      dmRouteCardHasTrace(dmRouteCardFrom(id: 'r1', waypoints: [
        {'lat': 1, 'lng': 1},
      ])),
      isFalse,
    );
  });

  test('an attachment id is recognised only when it is not blank', () {
    expect(hasDmRouteAttachment('r1'), isTrue);
    expect(hasDmRouteAttachment(''), isFalse);
    expect(hasDmRouteAttachment('  '), isFalse);
    expect(hasDmRouteAttachment(null), isFalse);
  });

  const routeUuid = '1f0f9d2c-7c58-4a1e-9d2b-6b4a8c5e1234';

  test('the share URL v1 sends as the body is suppressed once the card draws '
      'it', () {
    expect(
        bodyRestatesAttachment(
            'https://threkir.com/share/route/$routeUuid', routeUuid),
        isTrue);
    expect(
        bodyRestatesAttachment(
            'https://threkir.com/share/route/$routeUuid/', routeUuid),
        isTrue);
    expect(
        bodyRestatesAttachment(
            'https://threkir.com/routes/$routeUuid', routeUuid),
        isTrue);
    expect(
        bodyRestatesAttachment(
            'https://threkir.com/share/route/${routeUuid.toUpperCase()}',
            routeUuid),
        isTrue);
  });

  test('anything a human could have typed renders beside the card', () {
    expect(bodyRestatesAttachment('try this on Saturday', routeUuid), isFalse);
    expect(bodyRestatesAttachment('/share/route/$routeUuid', routeUuid),
        isFalse);
    expect(
        bodyRestatesAttachment(
            'https://threkir.com/share/route/00000000-0000-0000-0000-000000000000',
            routeUuid),
        isFalse);
    expect(
        bodyRestatesAttachment('https://threkir.com/runs/$routeUuid', routeUuid),
        isFalse);
    expect(bodyRestatesAttachment('', routeUuid), isFalse);
    expect(
        bodyRestatesAttachment('https://threkir.com/routes/$routeUuid', '  '),
        isFalse);
  });
}
