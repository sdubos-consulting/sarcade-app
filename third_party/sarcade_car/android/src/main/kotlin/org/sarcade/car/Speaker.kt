package org.sarcade.car

import android.content.Context
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import java.util.Locale

/** « Lire » : the messages read aloud by the text to speech of the phone,
 *  heard in the car through Android Auto. */
internal class Speaker(context: Context) : TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = TextToSpeech(context.applicationContext, this)
    private var ready = false
    private var pending: Pair<String, String>? = null

    override fun onInit(status: Int) {
        ready = status == TextToSpeech.SUCCESS
        val p = pending
        pending = null
        if (ready && p != null) say(p.first, p.second)
    }

    fun say(text: String, lang: String) {
        val t = tts ?: return
        if (!ready) {
            pending = Pair(text, lang)
            return
        }
        t.setLanguage(if (lang == "en") Locale.ENGLISH else Locale.FRENCH)
        t.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        t.speak(text, TextToSpeech.QUEUE_FLUSH, null, "sarcade-car")
    }

    fun stop() {
        tts?.stop()
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
    }
}
