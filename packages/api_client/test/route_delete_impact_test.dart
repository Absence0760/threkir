import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RouteDeleteImpact.fromRow reads every route_delete_impact column', () {
    final impact = RouteDeleteImpact.fromRow({
      'saved_by_others': 1,
      'reviews_by_others': 2,
      'conditions_by_others': 3,
      'segments_by_others': 4,
      'segment_efforts_by_others': 5,
      'shares': 6,
      'race_listings': 7,
      'events': 8,
      'linked_runs': 9,
      'photos': 10,
      'markers': 11,
    });
    expect(
      [
        impact.savedByOthers,
        impact.reviewsByOthers,
        impact.conditionsByOthers,
        impact.segmentsByOthers,
        impact.segmentEffortsByOthers,
        impact.shares,
        impact.raceListings,
        impact.events,
        impact.linkedRuns,
        impact.photos,
        impact.markers,
      ],
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    );
  });

  test('a missing or non-numeric column reads as zero, never a throw', () {
    final impact = RouteDeleteImpact.fromRow({'photos': null, 'markers': 'x'});
    expect(impact.photos, 0);
    expect(impact.markers, 0);
    expect(impact.raceListings, 0);
  });
}
