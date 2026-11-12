package com.threkir.app

import java.time.LocalDate
import org.json.JSONException
import org.json.JSONObject

/// What the today's-workout widget shows for one snapshot on one local date.
/// Every string comes from the snapshot, already translated and formatted on
/// the Dart side (`lib/today_widget.dart`); a null one means the widget's own
/// fallback resource, which only happens when there is no readable snapshot.
data class TodayWidgetView(
    val state: State,
    val header: String?,
    val title: String?,
    val detail: String?,
    /// "Done" / "Skipped" beside a session that is no longer to do.
    val badge: String?,
    /// The deep link a tap opens; null opens the app with none.
    val link: String?,
) {
    enum class State { WORKOUT, DONE, SKIPPED, REST, NONE, NO_PLAN, STALE }
}

const val TODAY_WIDGET_SNAPSHOT_VERSION = 1

private const val LINK_PLANS = "com.threkir.app://plans"

private val unreadable = TodayWidgetView(
    state = TodayWidgetView.State.STALE,
    header = null,
    title = null,
    detail = null,
    badge = null,
    link = null,
)

/// Pick what to draw from [snapshotJson] on local date [today]: the day entry
/// whose `date` is [today]. Pure, so the whole table runs on a host JVM
/// against `fixtures/today_widget_snapshot.json`.
///
/// No `plan_id` is the no-plan state. A plan with no entry for today (the
/// snapshot is over a week old, or the clock moved) is stale. A version other
/// than [TODAY_WIDGET_SNAPSHOT_VERSION], or text that is not a snapshot, is
/// stale with nothing read from it: never guess at a shape.
fun selectTodayWidgetView(snapshotJson: String?, today: LocalDate): TodayWidgetView {
    if (snapshotJson.isNullOrBlank()) return unreadable
    return try {
        selectFrom(JSONObject(snapshotJson), today.toString())
    } catch (e: JSONException) {
        unreadable
    }
}

private fun selectFrom(root: JSONObject, today: String): TodayWidgetView {
    if (root.optInt("v", -1) != TODAY_WIDGET_SNAPSHOT_VERSION) return unreadable
    val labels = root.getJSONObject("labels")
    val header = labels.getString("header")
    val planId = root.optString("plan_id").takeIf { it.isNotEmpty() }
        ?: return TodayWidgetView(
            state = TodayWidgetView.State.NO_PLAN,
            header = header,
            title = labels.getString("no_plan"),
            detail = labels.getString("no_plan_action"),
            badge = null,
            link = LINK_PLANS,
        )
    val planLink = "$LINK_PLANS/$planId"
    val days = root.getJSONArray("days")
    val day = (0 until days.length())
        .map { days.getJSONObject(it) }
        .firstOrNull { it.optString("date") == today }
        ?: return TodayWidgetView(
            state = TodayWidgetView.State.STALE,
            header = header,
            title = labels.getString("stale"),
            detail = "",
            badge = null,
            link = planLink,
        )
    val title = day.optString("title")
    val detail = day.optString("detail")
    val workoutId = day.optString("plan_workout_id").takeIf { it.isNotEmpty() }
    val workoutLink = workoutId?.let { "$planLink/workouts/$it" } ?: planLink
    return when (day.optString("state")) {
        "workout" -> TodayWidgetView(TodayWidgetView.State.WORKOUT, header, title, detail, null, workoutLink)
        "done" -> TodayWidgetView(TodayWidgetView.State.DONE, header, title, detail, labels.getString("done"), workoutLink)
        "skipped" -> TodayWidgetView(TodayWidgetView.State.SKIPPED, header, title, detail, labels.getString("skipped"), workoutLink)
        "rest" -> TodayWidgetView(
            TodayWidgetView.State.REST, header, title.ifEmpty { labels.getString("rest_day") }, "", null, planLink,
        )
        "none" -> TodayWidgetView(
            TodayWidgetView.State.NONE, header, labels.getString("nothing_scheduled"), "", null, planLink,
        )
        else -> unreadable
    }
}

/// Pure arg parser for `run_app/home_widget` `update`: a missing or blank
/// `snapshot_json` is refused rather than stored.
internal fun parseHomeWidgetUpdateArgs(args: Map<String, Any?>?): String? {
    val json = args?.get("snapshot_json") as? String ?: return null
    return json.takeIf { it.isNotBlank() }
}
