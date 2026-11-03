package org.sarcade.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarText
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import org.json.JSONObject

/** Screen that follows the data of the application while it is shown. */
internal abstract class LiveScreen(carContext: CarContext) : Screen(carContext) {
    /** Drawn again only when what it shows changed (lot 20, choice 4). */
    private var shown: String? = null
    private val refresh: () -> Unit = {
        if (watched(snap) != shown) invalidate()
    }

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

    /** Data this screen shows, as text (see [Snapshot.signature]). */
    protected abstract fun watched(s: Snapshot): String

    /** Called by [onGetTemplate] of each screen: remembers what is drawn. */
    protected fun drawn(s: Snapshot) {
        shown = watched(s)
    }

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

    override fun watched(s: Snapshot): String = "${s.lang}|${s.item("messages", key)}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
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
 * Lot 24: also « Écrire » of the card of an operator ([mode] WRITE: a new
 * direct message to [to], not an answer) and « Écrire au PCO » of the card
 * of an order ([mode] PCO).
 */
internal class ReplyScreen(
    carContext: CarContext,
    private val key: String,
    private val to: String,
    private val mode: String = REPLY,
) : LiveScreen(carContext) {
    companion object {
        const val REPLY = "reply"
        const val WRITE = "write"
        const val PCO = "writePco"
    }

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

    /** Only the language: the dictation redraws this screen itself. */
    override fun watched(s: Snapshot): String = s.lang

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val title = when (mode) {
            WRITE -> s.label("writeTo").replace("{who}", to)
            PCO -> s.label("pcoTitle")
            else -> s.label("replyTo").replace("{who}", to)
        }
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
                            when (mode) {
                                WRITE -> CarUi.post(carContext, WRITE) { put("to", to); put("text", text) }
                                PCO -> CarUi.post(carContext, PCO) { put("order", key); put("text", text) }
                                else -> CarUi.post(carContext, REPLY) { put("conversation", key); put("text", text) }
                            }
                            CarUi.toast(carContext, s.label("sent"))
                            screenManager.pop()
                        }.build()
                )
                .build()
        }
    }
}

/**
 * Card of an operator (lot 24, card « Android Auto, onglet Équipe : fiche
 * d'un opérateur avec actions », choices 2 and 3): name and role, distance
 * and direction, age of the position, battery when known, last message
 * received from him; « Y aller » (main button, in colour when the car
 * allows it) and « Écrire » (dictated message), two buttons at most.
 */
internal class TeammateScreen(carContext: CarContext, private val id: String) : LiveScreen(carContext) {
    override fun watched(s: Snapshot): String = "${s.lang}|${s.teammate(id)}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val t = s.item("team", id) ?: return gone()
        val pane = Pane.Builder()
        val first = Row.Builder().setTitle(t.optString("role").ifEmpty { s.label("operator") })
            .setImage(CarUi.tile(carContext, CarUi.operatorIcon(t.optString("icon")), t.optInt("color", MainScreen.DEFAULT_COLOR)))
        t.optString("battery").takeIf { it.isNotEmpty() }?.let { first.addText(it) }
        pane.addRow(first.build())
        val where = Row.Builder().setTitle(t.optString("away").ifEmpty { s.label("noPosition") })
        t.optString("seen").takeIf { it.isNotEmpty() }?.let { where.addText(it) }
        pane.addRow(where.build())
        t.optString("last").takeIf { it.isNotEmpty() }?.let {
            pane.addRow(Row.Builder().setTitle(s.label("lastMessage")).addText(it).build())
        }
        pane.addAction(
            Action.Builder().setTitle(s.label("write"))
                .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_mic))
                .setOnClickListener { screenManager.push(ReplyScreen(carContext, "", id, ReplyScreen.WRITE)) }
                .build()
        )
        if (MainScreen.hasPosition(t)) {
            pane.addAction(
                Action.Builder(MainScreen.goToTeammate(carContext, s, id, t, CarText.create(s.label("go"))))
                    .setBackgroundColor(CarColor.PRIMARY).build()
            )
        }
        return PaneTemplate.Builder(pane.build())
            .setTitle(t.optString("title"))
            .setHeaderAction(Action.BACK)
            .build()
    }
}

/**
 * An order (Ordres tab): who, where, how far, and its buttons.
 *
 * Lot 24 (card « Android Auto : fiches dans les onglets Points et Ordres »,
 * choice 2): « Écrire au PCO » in the card; order sent: Accepter / Refuser;
 * accepted: Y aller / Écrire, « Je suis arrivé » kept as a third button in
 * the action strip at the top (2 buttons at most in a card, Car App
 * Library).
 */
internal class OrderScreen(carContext: CarContext, private val id: String) : LiveScreen(carContext) {
    override fun watched(s: Snapshot): String = "${s.lang}|${s.item("orders", id)}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val o = s.item("orders", id) ?: return gone()
        val pane = Pane.Builder()
            .addRow(Row.Builder().setTitle(o.optString("title")).addText(o.optString("text")).build())
        val note = o.optString("note")
        if (note.isNotEmpty()) pane.addRow(Row.Builder().setTitle(s.label("note")).addText(note).build())
        val card = orderCard(carContext, s, o) { screenManager.push(ReplyScreen(carContext, id, o.optString("from"), ReplyScreen.PCO)) }
        card.body.forEach { pane.addAction(it) }
        val t = PaneTemplate.Builder(pane.build())
            .setTitle(s.label("order"))
            .setHeaderAction(Action.BACK)
        if (card.strip.isNotEmpty()) {
            val strip = ActionStrip.Builder()
            card.strip.forEach { strip.addAction(it) }
            t.setActionStrip(strip.build())
        }
        return t.build()
    }

    /** Buttons of the card of an order: [body] (2 at most, the main one
     *  last) and [strip] (action strip at the top, one titled button). */
    class Card(val body: List<Action>, val strip: List<Action>)

    companion object {
        fun orderCard(context: CarContext, s: Snapshot, o: JSONObject, writePco: () -> Unit): Card {
            fun write(title: String) = Action.Builder().setTitle(s.label(title))
                .setIcon(CarUi.icon(context, R.drawable.sarcade_car_mic))
                .setOnClickListener { writePco() }.build()
            val go = Action.Builder().setTitle(s.label("go")).setFlags(Action.FLAG_PRIMARY)
                .setIcon(CarUi.icon(context, R.drawable.sarcade_car_directions))
                .setOnClickListener { CarUi.navigate(context, s, o.optDouble("lat"), o.optDouble("lon")) }
                .build()
            val answers = MainScreen.orderActions(context, s, o)
            return when (o.optString("status")) {
                // Refuser, Accepter; « Écrire au PCO » at the top.
                "sent" -> Card(answers, listOf(write("writePco")))
                // Écrire, Y aller; « Je suis arrivé » at the top.
                "accepted" -> Card(listOf(write("write"), go), answers.take(1))
                else -> Card(listOf(write("writePco"), go), emptyList())
            }
        }
    }
}

/**
 * Card of a point (lot 24, card « Android Auto : fiches dans les onglets
 * Points et Ordres », choice 1): name, type, distance and direction,
 * altitude of a high point, who created it; « Je suis sur place » (message
 * to the PCO with my position) and « Y aller ».
 */
internal class PointScreen(carContext: CarContext, private val id: String) : LiveScreen(carContext) {
    override fun watched(s: Snapshot): String = "${s.lang}|${s.item("points", id)}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val p = s.item("points", id) ?: return gone()
        val pane = Pane.Builder()
        val first = Row.Builder().setTitle(p.optString("type").ifEmpty { s.label("point") })
            .setImage(CarUi.tile(carContext, CarUi.pointIcon(p.optString("icon")), p.optInt("color", MainScreen.DEFAULT_COLOR)))
        p.optString("by").takeIf { it.isNotEmpty() }?.let { first.addText(it) }
        pane.addRow(first.build())
        val where = Row.Builder().setTitle(p.optString("away").ifEmpty { s.label("noPosition") })
        p.optString("alt").takeIf { it.isNotEmpty() }?.let { where.addText(it) }
        pane.addRow(where.build())
        pane.addAction(
            Action.Builder().setTitle(s.label("onSite"))
                .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_location_on))
                .setOnClickListener {
                    CarUi.post(carContext, "onSite") { put("id", id) }
                    CarUi.toast(carContext, s.label("sent"))
                }.build()
        )
        pane.addAction(
            Action.Builder().setTitle(s.label("go")).setFlags(Action.FLAG_PRIMARY)
                .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_directions))
                .setOnClickListener { CarUi.navigate(carContext, s, p.optDouble("lat"), p.optDouble("lon")) }
                .build()
        )
        return PaneTemplate.Builder(pane.build())
            .setTitle(p.optString("title"))
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
    override fun watched(s: Snapshot): String = "${s.lang}|${s.distress}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
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
