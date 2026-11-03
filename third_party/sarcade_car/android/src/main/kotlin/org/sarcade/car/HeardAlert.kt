package org.sarcade.car

import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.model.Action
import androidx.car.app.model.Alert
import androidx.car.app.model.CarText
import java.util.UUID

/**
 * « Signal entendu ici » (lot 24, card « Android Auto : « Signal entendu
 * ici » (SATER) », choices 2 and 4): one touch sends the listening point
 * (position, heading of the vehicle and time, given by the application);
 * an alert « Point d'écoute envoyé » with « Annuler » stays 10 s, the time
 * the server gives to cancel it.
 */
internal object HeardAlert {
    /** Orange of the listening points (server default 0xFFFF9F1C). */
    const val COLOR = 0xFFFF9F1C.toInt()
    const val CANCEL_MS = 10_000L

    /** Sends the point; returns its identifier (chosen here so that
     *  « Annuler » names it). */
    fun send(context: CarContext, snap: Snapshot): String {
        val id = UUID.randomUUID().toString()
        CarUi.post(context, "heard") { put("id", id); put("at", System.currentTimeMillis()) }
        val shown = runCatching { context.carAppApiLevel >= OrderAlerts.ALERT_LEVEL }.getOrDefault(false) &&
            runCatching { context.getCarService(AppManager::class.java).showAlert(alert(context, snap, id)) }.isSuccess
        // Older cars: no alert, so no « Annuler ».
        if (!shown) CarUi.toast(context, snap.label("heardSent"))
        return id
    }

    fun alert(context: CarContext, snap: Snapshot, id: String): Alert {
        val cancel = Action.Builder().setTitle(snap.label("cancel"))
            .setIcon(CarUi.icon(context, R.drawable.sarcade_car_close))
            .setOnClickListener {
                CarUi.post(context, "heardCancel") { put("id", id) }
                CarUi.toast(context, snap.label("heardCancelled"))
            }.build()
        return Alert.Builder(id.hashCode() and 0x7fffffff, CarText.create(snap.label("heardSent")), CANCEL_MS)
            .setSubtitle(CarText.create(snap.label("heardHelp")))
            .setIcon(CarUi.icon(context, R.drawable.sarcade_car_cell_tower))
            .addAction(cancel)
            .build()
    }
}
