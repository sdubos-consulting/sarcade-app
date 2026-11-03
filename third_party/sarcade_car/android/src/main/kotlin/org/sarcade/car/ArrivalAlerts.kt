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
import androidx.car.app.model.AlertCallback
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
import java.text.Normalizer
import java.util.Locale

/**
 * Arrival detected near the point of an order (lot 24, card « Android
 * Auto : arrivée détectée près du point d'un ordre », choices 1 to 4):
 * within 100 m of the point of an accepted order (« near », computed by the
 * application), « Vous êtes arrivé à … Signaler l'arrivée ? » with « Oui »
 * and « Plus tard »; the question is also read aloud and the answer may be
 * spoken; « Oui » sets the order to « Arrivé » and the status to « Sur
 * place » (application, action « arrival »). One alert per order, even
 * when driving around the point or after a restart (identifiers kept in
 * the preferences of the car screen, as [OrderAlerts]).
 */
internal object ArrivalAlerts {
    const val ACTION_YES = "org.sarcade.car.ARRIVAL_YES"
    const val CHANNEL = "sarcade_car_arrivals"
    private const val PREFS = "sarcade_car_screen"
    private const val KEY = "alerted_arrivals"
    private const val KEPT = 100

    /** Orders near their point, accepted, not asked yet. */
    fun fresh(snap: Snapshot, seen: Set<String>): List<JSONObject> =
        snap.items("orders").filter {
            it.optString("status") == "accepted" && it.optBoolean("near", false) && it.optString("id") !in seen
        }

    /** Takes the orders to ask about and remembers them: never twice. */
    fun take(context: Context, snap: Snapshot): List<JSONObject> {
        if (!snap.ready) return emptyList()
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val seen = prefs.getString(KEY, null)?.let { r -> runCatching { JSONArray(r) }.getOrNull() }
            ?.let { a -> (0 until a.length()).map { a.optString(it) } }
            ?: emptyList()
        val out = fresh(snap, seen.toSet())
        if (out.isNotEmpty()) {
            val kept = (seen + out.map { it.optString("id") }).distinct().takeLast(KEPT)
            prefs.edit().putString(KEY, JSONArray(kept).toString()).apply()
        }
        return out
    }

    fun title(snap: Snapshot, o: JSONObject): String = snap.label("arrivalTitle").replace("{point}", o.optString("title"))

    /** « Vous êtes arrivé à P2. Signaler l'arrivée ? », read aloud. */
    fun question(snap: Snapshot, o: JSONObject): String = "${title(snap, o)}. ${snap.label("arrivalAsk")}"

    fun alertId(o: JSONObject): Int = ("arrival:" + o.optString("id")).hashCode() and 0x7fffffff

    /** « Oui »: the order arrived and the status « Sur place ». */
    fun yes(context: Context, id: String) {
        CarData.post(context, JSONObject().put("type", "arrival").put("id", id))
    }

    /** The alert over the SARCADE screen: « Oui » and « Plus tard ». */
    fun alert(context: CarContext, snap: Snapshot, o: JSONObject, onEnd: () -> Unit = {}): Alert {
        val id = o.optString("id")
        val ok = Action.Builder().setTitle(snap.label("yes"))
            .setIcon(CarUi.icon(context, R.drawable.sarcade_car_check))
            .setOnClickListener {
                yes(context, id)
                CarUi.toast(context, snap.label("sent"))
                onEnd()
            }.build()
        val later = Action.Builder().setTitle(snap.label("later"))
            .setIcon(CarUi.icon(context, R.drawable.sarcade_car_close))
            .setOnClickListener { onEnd() }
            .build()
        return Alert.Builder(alertId(o), CarText.create(title(snap, o)), OrderAlerts.ALERT_MS)
            .setSubtitle(CarText.create(snap.label("arrivalAsk")))
            .setIcon(CarUi.icon(context, R.drawable.sarcade_car_flag))
            .addAction(ok)
            .addAction(later)
            .setCallback(object : AlertCallback {
                override fun onCancel(reason: Int) { onEnd() }
                override fun onDismiss() { onEnd() }
            })
            .build()
    }

    /** Answer spoken after the question: true « oui », false « plus tard »
     *  or « non », null when not understood. */
    fun spokenAnswer(heard: String?): Boolean? {
        val t = Normalizer.normalize(heard ?: return null, Normalizer.Form.NFD)
            .replace(Regex("\\p{M}"), "").lowercase(Locale.ROOT)
        val words = t.split(Regex("[^a-z]+")).filter { it.isNotEmpty() }
        if (t.contains("plus tard") || words.any { it in NO }) return false
        if (words.any { it in YES }) return true
        return null
    }

    private val YES = setOf("oui", "ouais", "yes", "yeah", "signaler", "signale", "arrive", "arrived", "ok", "daccord", "accord")
    private val NO = setOf("non", "no", "later", "tard", "attends", "attendre", "pas")

    /** Notification of the car with « Oui », when the alert cannot be shown
     *  (SARCADE not on the car screen, older car). */
    fun notify(context: CarContext, snap: Snapshot, o: JSONObject) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val id = alertId(o)
        val title = title(snap, o)
        val text = snap.label("arrivalAsk")
        val yes = CarPendingIntent.getCarApp(
            context, id,
            Intent(ACTION_YES).setComponent(ComponentName(context, SarcadeCarAppService::class.java))
                .putExtra(OrderAlerts.EXTRA_ID, o.optString("id")),
            0,
        )
        val see = CarPendingIntent.getCarApp(
            context, id + 1,
            Intent(OrderAlerts.ACTION_VIEW).setComponent(ComponentName(context, SarcadeCarAppService::class.java))
                .putExtra(OrderAlerts.EXTRA_ID, o.optString("id")),
            0,
        )
        val manager = CarNotificationManager.from(context)
        try {
            manager.createNotificationChannel(
                NotificationChannelCompat.Builder(CHANNEL, NotificationManagerCompat.IMPORTANCE_HIGH)
                    .setName(snap.label("arrivalAsk")).build()
            )
            val builder = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.sarcade_car_flag)
                .setContentTitle(title)
                .setContentText(text)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .extend(
                    CarAppExtender.Builder()
                        .setContentTitle(title)
                        .setContentText(text)
                        .setSmallIcon(R.drawable.sarcade_car_flag)
                        .setContentIntent(see)
                        .setImportance(NotificationManagerCompat.IMPORTANCE_HIGH)
                        .addAction(R.drawable.sarcade_car_check, snap.label("yes"), yes)
                        .build()
                )
            manager.notify(id, builder)
        } catch (e: Exception) {
            // No notification: the question read aloud and the order card remain.
        }
    }

    fun cancelNotification(context: Context, o: JSONObject) {
        runCatching { CarNotificationManager.from(context).cancel(alertId(o)) }
    }
}
