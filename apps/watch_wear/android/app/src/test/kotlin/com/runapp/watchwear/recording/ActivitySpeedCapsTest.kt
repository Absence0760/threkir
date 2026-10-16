package com.runapp.watchwear.recording

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// `fixtures/activity_speed_caps.json` is the phone's `ActivityType.maxSpeedMps`,
/// the one table every port's tests read.
class ActivitySpeedCapsTest {

    private val fixture = Json.parseToJsonElement(
        File("../../../../fixtures/activity_speed_caps.json").readText(),
    ).jsonObject

    private val caps: Map<String, Double> =
        fixture["capsMps"]!!.jsonObject.mapValues { it.value.jsonPrimitive.double }

    @Test
    fun `every activity cap matches the shared fixture`() {
        assertTrue("fixture has no caps", caps.isNotEmpty())
        for ((activity, cap) in caps) {
            assertEquals(activity, cap, GpsDistanceEstimator.maxSpeedMpsFor(activity), 0.0)
        }
    }

    @Test
    fun `an unknown activity takes the fixture fallback cap`() {
        val fallback = caps[fixture["unknownActivityCap"]!!.jsonPrimitive.content]
        assertNotNull(fallback)
        assertEquals(fallback!!, GpsDistanceEstimator.maxSpeedMpsFor("something-new"), 0.0)
        assertEquals(fallback, GpsDistanceEstimator.maxSpeedMpsFor(""), 0.0)
    }
}
