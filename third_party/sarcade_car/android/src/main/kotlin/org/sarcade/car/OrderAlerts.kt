package org.sarcade.car

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.car.app.CarContext
import androidx.car.app.model.Action
import androidx.car.app.model.Alert
import androidx.car.app.model.CarText
import androidx.car.app.notification.CarAppExtender
import androidx.car.app.notification.CarNotificationManager
import androidx.car.app.notification.CarPendingIntent
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Alert of a move order in the car (lot 20, card « Android Auto : ordres de
 * déplacement peu utilisables… », choices 1, 3 and 6): besides the message
 * read aloud, the new order comes with two buttons, « Y aller » (Google
 * Maps or Waze guided towards the point) and « Voir » (the order screen).
 * The name of the point comes first, before « Ordre de déplacement », so
 * that it stays readable.
 *
 * - SARCADE shown in the car (car API level 5 and more): alert of the Car
 *   App Library over the screen;
 * - otherwise: notification of the car (CarAppExtender) with the same two
 *   buttons.
 *
 * Each order is announced once, even after a restart (identifiers kept in
 * the preferences of the car screen).
 */
internal object OrderAlerts {
    const val ACTION_VIEW = "org.sarcade.car.ORDER_VIEW"
    const val EXTRA_ID = "order_id"
    const val CHANNEL = "sarcade_car_orders"
    /** Car API level of the alerts (AppManager.showAlert). */
    const val ALERT_LEVEL = 5
    const val ALERT_MS = 30_000L
    private const val PREFS = "sarcade_car_screen"
    private const val KEY = "alerted_orders"
    private const val KEPT = 100

    /** Orders to announce: sent (not yet answered) and not announced yet. */
    fun fresh(snap: Snapshot, seen: Set<String>): List<JSONObject> =
        snap.items("orders").filter { it.optString("status") == "sent" && it.optString("id") !in seen }

    /** Takes the orders to announce and remembers them. The first time
     *  ever, the orders already there are only remembered (no burst of
     *  old alerts after the update). */
    fun take(context: Context, snap: Snapshot): List<JSONObject> {
        if (!snap.ready) return emptyList()
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY, null)
        val seen = raw?.let { r -> runCatching { JSONArray(r) }.getOrNull() }
            ?.let { a -> (0 until a.length()).map { a.optString(it) } }
            ?: emptyList()
        val all = snap.items("orders").map { it.optString("id") }
        val out = if (raw == null) emptyList() else fresh(snap, seen.toSet())
        val kept = (seen + all).distinct().takeLast(KEPT)
        if (raw == null || out.isNotEmpty() || kept.size != seen.size) {
            prefs.edit().putString(KEY, JSONArray(kept).toString()).apply()
        }
        return out
    }

    /** « Ordre de déplacement · PCO · 3 km NO » (choice 6: after the name). */
    fun text(snap: Snapshot, o: JSONObject): String =
        listOf(snap.label("orderAlert"), o.optString("from"), o.optString("away"))
            .filter { it.isNotBlank() }.joinToString(" · ")

    fun alertId(o: JSONObject): Int = o.optString("id").hashCode() and 0x7fffffff

    /** The alert over the SARCADE screen: name of the point, then the
     *  order; « Y aller » and « Voir ». */
    fun alert(context: CarContext, snap: Snapshot, o: JSONObject, view: () -> Unit): Alert {
        val go = Action.Builder().setTitle(snap.label("go"))
            .setIcon(CarUi.icon(context, R.drawable.sarcade_car_directions))
            .setOnClickListener { MainScreen.goToOrder(context, snap, o) }
            .build()
        val see = Action.Builder().setTitle(snap.label("view"))
            .setIcon(CarUi.icon(context, R.drawable.sarcade_car_visibility))
            .setOnClickListener { view() }
            .build()
        return Alert.Builder(alertId(o), CarText.create(o.optString("title")), ALERT_MS)
            .setSubtitle(CarText.create(text(snap, o)))
            .setIcon(CarUi.icon(context, R.drawable.sarcade_car_flag))
            .addAction(go)
            .addAction(see)
            .build()
    }

    /** Notification of the car with « Y aller » and « Voir », when the alert
     *  cannot be shown (SARCADE not on the car screen, older car). */
    fun notify(context: CarContext, snap: Snapshot, o: JSONObject) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val id = alertId(o)
        val title = o.optString("title")
        val text = text(snap, o)
        val see = CarPendingIntent.getCarApp(
            context, id,
            Intent(ACTION_VIEW).setComponent(ComponentName(context, SarcadeCarAppService::class.java))
                .putExtra(EXTRA_ID, o.optString("id")),
            0,
        )
        val go = CarPendingIntent.getCarApp(context, id + 1, CarUi.navigateIntent(o.optDouble("lat"), o.optDouble("lon")), 0)
        val manager = CarNotificationManager.from(context)
        try {
            manager.createNotificationChannel(
                NotificationChannelCompat.Builder(CHANNEL, NotificationManagerCompat.IMPORTANCE_HIGH)
                    .setName(snap.label("orderAlert")).build()
            )
            val builder = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.sarcade_car_flag)
                .setContentTitle(title)
                .setContentText(text)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .extend(
                    CarAppExtender.Builder()
                        .setContentTitle(title)
                        .setContentText(text)
                        .setSmallIcon(R.drawable.sarcade_car_flag)
                        .setContentIntent(see)
                        .setImportance(NotificationManagerCompat.IMPORTANCE_HIGH)
                        .addAction(R.drawable.sarcade_car_directions, snap.label("go"), go)
                        .addAction(R.drawable.sarcade_car_visibility, snap.label("view"), see)
                        .build()
                )
            manager.notify(id, builder)
        } catch (e: Exception) {
            // No notification: the message read aloud and the Ordres tab remain.
        }
    }
}
