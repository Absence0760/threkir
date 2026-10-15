package com.runapp.watchwear

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.runapp.watchwear.recording.ESTIMATOR_ACCURACY_CAP_M
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/// [accuracyM] / [speedMps] / [speedAccuracyMps] / [bearingDeg] are null when
/// the platform did not report them. [elapsedRealtimeMs] is the fix's own
/// stamp on `SystemClock.elapsedRealtime`'s clock, which is what the distance
/// estimator integrates over: `epochMs` is a wall clock that can step on an
/// NTP sync, and the receive time is shared by every fix in a batched result.
data class GpsPoint(
    val lat: Double,
    val lng: Double,
    val ele: Double?,
    val epochMs: Long,
    val accuracyM: Double? = null,
    val speedMps: Double? = null,
    val speedAccuracyMps: Double? = null,
    val bearingDeg: Double? = null,
    val elapsedRealtimeMs: Long? = null,
)

internal fun gpsPointFrom(loc: Location): GpsPoint = GpsPoint(
    lat = loc.latitude,
    lng = loc.longitude,
    ele = if (loc.hasAltitude()) loc.altitude else null,
    epochMs = loc.time,
    accuracyM = if (loc.hasAccuracy()) loc.accuracy.toDouble() else null,
    speedMps = if (loc.hasSpeed()) loc.speed.toDouble() else null,
    speedAccuracyMps = if (loc.hasSpeedAccuracy()) loc.speedAccuracyMetersPerSecond.toDouble() else null,
    bearingDeg = if (loc.hasBearing()) loc.bearing.toDouble() else null,
    elapsedRealtimeMs = loc.elapsedRealtimeNanos.takeIf { it > 0L }?.let { it / 1_000_000L },
)

/// Shape of each emission from [GpsRecorder.stream]. Either a new GPS
/// point arrived, or the underlying provider flipped availability (GPS
/// signal lost / regained / permission revoked).
sealed class GpsEvent {
    data class Point(val point: GpsPoint) : GpsEvent()
    data class Availability(val available: Boolean) : GpsEvent()
}

class GpsRecorder(context: Context) {
    private val client: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)
    private val locationManager: LocationManager? =
        context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    /// One-shot read of the device's last cached location. Returns
    /// null if no fix is available or the call fails. Used by the
    /// countdown overlay to warm-fetch tiles before recording starts
    /// — letting tile downloads ride the 3-second countdown instead
    /// of stalling the running screen's first frame on HTTP latency.
    @SuppressLint("MissingPermission")
    suspend fun lastLocation(): GpsPoint? = suspendCancellableCoroutine { cont ->
        try {
            client.lastLocation
                .addOnSuccessListener { loc: Location? ->
                    cont.resume(loc?.let {
                        GpsPoint(
                            lat = it.latitude,
                            lng = it.longitude,
                            ele = if (it.hasAltitude()) it.altitude else null,
                            epochMs = it.time,
                        )
                    })
                }
                .addOnFailureListener { cont.resume(null) }
                .addOnCanceledListener { cont.resume(null) }
        } catch (_: Throwable) {
            cont.resume(null)
        }
    }

    /// Open a position stream at high accuracy with a 1-second update target.
    /// Emits [GpsEvent.Availability] when the provider's usable-signal state
    /// changes, so the caller can surface "GPS lost" to the user instead
    /// of showing stale distance silently.
    @SuppressLint("MissingPermission")
    fun stream(): Flow<GpsEvent> = callbackFlow {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1_000L)
            .setMinUpdateIntervalMillis(500L)
            .build()

        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (loc: Location in result.locations) {
                    if (!loc.hasAccuracy() || loc.accuracy > ESTIMATOR_ACCURACY_CAP_M) continue
                    trySend(GpsEvent.Point(gpsPointFrom(loc)))
                }
            }

            override fun onLocationAvailability(availability: LocationAvailability) {
                trySend(GpsEvent.Availability(availability.isLocationAvailable))
            }
        }

        // Pass the main Looper explicitly. `null` means "use the calling
        // thread's Looper", which throws when this Flow is collected on a
        // background dispatcher (e.g. the foreground service's scope).
        client.requestLocationUpdates(request, cb, Looper.getMainLooper())
        awaitClose { client.removeLocationUpdates(cb) }
    }

    /// The satellite receiver's own fixes (`GPS_PROVIDER`) at 1 Hz, every fix
    /// emitted ungated so the caller's source arbitration can tell a usable
    /// fix from a canopy one. Emits only [GpsEvent.Point]. The flow ends
    /// when the watch has no receiver, the provider is or becomes disabled,
    /// or the request is refused, so the caller reads a finished flow as "no
    /// receiver right now" and fused carries the run.
    @SuppressLint("MissingPermission")
    fun gnssStream(): Flow<GpsEvent> = callbackFlow {
        val lm = locationManager
        val available = lm != null && runCatching {
            LocationManager.GPS_PROVIDER in lm.allProviders &&
                lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
        }.getOrDefault(false)
        if (lm == null || !available) {
            close()
            return@callbackFlow
        }

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                trySend(GpsEvent.Point(gpsPointFrom(location)))
            }

            override fun onProviderEnabled(provider: String) = Unit

            override fun onProviderDisabled(provider: String) {
                close()
            }
        }

        try {
            lm.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1_000L,
                0f,
                listener,
                Looper.getMainLooper(),
            )
        } catch (e: Exception) {
            android.util.Log.w("GpsRecorder", "receiver request refused", e)
            close()
            return@callbackFlow
        }
        awaitClose { lm.removeUpdates(listener) }
    }
}
