import 'package:flutter_test/flutter_test.dart';

import '../lib/event_waitlist_offer.dart';

// Mirrors the waitlistOfferState cases in web's
// src/lib/social/event_waitlist_offer.test.ts.
final _now = DateTime.utc(2026, 10, 13, 12);

void main() {
  test('no row, or a row that is not waitlisted, is not on the waitlist', () {
    expect(waitlistOfferState(status: null, offerExpiresAt: null, now: _now),
        isA<WaitlistNone>());
    expect(
        waitlistOfferState(status: 'going', offerExpiresAt: null, now: _now),
        isA<WaitlistNone>());
    // A stale deadline on a row that has moved on is not an offer.
    expect(
        waitlistOfferState(
            status: 'declined',
            offerExpiresAt: DateTime.utc(2026, 10, 13, 20),
            now: _now),
        isA<WaitlistNone>());
  });

  test('a queued waitlister with no offer is waiting', () {
    expect(
        waitlistOfferState(
            status: 'waitlisted', offerExpiresAt: null, now: _now),
        isA<WaitlistWaiting>());
  });

  test('a future deadline is a held seat, carrying the deadline', () {
    final deadline = DateTime.utc(2026, 10, 13, 20);
    final state = waitlistOfferState(
        status: 'waitlisted', offerExpiresAt: deadline, now: _now);
    expect(state, isA<WaitlistOffered>());
    expect((state as WaitlistOffered).deadline, deadline);
  });

  test('a passed deadline is lapsed, never a held seat', () {
    for (final at in [DateTime.utc(2026, 10, 13, 12), DateTime.utc(2026, 10, 13, 11)]) {
      expect(
          waitlistOfferState(status: 'waitlisted', offerExpiresAt: at, now: _now),
          isA<WaitlistLapsed>());
    }
  });
}
