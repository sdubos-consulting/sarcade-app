package org.sarcade.car

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * « Répondre » : the answer dictated, never typed (choice 5 of the card).
 * Speech recognition of the phone (microphone permission already given for
 * the dictation of the application); [onDone] gets the text, or null when
 * nothing was understood or the recognition is not available.
 */
internal class Dictation(
    private val context: Context,
    private val lang: String,
    private val onDone: (String?) -> Unit,
) : RecognitionListener {
    private var recognizer: SpeechRecognizer? = null
    private var done = false

    /** False when the recognition cannot start (no service, no permission). */
    fun start(): Boolean {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) return false
        if (context.checkCallingOrSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return false
        val r = runCatching { SpeechRecognizer.createSpeechRecognizer(context) }.getOrNull() ?: return false
        recognizer = r
        r.setRecognitionListener(this)
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, if (lang == "en") "en-GB" else "fr-FR")
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        return runCatching { r.startListening(intent) }.isSuccess
    }

    fun cancel() {
        done = true
        recognizer?.let { runCatching { it.cancel() }; runCatching { it.destroy() } }
        recognizer = null
    }

    private fun finish(text: String?) {
        if (done) return
        done = true
        recognizer?.let { runCatching { it.destroy() } }
        recognizer = null
        onDone(text?.trim()?.takeIf { it.isNotEmpty() })
    }

    override fun onResults(results: Bundle?) {
        finish(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull())
    }

    override fun onError(error: Int) {
        finish(null)
    }

    override fun onReadyForSpeech(params: Bundle?) {}
    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {}
    override fun onPartialResults(partialResults: Bundle?) {}
    override fun onEvent(eventType: Int, params: Bundle?) {}
}
