package com.runapp.watchwear

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import com.runapp.watchwear.workout.WorkoutPush
import com.runapp.watchwear.workout.parseWorkoutPush
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await

/// One delivery of today's workout: the decoded push, the JSON text it came
/// from (handed to the recording service verbatim, which decodes it again
/// rather than trusting a second encoder), and the phone's stamp.
data class WorkoutPushDelivery(
    val push: WorkoutPush,
    val workoutJson: String,
    val updatedAtMs: Long,
)

/// Listens at `/todays_workout` for the planned workout the paired phone
/// pushes (`WearWorkoutBridge` on the phone, fed by
/// `apps/mobile_android/lib/watch_workout_push.dart`). Sibling of
/// [RoutesBridge].
///
/// No DataStore copy, unlike the routes: the Data Layer keeps the item in the
/// watch's own local graph, so [current] answers on a cold start with no
/// phone in range, and the item is replaced on every push rather than
/// accumulated. A watch that has never paired a phone simply has no item.
class WorkoutBridge(context: Context) {
    private val dataClient: DataClient = Wearable.getDataClient(context)

    val events: Flow<WorkoutPushDelivery> = callbackFlow {
        val listener = DataClient.OnDataChangedListener { evts ->
            for (event in evts) {
                if (event.dataItem.uri.path != PATH) continue
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val dm = DataMapItem.fromDataItem(event.dataItem).dataMap
                val raw = dm.getString("workout_json") ?: continue
                trySend(WorkoutPushDelivery(parseWorkoutPush(raw), raw, dm.getLong("updated_at_ms")))
            }
        }
        dataClient.addListener(listener)
        awaitClose { dataClient.removeListener(listener) }
    }

    suspend fun current(): WorkoutPushDelivery? {
        val uri = Uri.Builder().scheme("wear").path(PATH).build()
        val buffer = dataClient.getDataItems(uri).await()
        return try {
            buffer.firstOrNull()?.let { item ->
                val dm = DataMapItem.fromDataItem(item).dataMap
                val raw = dm.getString("workout_json") ?: return@let null
                WorkoutPushDelivery(parseWorkoutPush(raw), raw, dm.getLong("updated_at_ms"))
            }
        } finally {
            buffer.release()
        }
    }

    companion object {
        const val PATH = "/todays_workout"
    }
}
