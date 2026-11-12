/// One `route_delete_impact` row (migration 20271106000001): what deleting a
/// route takes with it or detaches. "Others" counts leave out the caller's own
/// rows. Mirrors web `routes/route_delete_impact.ts`.
class RouteDeleteImpact {
  final int savedByOthers;
  final int reviewsByOthers;
  final int conditionsByOthers;
  final int segmentsByOthers;
  final int segmentEffortsByOthers;
  final int shares;
  final int raceListings;
  final int events;
  final int linkedRuns;
  final int photos;
  final int markers;

  const RouteDeleteImpact({
    this.savedByOthers = 0,
    this.reviewsByOthers = 0,
    this.conditionsByOthers = 0,
    this.segmentsByOthers = 0,
    this.segmentEffortsByOthers = 0,
    this.shares = 0,
    this.raceListings = 0,
    this.events = 0,
    this.linkedRuns = 0,
    this.photos = 0,
    this.markers = 0,
  });

  factory RouteDeleteImpact.fromRow(Map<String, dynamic> row) {
    int n(String key) {
      final v = row[key];
      return v is num ? v.toInt() : 0;
    }

    return RouteDeleteImpact(
      savedByOthers: n('saved_by_others'),
      reviewsByOthers: n('reviews_by_others'),
      conditionsByOthers: n('conditions_by_others'),
      segmentsByOthers: n('segments_by_others'),
      segmentEffortsByOthers: n('segment_efforts_by_others'),
      shares: n('shares'),
      raceListings: n('race_listings'),
      events: n('events'),
      linkedRuns: n('linked_runs'),
      photos: n('photos'),
      markers: n('markers'),
    );
  }
}

/// The server refused a route delete: RLS filters a refused DELETE rather
/// than raising, so the route is still there after a delete that removed
/// nothing. Terminal — retrying the same session's delete cannot succeed.
class RouteDeleteRefusedException implements Exception {
  final String routeId;

  const RouteDeleteRefusedException(this.routeId);

  @override
  String toString() => 'RouteDeleteRefusedException(route $routeId)';
}
