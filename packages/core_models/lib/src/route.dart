import 'package:json_annotation/json_annotation.dart';

import 'waypoint.dart';

part 'route.g.dart';

@JsonSerializable()
class Route {
  final String id;
  /// Owner of the route. Required for the privacy-zone clipping path —
  /// non-owner viewers must route through `clip_route_for_viewer`
  /// (decisions §33). Sourced from `routes.user_id` on the row.
  final String userId;
  final String name;
  final List<Waypoint> waypoints;
  final double distanceMetres;
  final double elevationGainMetres;
  final bool isPublic;
  final DateTime? createdAt;

  /// Predominant ground type: `road`, `trail`, or `mixed`. Web's route
  /// builder populates this; mobile imports preserve whatever the backend
  /// returns and default to null for GPX/KML imports that don't know.
  final String? surface;

  /// Free-form labels ("5k", "loop", "hill", "parkrun_course",
  /// "beginner"). Owner-editable, filterable on /explore.
  final List<String> tags;

  /// Editor's-pick flag. Curated (admin-set for now) to surface high-
  /// quality public routes on the Explore page.
  final bool featured;

  /// Cached count of `runs.route_id = this.id` rows. Maintained by a DB
  /// trigger, read-only from the client's perspective.
  final int runCount;

  /// User-curated "what I actually run" flag. Drives the watch's
  /// route picker (starred-only) so the runner doesn't scroll
  /// through every saved route on a 1.4-inch screen. Owner-editable
  /// from web / mobile; read-only on the watch.
  final bool isStarred;

  /// Club this route belongs to, if any. Owned routes can be
  /// transferred into a club's library or detached back to personal
  /// via `SocialService.setRouteClub`. `null` means personal. See
  /// `decisions.md § 30` (club-owned routes) and migration
  /// `20260520_001_club_owned_routes.sql`.
  final String? clubId;

  /// Free-form description set in the route builder's Save modal.
  /// Migration `20260902_001_routes_description.sql`. Rendered below
  /// the title on the route detail surfaces.
  final String? description;

  /// Published by a verified organiser: [clubId] names a verified club and
  /// the author is an active owner/admin of it. Derived server-side
  /// (`is_official`, migration 20271021000030) and never stored on the row,
  /// so it is true only on reads that select it.
  final bool official;

  /// The race's certified distance (`routes.official_distance_m`, migration
  /// 20271108000010). A course traced on street centre lines measures long,
  /// so when this is set it is the distance the route is shown as, and km
  /// markers scale along the line to it; [distanceMetres] stays the length of
  /// the line. Null means no official distance.
  final double? officialDistanceMetres;

  const Route({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.distanceMetres,
    this.userId = '',
    this.elevationGainMetres = 0,
    this.isPublic = false,
    this.createdAt,
    this.surface,
    this.tags = const [],
    this.featured = false,
    this.runCount = 0,
    this.isStarred = false,
    this.clubId,
    this.description,
    this.official = false,
    this.officialDistanceMetres,
  });

  /// This route with the named fields replaced and every other field kept.
  /// A toggle rewrites one flag through this rather than rebuilding the
  /// route by hand, which dropped whichever field the hand copy forgot
  /// (`clubId`, `official`; issue #1374 FS-12). A nullable field can be
  /// changed, not cleared.
  Route copyWith({
    String? name,
    List<Waypoint>? waypoints,
    bool? isPublic,
    List<String>? tags,
    bool? isStarred,
    String? clubId,
    String? description,
  }) =>
      Route(
        id: id,
        userId: userId,
        name: name ?? this.name,
        waypoints: waypoints ?? this.waypoints,
        distanceMetres: distanceMetres,
        elevationGainMetres: elevationGainMetres,
        isPublic: isPublic ?? this.isPublic,
        createdAt: createdAt,
        surface: surface,
        tags: tags ?? this.tags,
        featured: featured,
        runCount: runCount,
        isStarred: isStarred ?? this.isStarred,
        clubId: clubId ?? this.clubId,
        description: description ?? this.description,
        official: official,
        officialDistanceMetres: officialDistanceMetres,
      );

  factory Route.fromJson(Map<String, dynamic> json) => _$RouteFromJson(json);

  Map<String, dynamic> toJson() => _$RouteToJson(this);
}
