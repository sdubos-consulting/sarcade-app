package org.sarcade.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.AppManager
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.ScreenManager
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner

/**
 * SARCADE in Android Auto, « points of interest » category (card « Voiture :
 * vraie interface SARCADE avec onglets », lot 17, 1 Nov 2026).
 *
 * Only the Android Auto and Android Automotive hosts signed by Google may
 * bind (list of the library); any host for a debuggable build (Desktop Head
 * Unit with a debug build).
 */
class SarcadeCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    @Suppress("OVERRIDE_DEPRECATION", "DEPRECATION")
    override fun onCreateSession(): Session = SarcadeSession()
}

/** One car screen: tabs, then the detail screens pushed over them. */
internal class SarcadeSession : Session() {
    private var speaker: Speaker? = null
    private val orders: () -> Unit = { announceOrders(); askArrivals() }
    /** Dictation of the spoken answer to the arrival question (lot 24). */
    private var listening: Dictation? = null

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                CarData.sessionChanged(1)
                CarData.addListener(orders)
            }

            override fun onDestroy(owner: LifecycleOwner) {
                CarData.removeListener(orders)
                listening?.cancel()
                listening = null
                CarData.sessionChanged(-1)
                speaker?.shutdown()
                speaker = null
            }
        })
    }

    /** Text to speech of the car (« Lire »), created at its first use. */
    fun speaker(): Speaker = speaker ?: Speaker(carContext).also { speaker = it }

    fun stopSpeaking() {
        speaker?.stop()
    }

    override fun onCreateScreen(intent: Intent): Screen {
        val main = MainScreen(carContext, this)
        if (intent.action == ArrivalAlerts.ACTION_YES) {
            intent.getStringExtra(OrderAlerts.EXTRA_ID)?.takeIf { it.isNotEmpty() }?.let { ArrivalAlerts.yes(carContext, it) }
        }
        val id = orderOf(intent) ?: return main
        // « Voir » of the notification, SARCADE not open in the car yet:
        // the tabs, with the order screen over them.
        carContext.getCarService(ScreenManager::class.java).push(main)
        return OrderScreen(carContext, id)
    }

    override fun onNewIntent(intent: Intent) {
        if (intent.action == ArrivalAlerts.ACTION_YES) {
            // « Oui » of the arrival notification (lot 24).
            intent.getStringExtra(OrderAlerts.EXTRA_ID)?.takeIf { it.isNotEmpty() }?.let { ArrivalAlerts.yes(carContext, it) }
            return
        }
        val id = orderOf(intent) ?: return
        carContext.getCarService(ScreenManager::class.java).push(OrderScreen(carContext, id))
    }

    /** Lot 24 (card « Android Auto : arrivée détectée près du point d'un
     *  ordre »): once per order, within 100 m of its point, « Vous êtes
     *  arrivé à … Signaler l'arrivée ? »: alert over SARCADE (« Oui »,
     *  « Plus tard ») or notification of the car; the question is read
     *  aloud, then the answer listened (« oui », « plus tard »). */
    private fun askArrivals() {
        val snap = Snapshot(CarData.snapshot(carContext))
        val fresh = ArrivalAlerts.take(carContext, snap)
        if (fresh.isEmpty()) return
        val o = fresh.first()
        val shown = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        var open = true
        val alertShown = shown && runCatching { carContext.carAppApiLevel >= OrderAlerts.ALERT_LEVEL }.getOrDefault(false) &&
            runCatching {
                carContext.getCarService(AppManager::class.java).showAlert(
                    ArrivalAlerts.alert(carContext, snap, o) { open = false; listening?.cancel(); listening = null }
                )
            }.isSuccess
        if (!alertShown) ArrivalAlerts.notify(carContext, snap, o)
        runCatching {
            speaker().say(ArrivalAlerts.question(snap, o), snap.lang) {
                if (!open) return@say
                val d = Dictation(carContext, snap.lang) { heard ->
                    listening = null
                    val yes = ArrivalAlerts.spokenAnswer(heard)
                    if (yes != null && open) {
                        open = false
                        if (yes) {
                            ArrivalAlerts.yes(carContext, o.optString("id"))
                            CarUi.toast(carContext, snap.label("sent"))
                        }
                        if (alertShown) runCatching { carContext.getCarService(AppManager::class.java).dismissAlert(ArrivalAlerts.alertId(o)) }
                        else ArrivalAlerts.cancelNotification(carContext, o)
                    }
                }
                listening?.cancel()
                listening = if (d.start()) d else null
            }
        }
    }

    private fun orderOf(intent: Intent): String? =
        if (intent.action == OrderAlerts.ACTION_VIEW) intent.getStringExtra(OrderAlerts.EXTRA_ID)?.takeIf { it.isNotEmpty() } else null

    /** New move orders (lot 20): alert over SARCADE when it is on the car
     *  screen, otherwise a notification of the car. */
    private fun announceOrders() {
        val snap = Snapshot(CarData.snapshot(carContext))
        val fresh = OrderAlerts.take(carContext, snap)
        if (fresh.isEmpty()) return
        val shown = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        for (o in fresh) {
            val done = shown && runCatching { carContext.carAppApiLevel >= OrderAlerts.ALERT_LEVEL }.getOrDefault(false) &&
                runCatching {
                    carContext.getCarService(AppManager::class.java).showAlert(
                        OrderAlerts.alert(carContext, snap, o) {
                            carContext.getCarService(ScreenManager::class.java).push(OrderScreen(carContext, o.optString("id")))
                        }
                    )
                }.isSuccess
            if (!done) OrderAlerts.notify(carContext, snap, o)
        }
    }
}
