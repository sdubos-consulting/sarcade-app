package org.sarcade.car

import android.content.pm.PackageManager
import androidx.car.app.CarContext
import androidx.car.app.hardware.CarHardwareManager
import androidx.car.app.hardware.common.CarValue
import androidx.car.app.hardware.common.OnCarDataAvailableListener
import androidx.car.app.hardware.info.Speed
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.core.content.ContextCompat
import org.json.JSONObject

/**
 * Remotes of relays from the car (lot 24, card « Android Auto :
 * télécommandes de relais depuis la voiture »):
 * 1. « Télécommandes » row at the bottom of the Points tab → list of the
 *    remotes → card of a remote with Allumer / Éteindre for each relay;
 * 2. confirmation always (« Allumer Relais 1 de Maurepas ? »); refused
 *    while the vehicle moves when Android Auto tells its speed
 *    ([CarMotion]);
 * 3. the answer of the box is read aloud (application, « say »);
 * 4. only the remotes declared in the application.
 * Screens: tabs, list, card, confirmation: 4 steps of the 5 allowed.
 */
internal class RemotesScreen(carContext: CarContext) : LiveScreen(carContext) {
    init {
        CarMotion.start(carContext)
    }

    override fun watched(s: Snapshot): String = "${s.lang}|${s.items("remotes").map { listOf(it.optString("id"), it.optString("title"), it.optString("text")) }}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val items = ItemList.Builder()
        for (r in s.items("remotes").take(CarUi.listLimit(carContext))) {
            val id = r.optString("id")
            items.addItem(
                Row.Builder().setTitle(r.optString("title")).addText(r.optString("text"))
                    .setImage(CarUi.tile(carContext, R.drawable.sarcade_car_power, if (r.optBoolean("ready")) READY else DOWN))
                    .setOnClickListener { screenManager.push(RemoteScreen(carContext, id)) }
                    .build()
            )
        }
        if (s.items("remotes").isEmpty()) items.setNoItemsMessage(s.label("gone"))
        return ListTemplate.Builder().setSingleList(items.build())
            .setTitle(s.label("remotes"))
            .setHeaderAction(Action.BACK)
            .build()
    }

    companion object {
        const val READY = 0xFF43A047.toInt()
        const val DOWN = 0xFF757575.toInt()

        fun row(context: CarContext, s: Snapshot, onClick: () -> Unit): Row =
            Row.Builder().setTitle(s.label("remotes"))
                .addText(s.items("remotes").joinToString(", ") { it.optString("title") })
                .setImage(CarUi.tile(context, R.drawable.sarcade_car_power, READY))
                .setOnClickListener { onClick() }
                .build()
    }
}

/** Card of a remote: one row per relay, its state; Allumer / Éteindre. */
internal class RemoteScreen(carContext: CarContext, private val id: String) : LiveScreen(carContext) {
    override fun watched(s: Snapshot): String = "${s.lang}|${s.item("remotes", id)}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val r = s.item("remotes", id) ?: return gone()
        val relays = r.optJSONArray("relays")
        val items = ItemList.Builder()
        val level = carContext.carAppApiLevel
        for (k in 0 until (relays?.length() ?: 0)) {
            val relay = relays!!.optJSONObject(k) ?: continue
            val row = Row.Builder().setTitle(relay.optString("name"))
                .addText(listOf(relay.optString("state"), relay.optString("detail")).filter { it.isNotEmpty() }.joinToString(" · "))
                .setImage(CarUi.tile(carContext, R.drawable.sarcade_car_power, if (relay.optBoolean("on", false)) RemotesScreen.READY else RemotesScreen.DOWN))
            if (level >= MainScreen.TABS_LEVEL) {
                // Row buttons from the car API level 6 (the car shows their icon).
                row.addAction(command(s, r, k, relay, false))
                if (level >= MainScreen.TWO_ROW_ACTIONS_LEVEL) row.addAction(command(s, r, k, relay, true))
            }
            // Older cars, or one button only: touching the row asks the
            // opposite of the last confirmed state.
            row.setOnClickListener { confirm(r, k, relay, !relay.optBoolean("on", false)) }
            items.addItem(row.build())
        }
        return ListTemplate.Builder().setSingleList(items.build())
            .setTitle(r.optString("title"))
            .setHeaderAction(Action.BACK)
            .build()
    }

    private fun command(s: Snapshot, r: JSONObject, k: Int, relay: JSONObject, on: Boolean): Action {
        val b = Action.Builder().setTitle(s.label(if (on) "remoteOn" else "remoteOff"))
            .setIcon(CarUi.icon(carContext, if (on) R.drawable.sarcade_car_power else R.drawable.sarcade_car_close))
            .setOnClickListener { confirm(r, k, relay, on) }
        if (on) b.setFlags(Action.FLAG_PRIMARY)
        return b.build()
    }

    private fun confirm(r: JSONObject, k: Int, relay: JSONObject, on: Boolean) {
        screenManager.push(RemoteConfirmScreen(carContext, r.optString("id"), k, on, relay.optString(if (on) "ask.on" else "ask.off")))
    }
}

/** « Allumer Relais 1 de Maurepas ? »: Annuler, Allumer (or Éteindre). */
internal class RemoteConfirmScreen(
    carContext: CarContext,
    private val id: String,
    private val relay: Int,
    private val on: Boolean,
    private val question: String,
) : LiveScreen(carContext) {
    override fun watched(s: Snapshot): String = s.lang

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val go = Action.Builder().setTitle(s.label(if (on) "remoteOn" else "remoteOff"))
            .setFlags(Action.FLAG_PRIMARY)
            .setOnClickListener {
                if (CarMotion.moving == true) {
                    CarUi.toast(carContext, s.label("remoteParked"))
                } else {
                    CarUi.post(carContext, "remote") { put("id", id); put("relay", relay); put("on", on) }
                    CarUi.toast(carContext, s.label("remoteSent"))
                }
                screenManager.pop()
            }
        if (on) go.setBackgroundColor(CarColor.GREEN)
        return MessageTemplate.Builder(question)
            .setTitle(s.label("remoteTitle"))
            .setHeaderAction(Action.BACK)
            .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_power))
            .addAction(Action.Builder().setTitle(s.label("cancel")).setOnClickListener { screenManager.pop() }.build())
            .addAction(go.build())
            .build()
    }
}

/**
 * Speed of the vehicle given by Android Auto (car API level 3, permission
 * CAR_SPEED, asked once): [moving] true above 1 m/s, false stopped, null
 * unknown (no permission, older car, no value): then the remotes are not
 * blocked (choice 2: « si Android Auto le signale »).
 */
internal object CarMotion {
    const val PERMISSION = "com.google.android.gms.permission.CAR_SPEED"
    /** Above this speed (m/s), the vehicle moves. */
    const val MOVING_MPS = 1.0f

    @Volatile var moving: Boolean? = null
    private var listening = false
    private var asked = false

    private val listener = OnCarDataAvailableListener<Speed> { speed ->
        val v = speed.rawSpeedMetersPerSecond
        moving = if (v.status == CarValue.STATUS_SUCCESS && v.value != null) v.value!! > MOVING_MPS else null
    }

    fun start(context: CarContext) {
        if (listening) return
        if (ContextCompat.checkSelfPermission(context, PERMISSION) != PackageManager.PERMISSION_GRANTED) {
            if (!asked) {
                asked = true
                runCatching { context.requestPermissions(listOf(PERMISSION)) { granted, _ -> if (PERMISSION in granted) start(context) } }
            }
            return
        }
        runCatching {
            if (context.carAppApiLevel < 3) return
            context.getCarService(CarHardwareManager::class.java).carInfo
                .addSpeedListener(ContextCompat.getMainExecutor(context), listener)
            listening = true
        }
    }

    fun stop(context: CarContext) {
        if (!listening) return
        runCatching { context.getCarService(CarHardwareManager::class.java).carInfo.removeSpeedListener(listener) }
        listening = false
        moving = null
    }
}
