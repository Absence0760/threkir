package com.runapp.watchwear.tiles

import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService
import com.runapp.watchwear.WorkoutBridge
import com.runapp.watchwear.complications.ActiveRunComplicationService

/// Wakes on a new `/todays_workout` push from the phone and asks the tile and
/// the complication to re-read it.
///
/// `WorkoutBridge`'s live listener only exists while the app's view model
/// does, and a runner who glances at the tile has usually not opened the app
/// today. Without this the tile would keep yesterday's rendering until the
/// host happened to re-request it. The manifest filters the wake-up to the
/// one path, so no other Data Layer traffic starts the process.
class TodaysWorkoutListenerService : WearableListenerService() {

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val relevant = dataEvents.any { it.dataItem.uri.path == WorkoutBridge.PATH }
        if (!relevant) return
        ActiveRunTileService.requestUpdate(this)
        ActiveRunComplicationService.requestUpdate(this)
    }
}
