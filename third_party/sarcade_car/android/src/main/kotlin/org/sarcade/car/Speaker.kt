package org.sarcade.car

import android.content.Context
import android.media.AudioAttributes
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/** « Lire » : the messages read aloud by the text to speech of the phone,
 *  heard in the car through Android Auto. Lot 24: [say] may call back once
 *  the text is read (question of the arrival, then the answer listened). */
internal class Speaker(context: Context) : TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = TextToSpeech(context.applicationContext, this)
    private var ready = false
    private var pending: Triple<String, String, (() -> Unit)?>? = null
    private val main = Handler(Looper.getMainLooper())
    private var seq = 0
    private val done = HashMap<String, () -> Unit>()

    override fun onInit(status: Int) {
        ready = status == TextToSpeech.SUCCESS
        if (ready) {
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) { finished(utteranceId) }
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) { finished(utteranceId) }
            })
        }
        val p = pending
        pending = null
        if (ready && p != null) say(p.first, p.second, p.third)
    }

    private fun finished(id: String?) {
        val callback = synchronized(done) { id?.let { done.remove(it) } } ?: return
        main.post { callback() }
    }

    fun say(text: String, lang: String, onDone: (() -> Unit)? = null) {
        val t = tts ?: return
        if (!ready) {
            pending = Triple(text, lang, onDone)
            return
        }
        t.setLanguage(if (lang == "en") Locale.ENGLISH else Locale.FRENCH)
        t.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        val id = "sarcade-car-${seq++}"
        if (onDone != null) synchronized(done) { done[id] = onDone }
        t.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
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
