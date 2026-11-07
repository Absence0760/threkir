/// The one rule for when a pace over a stretch of running means anything.
///
/// A pace read over too little ground or too little time is noise: a standing
/// start plus GPS lag covered 19 m in the first 15 s of a 9:20 /mi block,
/// which read 20:49 /mi. Both floors are required, because a GPS catch-up
/// burst can cover 50 m in a couple of seconds. A rolling window built on this
/// trims only while it keeps both, so a cyclist past 10 m/s, who covers
/// 200 m in under 20 s, still gets a pace. The live Pace
/// tile (the recorder's rolling window), the Avg pace tile, the workout band's
/// delta, its adherence colour and the step drift cue all ask this one
/// question, so none of them can show a pace while another still says it is
/// too early. The wrist ports (Wear OS `LivePaceWindow` + `WorkoutRunner.kt`,
/// watchOS `PaceWindow` + `WatchWorkoutRunner.swift`) hold the same pair.
const double kPaceReadyMinMetres = 50;
const int kPaceReadyMinSeconds = 20;

bool paceIsReady(double metres, num seconds) =>
    metres >= kPaceReadyMinMetres && seconds >= kPaceReadyMinSeconds;

/// Average pace in s/km over [metres] and [seconds], or null until
/// [paceIsReady]. The live Avg pace and Avg speed tiles read this.
double? readyAveragePaceSecPerKm(double metres, num seconds) =>
    paceIsReady(metres, seconds) ? seconds / (metres / 1000) : null;
