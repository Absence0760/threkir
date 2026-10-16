package com.threkir.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/// The phone barometer as an altitude, for the run recorder's elevation, over
/// `run_app/barometer`. Dart side: `lib/barometer_bridge.dart`.
///
/// The altitude is `SensorManager.getAltitude` against the standard
/// atmosphere, so its level is arbitrary and drifts with the weather; only its
/// shape is used, and the recorder levels it against GPS altitude
/// (`BaroAltitudeAnchor`). Readings arrive every ~200 ms and are sent as the
/// mean of each second, which averages the sensor's own noise.
class BarometerBridge(context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler {

    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val channel = EventChannel(messenger, "run_app/barometer")
    private var listener: SensorEventListener? = null

    init {
        channel.setStreamHandler(this)
    }

    /// The engine going away does not guarantee an onCancel, and a registered
    /// listener keeps the sensor powered.
    fun dispose() {
        stop()
        channel.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_PRESSURE)
        if (sensor == null) {
            events.error("unavailable", "no pressure sensor", null)
            return
        }
        val l = object : SensorEventListener {
            private var windowStartNs = 0L
            private var sum = 0.0
            private var count = 0

            override fun onSensorChanged(event: SensorEvent) {
                val hPa = event.values.firstOrNull() ?: return
                if (!hPa.isFinite() || hPa <= 0f) return
                if (count == 0) windowStartNs = event.timestamp
                sum += SensorManager.getAltitude(
                    SensorManager.PRESSURE_STANDARD_ATMOSPHERE, hPa
                ).toDouble()
                count++
                if (event.timestamp - windowStartNs >= 1_000_000_000L) {
                    events.success(mapOf("altitudeM" to sum / count))
                    sum = 0.0
                    count = 0
                }
            }

            override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) = Unit
        }
        listener = l
        if (!sensorManager.registerListener(l, sensor, SensorManager.SENSOR_DELAY_NORMAL)) {
            listener = null
            events.error("unavailable", "pressure sensor refused the listener", null)
        }
    }

    override fun onCancel(arguments: Any?) = stop()

    private fun stop() {
        listener?.let { sensorManager.unregisterListener(it) }
        listener = null
    }
}
