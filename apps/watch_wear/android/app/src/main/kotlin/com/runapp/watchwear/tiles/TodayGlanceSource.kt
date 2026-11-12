package com.runapp.watchwear.tiles

import android.content.Context
import android.util.Log
import com.runapp.watchwear.WorkoutBridge
import com.runapp.watchwear.complications.LastRunStore
import java.time.ZoneId
import kotlinx.coroutines.withTimeoutOrNull

private const val TAG = "TodayGlance"

/// How long a glance waits on the Data Layer before it gives up and shows its
/// idle content. The read is local (the item lives in the watch's own graph),
/// so this only bounds a Play services that is starting up or wedged; a tile
/// or complication request must answer, not hang.
private const val READ_TIMEOUT_MS = 3_000L

/// Read today's workout for the tile and the complication: the phone's last
/// push from the watch's own Data Layer graph and the last run this watch
/// recorded, both local. Every failure reads as "no workout today", so a
/// glance degrades to its idle content and never to an error.
internal suspend fun loadTodayGlance(context: Context, nowEpochMs: Long): TodayGlance? {
    val zone = ZoneId.systemDefault()
    val push = try {
        withTimeoutOrNull(READ_TIMEOUT_MS) { WorkoutBridge(context).current() }?.push
    } catch (e: Throwable) {
        Log.w(TAG, "today's workout unreadable; showing the idle glance", e)
        return null
    }
    val lastRun = try {
        LastRunStore(context).current()
    } catch (e: Throwable) {
        Log.w(TAG, "last run unreadable; offering today's workout without it", e)
        null
    }
    return todayGlance(push, lastRun, localDate(nowEpochMs, zone), zone)
}
