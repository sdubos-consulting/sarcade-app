package org.sarcade.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/** Screen that follows the data of the application while it is shown. */
internal abstract class LiveScreen(carContext: CarContext) : Screen(carContext) {
    private val refresh: () -> Unit = { invalidate() }

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                CarData.addListener(refresh)
            }

            override fun onDestroy(owner: LifecycleOwner) {
                CarData.removeListener(refresh)
                onClosed()
            }
        })
    }

    protected val snap: Snapshot get() = Snapshot(CarData.snapshot(carContext))

    protected open fun onClosed() {}

    /** The item is gone (deleted, cancelled): a short message, back. */
    protected fun gone(): Template = MessageTemplate.Builder(snap.label("gone"))
        .setHeaderAction(Action.BACK)
        .build()
}

/**
 * A conversation (Messages tab): its last messages, « Lire » (read aloud)
 * and « Répondre » (dictated answer, to the sender, as the answers of the
 * notifications, lot 1b). Opening it marks it as read, as on the phone.
 */
internal class ConversationScreen(
    carContext: CarContext,
    private val session: SarcadeSession,
    private val key: String,
) : LiveScreen(carContext) {
    init {
        CarUi.post(carContext, "read") { put("conversation", key) }
    }

    override fun onClosed() {
        session.stopSpeaking()
    }

    override fun onGetTemplate(): Template {
        val s = snap
        val c = s.item("messages", key) ?: return gone()
        val b = MessageTemplate.Builder(c.optString("body").ifEmpty { c.optString("text") })
            .setTitle(c.optString("title"))
            .setHeaderAction(Action.BACK)
            .setIcon(CarUi.tile(carContext, CarUi.operatorIcon(c.optString("icon")), c.optInt("color", MainScreen.DEFAULT_COLOR)))
        if (c.optBoolean("canReply", false)) {
            b.addAction(
                Action.Builder().setTitle(s.label("reply"))
                    .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_mic))
                    .setOnClickListener { screenManager.push(ReplyScreen(carContext, key, c.optString("replyTo"))) }
                    .build()
            )
        }
        b.addAction(
            Action.Builder().setTitle(s.label("read"))
                .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_volume_up))
                .setFlags(Action.FLAG_PRIMARY)
                .setOnClickListener { session.speaker().say(c.optString("speak"), s.lang) }
                .build()
        )
        return b.build()
    }
}

/**
 * « Répondre » : dictation at once, then « Envoyer » or « Annuler »; no
 * keyboard (choice 5). The answer goes to [to] in a direct message.
 */
internal class ReplyScreen(
    carContext: CarContext,
    private val key: String,
    private val to: String,
) : LiveScreen(carContext) {
    private enum class State { LISTENING, HEARD, FAILED }

    private var state = State.LISTENING
    private var text = ""
    private var dictation: Dictation? = null

    init {
        listen()
    }

    private fun listen() {
        state = State.LISTENING
        val d = Dictation(carContext, snap.lang) { heard ->
            dictation = null
            if (heard == null) {
                state = State.FAILED
            } else {
                text = heard
                state = State.HEARD
            }
            invalidate()
        }
        dictation = d
        if (!d.start()) {
            dictation = null
            state = State.FAILED
        }
    }

    override fun onClosed() {
        dictation?.cancel()
        dictation = null
    }

    override fun onGetTemplate(): Template {
        val s = snap
        val title = s.label("replyTo").replace("{who}", to)
        return when (state) {
            State.LISTENING -> MessageTemplate.Builder(s.label("listening"))
                .setTitle(title)
                .setHeaderAction(Action.BACK)
                .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_mic))
                .build()
            State.FAILED -> MessageTemplate.Builder(s.label("dictationFailed"))
                .setTitle(title)
                .setHeaderAction(Action.BACK)
                .addAction(Action.Builder().setTitle(s.label("cancel")).setOnClickListener { screenManager.pop() }.build())
                .addAction(
                    Action.Builder().setTitle(s.label("retry")).setFlags(Action.FLAG_PRIMARY)
                        .setOnClickListener { listen(); invalidate() }.build()
                )
                .build()
            State.HEARD -> MessageTemplate.Builder("« $text »")
                .setTitle(title)
                .setHeaderAction(Action.BACK)
                .addAction(Action.Builder().setTitle(s.label("cancel")).setOnClickListener { screenManager.pop() }.build())
                .addAction(
                    Action.Builder().setTitle(s.label("send")).setFlags(Action.FLAG_PRIMARY)
                        .setOnClickListener {
                            CarUi.post(carContext, "reply") { put("conversation", key); put("text", text) }
                            CarUi.toast(carContext, s.label("sent"))
                            screenManager.pop()
                        }.build()
                )
                .build()
        }
    }
}

/** An order (Ordres tab): who, where, how far, and its buttons. */
internal class OrderScreen(carContext: CarContext, private val id: String) : LiveScreen(carContext) {
    override fun onGetTemplate(): Template {
        val s = snap
        val o = s.item("orders", id) ?: return gone()
        val pane = Pane.Builder()
            .addRow(Row.Builder().setTitle(o.optString("title")).addText(o.optString("text")).build())
        val note = o.optString("note")
        if (note.isNotEmpty()) pane.addRow(Row.Builder().setTitle(s.label("note")).addText(note).build())
        val actions = MainScreen.orderActions(carContext, s, o)
        actions.forEach { pane.addAction(it) }
        if (actions.isEmpty()) {
            pane.addAction(
                Action.Builder().setTitle(CarUi.navigateTitle(carContext, s))
                    .setOnClickListener { CarUi.navigate(carContext, s, o.optDouble("lat"), o.optDouble("lon"), o.optString("title")) }
                    .build()
            )
        }
        return PaneTemplate.Builder(pane.build())
            .setTitle(s.label("order"))
            .setHeaderAction(Action.BACK)
            .build()
    }
}

/**
 * SOS (choice 3), with confirmation: the same distress as the button of
 * the phone (immediate message to everyone with the position); during a
 * distress, « Fin de détresse » instead, as on the phone.
 */
internal class SosScreen(carContext: CarContext) : LiveScreen(carContext) {
    override fun onGetTemplate(): Template {
        val s = snap
        val end = s.distress
        val confirm = Action.Builder()
            .setTitle(s.label(if (end) "sosEnd" else "sosSend"))
            .setFlags(Action.FLAG_PRIMARY)
            .setOnClickListener {
                CarUi.post(carContext, if (end) "sosEnd" else "sos")
                CarUi.toast(carContext, s.label(if (end) "sosEnded" else "sosSent"))
                screenManager.pop()
            }
        if (!end) confirm.setBackgroundColor(CarColor.RED)
        return MessageTemplate.Builder(s.label(if (end) "sosOn" else "sosAsk"))
            .setTitle(s.label("sosTitle"))
            .setHeaderAction(Action.BACK)
            .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_sos, CarColor.RED))
            .addAction(Action.Builder().setTitle(s.label("cancel")).setOnClickListener { screenManager.pop() }.build())
            .addAction(confirm.build())
            .build()
    }
}
