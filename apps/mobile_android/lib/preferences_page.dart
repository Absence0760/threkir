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
