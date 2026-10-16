import 'plan_request_client.dart';
import 'season_types.dart';

/// Network glue for the season planner's "Describe your season" box: posts
/// the runner's description and resolves to the races found in it, for the
/// runner to confirm before anything is generated.
Future<SeasonRequestResult> requestSeasonRaces(
    String request, String todayIso) async {
  throw const PlanRequestError(PlanRequestErrorKind.unavailable);
}
