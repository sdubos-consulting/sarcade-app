package org.sarcade.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
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

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                CarData.sessionChanged(1)
            }

            override fun onDestroy(owner: LifecycleOwner) {
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

    override fun onCreateScreen(intent: Intent): Screen = MainScreen(carContext, this)
}
