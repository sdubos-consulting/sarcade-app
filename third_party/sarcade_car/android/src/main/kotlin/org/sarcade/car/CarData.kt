package org.sarcade.car

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * What the car shows, written by the application (Dart, lib/src/features/car/
 * car_screen.dart) through the channel of [SarcadeCarPlugin], and what the
 * driver did in the car, read back by the application.
 *
 * - the last data are kept in the private preferences of the application, so
 *   that the car shows them at once, even before the application answers;
 * - the actions (order answered, SOS, dictated answer, read) wait in the same
 *   preferences until the application takes them: none is lost when the
 *   application is not running at that moment.
 */
internal object CarData {
    private const val PREFS = "sarcade_car_screen"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_ACTIONS = "actions"

    private val main = Handler(Looper.getMainLooper())
    private var snapshot: JSONObject? = null
    private val listeners = LinkedHashSet<() -> Unit>()
    private val plugins = LinkedHashSet<SarcadeCarPlugin>()
    private var sessions = 0

    /** A car session is open (Android Auto shows SARCADE). */
    val active: Boolean get() = sessions > 0

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Last data written by the application; empty before its first run. */
    fun snapshot(context: Context): JSONObject {
        snapshot?.let { return it }
        val raw = prefs(context).getString(KEY_SNAPSHOT, null)
        val read = raw?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
        snapshot = read
        return read
    }

    fun update(context: Context, json: String) {
        val read = runCatching { JSONObject(json) }.getOrNull() ?: return
        snapshot = read
        prefs(context).edit().putString(KEY_SNAPSHOT, json).apply()
        main.post { listeners.toList().forEach { it() } }
    }

    fun addListener(listener: () -> Unit) { listeners.add(listener) }
    fun removeListener(listener: () -> Unit) { listeners.remove(listener) }

    /** Keeps an action of the driver and tells the application. */
    fun post(context: Context, action: JSONObject) {
        action.put("uid", UUID.randomUUID().toString())
        action.put("at", System.currentTimeMillis())
        synchronized(this) {
            val p = prefs(context)
            val list = runCatching { JSONArray(p.getString(KEY_ACTIONS, "[]")) }.getOrNull() ?: JSONArray()
            list.put(action)
            p.edit().putString(KEY_ACTIONS, list.toString()).apply()
        }
        main.post { plugins.toList().forEach { it.notifyActions() } }
    }

    /** Actions since the last call, as a JSON list; the list is emptied. */
    fun takeActions(context: Context): String = synchronized(this) {
        val p = prefs(context)
        val raw = p.getString(KEY_ACTIONS, null) ?: "[]"
        p.edit().remove(KEY_ACTIONS).apply()
        raw
    }

    fun attach(plugin: SarcadeCarPlugin) { plugins.add(plugin) }
    fun detach(plugin: SarcadeCarPlugin) { plugins.remove(plugin) }

    /** A car session opens (+1) or closes (-1): the application only sends
     *  its data while the car shows SARCADE. */
    fun sessionChanged(delta: Int) {
        sessions = (sessions + delta).coerceAtLeast(0)
        val now = active
        main.post { plugins.toList().forEach { it.notifyActive(now) } }
    }
}
