/// The viewer's place on a paid occurrence's waitlist (migration
/// 20270726000002, decisions § 1840). When a seat frees, the earliest
/// waitlister is not seated but OFFERED it until
/// `event_attendees.offer_expires_at`. Dart twin of `waitlistOfferState` in
/// web's `apps/web/src/lib/social/event_waitlist_offer.ts` — keep the two in
/// lockstep. Web reads the deadline as a string and treats an unparseable one
/// as lapsed; here the row is parsed at the read boundary, so a deadline that
/// did not parse arrives as null and the row reads as waiting.
sealed class WaitlistOfferState {
  const WaitlistOfferState();
}

/// Not on the waitlist (no row, or any other status).
class WaitlistNone extends WaitlistOfferState {
  const WaitlistNone();
}

/// Queued; nothing has been offered.
class WaitlistWaiting extends WaitlistOfferState {
  const WaitlistWaiting();
}

/// A seat is held for the viewer until [deadline]; paying claims it.
class WaitlistOffered extends WaitlistOfferState {
  final DateTime deadline;
  const WaitlistOffered(this.deadline);
}

/// The deadline has passed and the mover has not removed the row yet. Nothing
/// is held any more, so the screen must not promise the seat.
class WaitlistLapsed extends WaitlistOfferState {
  const WaitlistLapsed();
}

WaitlistOfferState waitlistOfferState({
  required String? status,
  required DateTime? offerExpiresAt,
  required DateTime now,
}) {
  if (status != 'waitlisted') return const WaitlistNone();
  if (offerExpiresAt == null) return const WaitlistWaiting();
  if (!offerExpiresAt.isAfter(now)) return const WaitlistLapsed();
  return WaitlistOffered(offerExpiresAt);
}
