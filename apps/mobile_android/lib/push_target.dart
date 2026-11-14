/// The in-app surface a tapped push notification should open.
///
/// The Go worker stamps an ABSOLUTE web URL into the notification's `url`
/// data key (`pathForKind` in `apps/job_worker/internal/mailer.go`, shared by
/// the email CTA, the web-push payload and the native FCM/APNs message), so
/// the phone receives e.g. `https://threkir.com/runs/<id>`. This maps that URL
/// onto a typed target the app can navigate to.
///
/// Pure — no BuildContext, no navigation, no I/O — so the whole target table
/// is host-testable. The host ([HomeScreen]) owns the actual push.
enum PushTargetKind {
  /// The notifications inbox. Also the degrade-to target for anything we
  /// can't recognise, mirroring `pathForKind`'s own `default:` arm — a
  /// notification the app can't place still opens the list it came from
  /// rather than being silently dropped.
  notifications,

  /// A user profile (`/u/<id>`).
  profile,

  /// A single run (`/runs/<id>`, or the `/share/run/<id>` a run_completed
  /// push carries — the in-app run, not the public page).
  run,

  /// A run opened on its PR card (`/runs/<id>?share=pr`, the URL a
  /// personal_record push carries). Carries the run UUID.
  runPrCard,

  /// The recipient's own Achievements tab (`/share/badge/<id>`, the URL an
  /// achievement push carries). The badge is always the recipient's own, so
  /// no id is needed to place it.
  badges,

  /// The training-plan list (`/plans`).
  plans,

  /// One training plan (`/plans/<id>`). Carries the plan UUID.
  plan,

  /// One workout of a plan (`/plans/<id>/workouts/<workout id>`). Carries
  /// the plan UUID as [PushTarget.id] and the workout's as
  /// [PushTarget.workoutId].
  planWorkout,

  /// A public-library plan's preview (`/plans/library/<id>`, or the
  /// `/share/plan/<id>` "Train with me" page), where the reader starts it.
  /// Carries the plan UUID.
  planLibrary,

  /// The challenge list (`/challenges`).
  challenges,

  /// The clubs hub (`/clubs`) — the worker's fallback when a club- or
  /// event-scoped notification carries no id.
  clubs,

  /// A single club (`/clubs/<id>`). Carries the club UUID; the mobile club
  /// screen is slug-addressed, so the host resolves id → slug before pushing.
  club,

  /// A single club event (`/events/<id>`). Carries the event UUID; the host
  /// resolves the owning club's slug before pushing.
  event,

  /// The direct-message inbox (`/messages`), or one conversation when the
  /// URL names the partner (`/messages/<user id>`, web's own thread path).
  messages,

  /// One group conversation (`/messages/group/<conversation id>`), the
  /// target of a group message notice (decisions § 2463).
  groupThread,

  /// The inbox's Requests list (`/messages?view=requests`), where a group
  /// invitation is answered.
  messageRequests,

  /// An organiser's course alert (`/course-alerts/<id>`, decisions § 2407).
  /// Carries the alert UUID; the host resolves it to the race or the route
  /// the alert is on, as web's resolver page does.
  courseAlert,

  /// the Account page (web `/settings/account`, the You tab on mobile), where a finished Art 20
  /// export is collected. Carries no id: the export lives in
  /// `data_export_jobs` and the screen reads the subject's latest one.
  settingsAccount,
}

/// A resolved push target: a [kind] plus the entity id when the kind carries
/// one. Value type so tests can compare targets directly.
class PushTarget {
  const PushTarget(this.kind, [this.id, this.workoutId, this.shareRef]);

  final PushTargetKind kind;
  final String? id;

  /// The plan workout a [PushTargetKind.planWorkout] opens; null otherwise.
  final String? workoutId;

  /// The `ref` a creator's share link carried, for the copy a
  /// [PushTargetKind.planLibrary] link may lead to (decisions § 2268).
  final String? shareRef;

  static const inbox = PushTarget(PushTargetKind.notifications);

  @override
  bool operator ==(Object other) =>
      other is PushTarget &&
      other.kind == kind &&
      other.id == id &&
      other.workoutId == workoutId &&
      other.shareRef == shareRef;

  @override
  int get hashCode => Object.hash(kind, id, workoutId, shareRef);

  @override
  String toString() => 'PushTarget(${kind.name}'
      '${id == null ? '' : ', $id'}'
      '${workoutId == null ? '' : ', $workoutId'})';
}

final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// The plan surface a path under `/plans` names, given its non-empty
/// segments starting at `plans`: `/plans/<id>` is that plan and
/// `/plans/<id>/workouts/<workout id>` that workout, matching web's routes.
/// `/plans/library/<id>` is a public-library plan's preview. Anything else
/// under a plan id degrades to that plan, and anything else under `/plans`
/// (`/plans/new`, `/plans/library`) to the plan list.
PushTarget planTargetFromSegments(List<String> segments) {
  const list = PushTarget(PushTargetKind.plans);
  if (segments.isEmpty || segments.first != 'plans') return list;
  if (segments.length == 3 &&
      segments[1] == 'library' &&
      _uuid.hasMatch(segments[2])) {
    return PushTarget(PushTargetKind.planLibrary, segments[2].toLowerCase());
  }
  if (segments.length < 2 || !_uuid.hasMatch(segments[1])) return list;
  final planId = segments[1].toLowerCase();
  if (segments.length == 4 &&
      segments[2] == 'workouts' &&
      _uuid.hasMatch(segments[3])) {
    return PushTarget(
        PushTargetKind.planWorkout, planId, segments[3].toLowerCase());
  }
  return PushTarget(PushTargetKind.plan, planId);
}

/// Maps a push notification's `url` data key onto a [PushTarget].
///
/// Total and never throws: a null / blank / unparseable / unknown URL resolves
/// to [PushTarget.inbox]. The origin is ignored on purpose — the same build
/// receives links stamped with whichever `APP_BASE_URL` the environment runs
/// (prod, preview, a local worker), and a relative path is accepted too.
PushTarget pushTargetFromUrl(String? url) {
  if (url == null) return PushTarget.inbox;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return PushTarget.inbox;

  // pathSegments drops the origin and the query/fragment and percent-decodes
  // each segment; the empty filter absorbs a trailing slash and any doubled
  // separator. Wrapped because this runs on a payload we didn't author — a
  // throw here would lose the tap, and the inbox is the honest degrade.
  List<String> segments;
  Map<String, String> query;
  try {
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return PushTarget.inbox;
    segments =
        uri.pathSegments.where((s) => s.isNotEmpty).toList(growable: false);
    query = uri.queryParameters;
  } catch (_) {
    return PushTarget.inbox;
  }
  if (segments.isEmpty) return PushTarget.inbox;

  final head = segments.first;
  final id = segments.length > 1 ? segments[1] : null;

  switch (head) {
    case 'events':
      return id == null ? const PushTarget(PushTargetKind.clubs)
                        : PushTarget(PushTargetKind.event, id);
    case 'clubs':
      return id == null ? const PushTarget(PushTargetKind.clubs)
                        : PushTarget(PushTargetKind.club, id);
    case 'runs':
      if (id == null) return PushTarget.inbox;
      return query['share'] == 'pr'
          ? PushTarget(PushTargetKind.runPrCard, id)
          : PushTarget(PushTargetKind.run, id);
    case 'u':
      return id == null
          ? PushTarget.inbox
          : PushTarget(PushTargetKind.profile, id);
    case 'settings':
      // Only the Account screen is a push destination today. Any other
      // settings path degrades to the inbox rather than dumping the runner
      // on a screen the notification was not about.
      return id == 'account'
          ? const PushTarget(PushTargetKind.settingsAccount)
          : PushTarget.inbox;
    case 'plans':
      return planTargetFromSegments(segments);
    case 'challenges':
      return const PushTarget(PushTargetKind.challenges);
    // The worker stamps a bare `/messages` for a message push, so it opens
    // the conversation list; a URL naming the partner opens that thread, and
    // a group's own path opens the group.
    case 'messages':
      if (id == 'group') {
        final group = segments.length > 2 ? segments[2] : null;
        return group == null
            ? const PushTarget(PushTargetKind.messages)
            : PushTarget(PushTargetKind.groupThread, group);
      }
      if (id == null && query['view'] == 'requests') {
        return const PushTarget(PushTargetKind.messageRequests);
      }
      return PushTarget(PushTargetKind.messages, id);
    // The worker stamps the public share URL for the kinds an email may be
    // opened logged out from. A signed-in app opens the in-app view instead,
    // as web's inbox does.
    case 'share':
      final entityId = segments.length > 2 ? segments[2] : null;
      if (entityId == null) return PushTarget.inbox;
      return switch (id) {
        'run' => PushTarget(PushTargetKind.run, entityId),
        'badge' => const PushTarget(PushTargetKind.badges),
        'plan' when _uuid.hasMatch(entityId) =>
          PushTarget(PushTargetKind.planLibrary, entityId.toLowerCase()),
        _ => PushTarget.inbox,
      };
    case 'course-alerts':
      return id != null && _uuid.hasMatch(id)
          ? PushTarget(PushTargetKind.courseAlert, id.toLowerCase())
          : PushTarget.inbox;
    case 'notifications':
      return PushTarget.inbox;
    default:
      return PushTarget.inbox;
  }
}
