/// Hard cap on `await`s that hit Supabase / an Edge Function. When the
/// backend is unreachable, supabase-dart's HTTP calls don't resolve on
/// their own for minutes — the timeout converts that into a visible
/// error state the user can retry.
const kBackendLoadTimeout = Duration(seconds: 15);

/// How long a save that has already landed on the phone waits for its sync
/// before confirming. Past it the confirmation says the save is on the phone
/// and will sync, and the drain carries on behind it.
const kLocalSaveSyncWait = Duration(seconds: 5);
