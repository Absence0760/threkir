package com.runapp.watchwear.ui.store

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.test.core.app.ApplicationProvider
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.TimeSource
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import com.github.takahirom.roborazzi.RobolectricDeviceQualifiers
import com.github.takahirom.roborazzi.captureRoboImage
import com.runapp.watchwear.FinishedLap
import com.runapp.watchwear.FinishedSummary
import com.runapp.watchwear.GpsPoint
import com.runapp.watchwear.HeartRateAvailability
import com.runapp.watchwear.recording.DistanceUnit
import com.runapp.watchwear.recording.RouteMath
import com.runapp.watchwear.ui.DuskTheme
import com.runapp.watchwear.ui.PostRunScreen
import com.runapp.watchwear.ui.PreRunScreen
import com.runapp.watchwear.ui.RunningScreen
import com.runapp.watchwear.ui.TileSource
import com.runapp.watchwear.workout.PushedStep
import com.runapp.watchwear.workout.StepKind
import com.runapp.watchwear.workout.WorkoutView
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/// The Wear OS store screenshots, rendered from the real screens on the JVM
/// with seeded demo data and no account. `assets/store/wear/gen-wear-screenshots.sh`
/// records them and flattens each onto an opaque square for Play; a plain
/// `testDebugUnitTest` renders every screen and writes nothing.
///
/// The map draws without tiles: the debug tile source points at a loopback
/// tile server that is not running here, so the route and track are drawn on
/// the night background, which is also what a watch with no tile key shows.
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = RobolectricDeviceQualifiers.WearOSLargeRound)
class WearStoreScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun preRun() = capture("01-pre-run", VignettePosition.Top) {
        PreRunScreen(
            queuedCount = 0,
            queueUnreadable = false,
            rejectedCount = 0,
            syncBlockedBy = null,
            syncing = false,
            authed = true,
            authFault = null,
            online = true,
            batteryOptimised = false,
            batteryPercent = 86,
            activeRace = null,
            onToggleAttempt = {},
            pendingRecoveryDistance = null,
            preferredUnit = DistanceUnit.KM,
            activityType = "run",
            selectedRouteName = "Riverside loop",
            selectedRouteWaypoints = DemoRoute.loop,
            targetPaceSecPerKm = 300,
            todaysWorkout = null,
            followWorkout = false,
            onToggleWorkout = {},
            onCycleActivity = {},
            onCyclePace = {},
            onOpenRoutePicker = {},
            onStart = {},
            onSignIn = {},
            onSignOut = {},
            onFixBattery = {},
            onRecover = {},
            onDiscardRecovery = {},
            onSync = {},
            onDiscardRejected = {},
            onOpenCalibration = null,
            listState = rememberScalingLazyListState(initialCenterItemIndex = 0),
        )
    }

    @Test
    fun running() = capture("02-running") {
        Running(workoutView = null)
    }

    @Test
    fun workoutStep() = capture("03-workout-step") {
        Running(
            workoutView = WorkoutView(
                step = PushedStep(
                    kind = StepKind.Rep,
                    repIndex = 3,
                    repTotal = 6,
                    distanceM = 800,
                    durationS = null,
                    paceSPerKm = 270,
                    toleranceSPerKm = 10,
                ),
                index = 4,
                stepCount = 13,
                remainingM = 340.0,
                remainingS = null,
                paced = true,
            ),
        )
    }

    @Test
    fun postRun() = capture("04-post-run") {
        PostRunScreen(
            summary = FinishedSummary(
                distanceM = 10_020.0,
                durationS = 50 * 60 + 21,
                avgBpm = 148.0,
                lapCount = 10,
                activityType = "run",
                laps = DemoRoute.laps,
                trackLatLngs = DemoRoute.loop,
            ),
            bodyWeightKg = 68.0,
            showCalories = true,
            preferredUnit = DistanceUnit.KM,
            synced = true,
            syncing = false,
            syncFault = null,
            authed = true,
            onSync = {},
            onSignIn = {},
            onStartNext = {},
            onDiscard = {},
        )
    }

    @Composable
    private fun Running(workoutView: WorkoutView?) {
        val here = DemoRoute.loop[DemoRoute.RUNNER_AT]
        RunningScreen(
            elapsedMs = (32 * 60 + 14) * 1000L,
            distanceM = 6_420.0,
            paceSecPerKm = 301.0,
            preferredUnit = DistanceUnit.KM,
            bpm = 152,
            hrAvailability = HeartRateAvailability.Available,
            hrZoneCutoffs = listOf(114, 133, 152, 171, 190),
            steps = 5_880,
            lapCount = 6,
            paused = false,
            locationAvailable = true,
            noGpsYet = false,
            offRouteDistanceM = 4.0,
            routeRemainingM = 3_600.0,
            routeWaypoints = DemoRoute.loop,
            latestPoint = GpsPoint(lat = here.lat, lng = here.lng, ele = 12.0, epochMs = 0L, accuracyM = 4.0),
            fallbackLatLng = null,
            trackOverlayPoints = DemoRoute.loop.take(DemoRoute.RUNNER_AT + 1),
            ambient = false,
            raceRun = null,
            raceToStartM = null,
            workoutView = workoutView,
            onPause = {},
            onResume = {},
            onLap = {},
            onStop = {},
        )
    }

    /// The app's own chrome around a screen (`RunWatchApp`, which keeps the
    /// bottom edge clear on pre-run), with the clock pinned and tiles off so a
    /// re-run reproduces the same pixels.
    private fun capture(
        name: String,
        vignette: VignettePosition = VignettePosition.TopAndBottom,
        screen: @Composable () -> Unit,
    ) {
        disableTiles()
        compose.mainClock.autoAdvance = false
        compose.setContent {
            DuskTheme {
                Box(Modifier.fillMaxSize().background(Color.Black)) {
                    Scaffold(
                        timeText = { TimeText(timeSource = FixedTime) },
                        vignette = { Vignette(vignettePosition = vignette) },
                    ) {
                        screen()
                    }
                }
            }
        }
        compose.mainClock.advanceTimeBy(1_000)
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/store/$name.png")
    }

    /// The debug build points the tile source at a loopback tile server, so a
    /// workstation running one would paint its tiles into the screenshot and
    /// one that is not would paint none. Off, the map is what a watch with no
    /// tile key draws: route and track on the night background, every run.
    private fun disableTiles() {
        val source = TileSource.get(ApplicationProvider.getApplicationContext())
        TileSource::class.java.getDeclaredField("enabled").apply { isAccessible = true }.setBoolean(source, false)
        check(!source.enabled) { "the tile source is still enabled" }
    }

    private object FixedTime : TimeSource {
        override val currentTime: String
            @Composable get() = "7:30"
    }
}

/// A made-up 10 km loop: a rounded lobe shape, not any real place, so the
/// screenshots carry no one's location.
private object DemoRoute {
    private const val CENTRE_LAT = 45.0
    private const val CENTRE_LNG = 7.0

    /// Where the runner is: the inside of a bend (sin 3t = -1), about 6 km in,
    /// so the street-zoom map shows a curve rather than a straight line.
    const val RUNNER_AT = 140

    val loop: List<RouteMath.LatLng> = (0..240).map { i ->
        val t = 2 * PI * i / 240
        val r = 1.0 + 0.28 * sin(3 * t) + 0.12 * cos(5 * t)
        RouteMath.LatLng(
            CENTRE_LAT + 0.0105 * r * sin(t),
            CENTRE_LNG + 0.0150 * r * cos(t),
        )
    }

    val laps: List<FinishedLap> = (1..10).map { n ->
        val split = 296 + (n * 7) % 11
        FinishedLap(
            number = n,
            splitSeconds = split,
            splitDistanceM = 1_000.0,
            cumulativeSeconds = (1..n).sumOf { 296 + (it * 7) % 11 },
            cumulativeDistanceM = n * 1_000.0,
        )
    }
}
