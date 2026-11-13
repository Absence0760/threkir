/// The pages Preferences is split into, in web's order
/// (`apps/web/src/lib/settings/preferences_ia.ts`, issue #905).
///
/// One page of about 65 rows in ten groups held five subjects; someone looking
/// for "turn off emails" or "who can see my runs" had to know those lived under
/// "Preferences" and scroll about eight screens (issue #1374 finding 10). Each
/// page is one subject, and the You tab lists all five under its Preferences
/// group, the way web's settings nav does. Body metrics, which web carved out
/// of the same page, sits with the account under Profile on both.
enum PreferencesPage { display, recording, training, privacy, notifications }

/// Every row a Preferences page can show, by a stable id, on the page it is
/// on, in page order and then the order the page draws them.
///
/// The settings search lists these, a link elsewhere in the app names one,
/// and the row carries `anchor: row.name`, so opening a page with a row
/// focused lands on it (decisions § 2494, amended): scrolled into view,
/// highlighted and announced. The name is the id: never rename one, since a
/// link anywhere else names it. `preferences_search_index_test.dart` mounts
/// every page and fails when a row and this list disagree.
enum PreferencesRow {
  language(PreferencesPage.display),
  darkMode(PreferencesPage.display),
  useMiles(PreferencesPage.display),
  paceFormat(PreferencesPage.display),
  weightUnit(PreferencesPage.display),
  weekStart(PreferencesPage.display),
  disclosureLevel(PreferencesPage.display),
  progressCards(PreferencesPage.display),
  mapStyle(PreferencesPage.display),
  undoWindow(PreferencesPage.display),
  showCalories(PreferencesPage.display),
  showMascot(PreferencesPage.display),
  coachInMessages(PreferencesPage.display),
  showGym(PreferencesPage.display),
  showNutrition(PreferencesPage.display),
  defaultActivity(PreferencesPage.recording),
  keepRunPrimary(PreferencesPage.recording),
  keepScreenOn(PreferencesPage.recording),
  dimScreenWhileRecording(PreferencesPage.recording),
  advancedGps(PreferencesPage.recording),
  showRawTrack(PreferencesPage.recording),
  audioCues(PreferencesPage.recording),
  vibrationCues(PreferencesPage.recording),
  minimalVoiceCues(PreferencesPage.recording),
  turnByTurnCues(PreferencesPage.recording),
  splitInterval(PreferencesPage.recording),
  targetPace(PreferencesPage.recording),
  cueSplits(PreferencesPage.recording),
  cueStartFinish(PreferencesPage.recording),
  cueOffRoute(PreferencesPage.recording),
  cuePaceAlerts(PreferencesPage.recording),
  cueWorkoutSteps(PreferencesPage.recording),
  cueCutoffCatchUp(PreferencesPage.recording),
  cueMarkerTargets(PreferencesPage.recording),
  cuePhaseTransitions(PreferencesPage.recording),
  cueGuidedRun(PreferencesPage.recording),
  splitPaceMode(PreferencesPage.recording),
  weeklyGoal(PreferencesPage.training),
  dateOfBirth(PreferencesPage.training),
  restingHr(PreferencesPage.training),
  maxHr(PreferencesPage.training),
  hrMedicationAffected(PreferencesPage.training),
  hrMedicationSetMaxHr(PreferencesPage.training),
  hrZones(PreferencesPage.training),
  excludeGymFromReadiness(PreferencesPage.training),
  extraRecovery(PreferencesPage.training),
  carbsPerHour(PreferencesPage.training),
  fluidPerHour(PreferencesPage.training),
  coachPersonality(PreferencesPage.training),
  defaultRunPrivacy(PreferencesPage.privacy),
  stravaAutoShare(PreferencesPage.privacy),
  privateProfile(PreferencesPage.privacy),
  followRequests(PreferencesPage.privacy),
  discoverable(PreferencesPage.privacy),
  discoverableNearby(PreferencesPage.privacy),
  nearbyArea(PreferencesPage.privacy),
  readReceipts(PreferencesPage.privacy),
  messageRequests(PreferencesPage.privacy),
  privacyZones(PreferencesPage.privacy),
  errorReports(PreferencesPage.privacy),
  emailNotifications(PreferencesPage.notifications),
  pushNotifications(PreferencesPage.notifications),
  workoutReminder(PreferencesPage.notifications),
  raceStartingSoon(PreferencesPage.notifications),
  newDeviceAlerts(PreferencesPage.notifications),
  weeklyDigest(PreferencesPage.notifications),
  lifecycleEmails(PreferencesPage.notifications);

  const PreferencesRow(this.page);

  final PreferencesPage page;

  /// The rows [page] can show, in the order it draws them.
  static Iterable<PreferencesRow> on(PreferencesPage page) =>
      values.where((r) => r.page == page);
}
