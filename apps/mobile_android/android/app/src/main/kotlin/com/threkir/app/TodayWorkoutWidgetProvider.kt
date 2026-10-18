package com.threkir.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/// The today's-workout home-screen widget. It draws the entry for the
/// device's local today out of the week-long snapshot the app last wrote
/// (`run_app/home_widget`, [HomeWidgetBridge]); which day and which state is
/// [selectTodayWidgetView], a pure function under host tests.
///
/// The snapshot covers seven days, so the widget rolls over at local midnight
/// without the app: an inexact alarm at the next midnight, re-armed on every
/// draw, plus the clock and zone broadcasts and `updatePeriodMillis` as a
/// backstop for a missed alarm (reboot clears alarms).
///
/// An L4 surface: a failure to draw is logged and leaves the last frame.
class TodayWorkoutWidgetProvider : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_MIDNIGHT,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED -> redrawAll(context)
            else -> super.onReceive(context, intent)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        draw(context, manager, ids)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        draw(context, manager, intArrayOf(id))
    }

    override fun onDisabled(context: Context) {
        try {
            alarmManager(context)?.cancel(midnightIntent(context))
        } catch (e: Exception) {
            Log.w(TAG, "midnight alarm not cancelled", e)
        }
    }

    companion object {
        private const val TAG = "TodayWorkoutWidget"
        private const val PREFS = "threkir_home_widget"
        private const val KEY_SNAPSHOT = "snapshot_json"
        private const val ACTION_MIDNIGHT = "com.threkir.app.widget.TODAY_MIDNIGHT"

        fun store(context: Context, json: String?) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            if (json == null) prefs.remove(KEY_SNAPSHOT) else prefs.putString(KEY_SNAPSHOT, json)
            prefs.apply()
        }

        fun redrawAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, TodayWorkoutWidgetProvider::class.java),
            )
            draw(context, manager, ids)
        }

        private fun draw(context: Context, manager: AppWidgetManager, ids: IntArray) {
            if (ids.isEmpty()) return
            try {
                val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getString(KEY_SNAPSHOT, null)
                val view = selectTodayWidgetView(json, LocalDate.now())
                for (id in ids) {
                    manager.updateAppWidget(id, remoteViews(context, manager, id, view))
                }
            } catch (e: Exception) {
                Log.w(TAG, "widget not drawn", e)
            }
            armMidnight(context)
        }

        private fun remoteViews(
            context: Context,
            manager: AppWidgetManager,
            id: Int,
            view: TodayWidgetView,
        ): RemoteViews {
            val small = fill(context, R.layout.widget_today_small, view)
            val full = fill(context, R.layout.widget_today, view)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                return RemoteViews(
                    mapOf(
                        SizeF(110f, 40f) to small,
                        SizeF(110f, SMALL_MAX_HEIGHT_DP.toFloat()) to full,
                    ),
                )
            }
            val minHeight = manager.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, SMALL_MAX_HEIGHT_DP)
            return if (minHeight < SMALL_MAX_HEIGHT_DP) small else full
        }

        /// Below this height the widget is one row (a 2x1 cell).
        private const val SMALL_MAX_HEIGHT_DP = 100

        private fun fill(context: Context, layout: Int, view: TodayWidgetView): RemoteViews {
            val rv = RemoteViews(context.packageName, layout)
            val header = view.header ?: context.getString(R.string.widget_today_header_fallback)
            val title = view.title ?: context.getString(R.string.widget_today_no_data)
            rv.setTextViewText(R.id.widget_today_header, header)
            rv.setTextViewText(R.id.widget_today_title, title)
            val detail = view.detail.orEmpty()
            rv.setTextViewText(R.id.widget_today_detail, detail)
            rv.setViewVisibility(
                R.id.widget_today_detail,
                if (detail.isEmpty()) View.GONE else View.VISIBLE,
            )
            val badge = view.badge
            rv.setTextViewText(R.id.widget_today_badge, badge.orEmpty())
            rv.setViewVisibility(
                R.id.widget_today_badge,
                if (badge == null) View.GONE else View.VISIBLE,
            )
            rv.setContentDescription(
                R.id.widget_today_root,
                listOfNotNull(header, title, badge, detail.ifEmpty { null }).joinToString(", "),
            )
            rv.setOnClickPendingIntent(R.id.widget_today_root, tapIntent(context, view.link))
            return rv
        }

        /// Opens MainActivity explicitly with the deep link as its data, which
        /// `app_links` hands to `EntityLinkService`. A distinct request code
        /// per link keeps two widgets showing different days from sharing one
        /// PendingIntent.
        private fun tapIntent(context: Context, link: String?): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                if (link != null) {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse(link)
                } else {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                }
            }
            return PendingIntent.getActivity(
                context,
                link?.hashCode() ?: 0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun midnightIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, TodayWorkoutWidgetProvider::class.java).setAction(ACTION_MIDNIGHT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun alarmManager(context: Context): AlarmManager? =
            context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

        /// An inexact, non-waking alarm: the widget only needs the new day
        /// drawn by the time someone looks, so no exact-alarm permission and
        /// no wakeup. Replaces any earlier one (same PendingIntent).
        private fun armMidnight(context: Context) {
            try {
                val at = nextLocalMidnightMs(ZonedDateTime.now(ZoneId.systemDefault()))
                alarmManager(context)?.set(AlarmManager.RTC, at, midnightIntent(context))
            } catch (e: Exception) {
                Log.w(TAG, "midnight alarm not armed", e)
            }
        }
    }
}

/// The epoch millis of the first instant of the local day after [now], a
/// minute late so the redraw lands on the new date whatever the alarm's
/// rounding. `atStartOfDay` keeps a zone whose midnight is skipped by DST.
internal fun nextLocalMidnightMs(now: ZonedDateTime): Long =
    now.toLocalDate().plusDays(1).atStartOfDay(now.zone)
        .plusMinutes(1).toInstant().toEpochMilli()
