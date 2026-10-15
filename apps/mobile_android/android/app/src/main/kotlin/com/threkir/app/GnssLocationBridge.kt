package com.threkir.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/// The satellite receiver's own fixes (`GPS_PROVIDER`), for the run recorder.
/// geolocator only reaches `LocationManager` through `forceLocationManager`,
/// which on Android 12+ picks `FUSED_PROVIDER`, and the fused provider's
/// speed and position both blend in non-GNSS estimates (issue #1106). Dart
/// side: `lib/gnss_location_bridge.dart` over `run_app/gnss_location`.
///
/// The recorder keeps geolocator's fused stream open alongside this one: it
/// carries the location foreground service that keeps the process recording
/// in the background, and it is the fallback while the receiver is silent.
class GnssLocationBridge(private val context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler {

    private val locationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var listener: LocationListener? = null

    init {
        EventChannel(messenger, "run_app/gnss_location").setStreamHandler(this)
    }

    @SuppressLint("MissingPermission")
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        val fine = context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)
        if (fine != PackageManager.PERMISSION_GRANTED) {
            events.error("permission", "fine location not granted", null)
            return
        }
        if (!locationManager.allProviders.contains(LocationManager.GPS_PROVIDER) ||
            !locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        ) {
            events.error("unavailable", "GPS_PROVIDER absent or disabled", null)
            return
        }
        val intervalMs = (arguments as? Number)?.toLong() ?: 1000L
        val l = LocationListener { location -> events.success(toMap(location)) }
        listener = l
        try {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, intervalMs, 0f, l, Looper.getMainLooper()
            )
        } catch (e: Exception) {
            listener = null
            events.error("unavailable", e.message, null)
        }
    }

    override fun onCancel(arguments: Any?) = stop()

    private fun stop() {
        listener?.let { locationManager.removeUpdates(it) }
        listener = null
    }

    // An absent reading is omitted rather than sent as 0, so the Dart side
    // can tell "not measured" from a measured zero.
    private fun toMap(l: Location): Map<String, Any> {
        val m = mutableMapOf<String, Any>(
            "lat" to l.latitude,
            "lng" to l.longitude,
            "timeMs" to l.time,
            "mocked" to l.isFromMockProvider,
        )
        if (l.hasAccuracy()) m["accuracy"] = l.accuracy.toDouble()
        if (l.hasAltitude()) m["altitude"] = l.altitude
        if (l.hasVerticalAccuracy()) m["altitudeAccuracy"] = l.verticalAccuracyMeters.toDouble()
        if (l.hasSpeed()) m["speed"] = l.speed.toDouble()
        if (l.hasSpeedAccuracy()) m["speedAccuracy"] = l.speedAccuracyMetersPerSecond.toDouble()
        if (l.hasBearing()) m["bearing"] = l.bearing.toDouble()
        if (l.hasBearingAccuracy()) m["bearingAccuracy"] = l.bearingAccuracyDegrees.toDouble()
        return m
    }
}
