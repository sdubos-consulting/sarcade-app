package org.sarcade.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.ScreenManager
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarText
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import org.json.JSONObject

/** Screen that follows the data of the application while it is shown. */
/**
 * After a message sent from a conversation or from an order (dictated
 * answer, quick message): back to the list of the tab, the conversation or
 * the order closed too (card « Android Auto : après Envoyer, revenir à la
 * liste des conversations », validated on 8 Nov 2026). « Annuler » and Back
 * still come back to the conversation: nothing was sent.
 */
internal fun ScreenManager.backToList() {
    pop()
    if (top is ConversationScreen || top is OrderScreen) pop()
}

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
 * A conversation (Messages tab): one row per message, latest first, a touch
 * reads it aloud (card « Android Auto : une conversation montre la liste de
 * ses messages », validated on 8 Nov 2026 after a mock-up); first row
 * « Lire les nouveaux messages » when some were unread; « Répondre »
 * (dictated answer, lot 1b) and « Messages types » at the top. Opening it
 * marks it as read, as on the phone.
 */
internal class ConversationScreen(
    carContext: CarContext,
    private val session: SarcadeSession,
    private val key: String,
) : LiveScreen(carContext) {
    /** Unread when the screen opened: the screen marks them read at once,
     *  « Lire les nouveaux messages » keeps them for its touch. */
    private val newCount: Int
    private val newSpeech: String

    init {
        val opened = snap.item("messages", key)
        newCount = opened?.optInt("unread", 0) ?: 0
        newSpeech = opened?.optString("speakUnread").orEmpty()
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
        val items = ItemList.Builder()
        var room = CarUi.listLimit(carContext)
        if (newCount > 0 && newSpeech.isNotEmpty()) {
            items.addItem(
                Row.Builder().setTitle(s.label("readNew"))
                    .addText(CarUi.unreadText(s, newCount))
                    .setImage(CarUi.icon(carContext, R.drawable.sarcade_car_volume_up))
                    .setOnClickListener { session.speaker().say(newSpeech, s.lang) }
                    .build()
            )
            room--
        }
        val lines = c.optJSONArray("lines")
        if (lines == null || lines.length() == 0) {
            // Data of an older application: the summary in one row.
            items.addItem(
                Row.Builder().setTitle(c.optString("title"))
                    .addText(c.optString("text"))
                    .setOnClickListener { session.speaker().say(c.optString("speak"), s.lang) }
                    .build()
            )
        } else {
            for (n in 0 until minOf(lines.length(), room.coerceAtLeast(1))) {
                val l = lines.getJSONObject(n)
                items.addItem(
                    Row.Builder().setTitle(l.optString("title"))
                        .addText(CarUi.withPriority(l.optString("prioLabel"), l.optString("prio"), l.optString("text")))
                        .setOnClickListener { session.speaker().say(l.optString("speak"), s.lang) }
                        .build()
                )
            }
        }
        val b = ListTemplate.Builder().setSingleList(items.build())
            .setTitle(c.optString("title"))
            .setHeaderAction(Action.BACK)
        if (c.optBoolean("canReply", false)) {
            val strip = ActionStrip.Builder().addAction(
                Action.Builder().setTitle(s.label("reply"))
                    .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_mic))
                    .setOnClickListener { screenManager.push(ReplyScreen(carContext, key, c.optString("replyTo"))) }
                    .build()
            )
            // Lot 24 (card « messages types en un appui »): the icon alone,
            // one titled button in the strip.
            if (s.items("quick").isNotEmpty()) {
                strip.addAction(QuickScreen.action(carContext, s, false) { screenManager.push(QuickScreen(carContext, conversation = key)) })
            }
            b.setActionStrip(strip.build())
        }
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
                            // An answer to a conversation or to an order: back to the
                            // list of the tab (8 Nov 2026); a new message: one screen back.
                            if (mode == WRITE) screenManager.pop() else screenManager.backToList()
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
        // Lot 24 (card « statut en un appui », choice 2): his status.
        listOf(t.optString("status"), t.optString("battery")).filter { it.isNotEmpty() }
            .takeIf { it.isNotEmpty() }?.let { first.addText(it.joinToString(" · ")) }
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
    init {
        // Lot 24: weather at the destination, fetched by the application.
        snap.item("orders", id)?.let { o -> CarUi.post(carContext, "weather") { put("lat", o.optDouble("lat")); put("lon", o.optDouble("lon")) } }
    }

    override fun watched(s: Snapshot): String = "${s.lang}|${s.item("orders", id)}|${s.item("orders", id)?.let { s.weather(it) }}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val o = s.item("orders", id) ?: return gone()
        val pane = Pane.Builder()
            .addRow(Row.Builder().setTitle(o.optString("title")).addText(o.optString("text")).build())
        val note = o.optString("note")
        if (note.isNotEmpty()) pane.addRow(Row.Builder().setTitle(s.label("note")).addText(note).build())
        CarUi.weatherRows(carContext, s.weather(o)).forEach { pane.addRow(it) }
        val card = orderCard(carContext, s, o) { screenManager.push(ReplyScreen(carContext, id, o.optString("from"), ReplyScreen.PCO)) }
        // Lot 24 (card « messages types en un appui », choice 1): quick
        // messages to the PCO, in the strip (the only titled button there
        // when there is none, otherwise an icon).
        val quick = if (s.items("quick").isEmpty()) null
            else QuickScreen.action(carContext, s, card.strip.isEmpty()) { screenManager.push(QuickScreen(carContext, order = id)) }
        card.body.forEach { pane.addAction(it) }
        val t = PaneTemplate.Builder(pane.build())
            .setTitle(s.label("order"))
            .setHeaderAction(Action.BACK)
        val top = card.strip + listOfNotNull(quick)
        if (top.isNotEmpty()) {
            val strip = ActionStrip.Builder()
            top.forEach { strip.addAction(it) }
            t.setActionStrip(strip.build())
        }
        return t.build()
    }

    /** Buttons of the card of an order: [body] (2 at most, the main one
     *  last) and [strip] (action strip at the top, one titled button). */
    class Card(val body: List<Action>, val strip: List<Action>)

    companion object {
        /** « Terminé, disponible » (lot 27): the order stays arrived, the
         *  server sets « Disponible ». */
        fun finish(context: CarContext, s: Snapshot, o: JSONObject): Action =
            Action.Builder().setTitle(s.label("finish")).setFlags(Action.FLAG_PRIMARY)
                .setIcon(CarUi.icon(context, R.drawable.sarcade_car_check))
                .setOnClickListener {
                    CarUi.post(context, "order") { put("id", o.optString("id")); put("status", "finished") }
                    CarUi.toast(context, s.label("sent"))
                }.build()

        fun orderCard(context: CarContext, s: Snapshot, o: JSONObject, writePco: () -> Unit): Card {
            fun write(title: String) = Action.Builder().setTitle(s.label(title))
                .setIcon(CarUi.icon(context, R.drawable.sarcade_car_mic))
                .setOnClickListener { writePco() }.build()
            val go = Action.Builder().setTitle(s.label("go")).setFlags(Action.FLAG_PRIMARY)
                .setIcon(CarUi.icon(context, R.drawable.sarcade_car_directions))
                .setOnClickListener { MainScreen.goToOrder(context, s, o) }
                .build()
            val answers = MainScreen.orderActions(context, s, o)
            return when (o.optString("status")) {
                // Refuser, Accepter; « Écrire au PCO » at the top.
                "sent" -> Card(answers, listOf(write("writePco")))
                // Écrire, Y aller; « Je suis arrivé » at the top.
                "accepted" -> Card(listOf(write("write"), go), answers.take(1))
                // Lot 27: arrived, mission not finished: Écrire au PCO,
                // « Terminé, disponible » (main button, in place of Y aller:
                // the driver is there; 2 buttons at most in a card).
                "arrived" -> if (o.optBoolean("finished")) Card(listOf(write("writePco"), go), emptyList())
                    else Card(listOf(write("writePco"), finish(context, s, o)), emptyList())
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
    init {
        // Lot 24: weather at the point, fetched by the application.
        snap.item("points", id)?.let { p -> CarUi.post(carContext, "weather") { put("lat", p.optDouble("lat")); put("lon", p.optDouble("lon")) } }
    }

    override fun watched(s: Snapshot): String = "${s.lang}|${s.item("points", id)}|${s.item("points", id)?.let { s.weather(it) }}"

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
        CarUi.weatherRows(carContext, s.weather(p)).forEach { pane.addRow(it) }
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
 * Quick messages in one touch (lot 24, card « Android Auto : messages types
 * en un appui »): the list of the event (4 at most, set by the PCO),
 * « Besoin d'aide » urgent; one touch sends it, in the [conversation] (to
 * whom « Répondre » answers) or from the card of an [order] (to the PCO).
 */
internal class QuickScreen(
    carContext: CarContext,
    private val conversation: String? = null,
    private val order: String? = null,
) : LiveScreen(carContext) {
    override fun watched(s: Snapshot): String = "${s.lang}|${s.items("quick")}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val items = ItemList.Builder()
        for (q in s.items("quick").take(4)) {
            val text = q.optString("text")
            val priority = q.optString("priority", "routine")
            // The title of a row takes no colour: « URGENT » in red below it.
            val row = Row.Builder().setTitle(text)
            CarUi.priorityLabel(q.optString("prioLabel"), priority)?.let { row.addText(it) }
            items.addItem(
                row
                    .setOnClickListener {
                        CarUi.post(carContext, "quick") {
                            put("text", text); put("priority", priority)
                            conversation?.let { put("conversation", it) }
                            order?.let { put("order", it) }
                        }
                        CarUi.toast(carContext, s.label("sent"))
                        screenManager.backToList()
                    }
                    .build()
            )
        }
        return ListTemplate.Builder().setSingleList(items.build())
            .setTitle(s.label("quick"))
            .setHeaderAction(Action.BACK)
            .build()
    }

    companion object {
        /** « Messages types » button: titled, or the icon alone ([titled]
         *  false: the strip takes one titled button only). */
        fun action(context: CarContext, s: Snapshot, titled: Boolean, onClick: () -> Unit): Action {
            val b = Action.Builder().setIcon(CarUi.icon(context, R.drawable.sarcade_car_chat)).setOnClickListener { onClick() }
            if (titled) b.setTitle(s.label("quick"))
            return b.build()
        }
    }
}

/**
 * Status in one touch (lot 24, card « Android Auto : statut en un appui »,
 * choices 1 to 3): grid of 4 squares En route, Sur place, Disponible,
 * Pause, and « Aucun statut » (lot 27); one touch sends it to the PCO; it
 * stays until the next one.
 */
internal class StatusScreen(carContext: CarContext) : LiveScreen(carContext) {
    override fun watched(s: Snapshot): String = "${s.lang}|${s.myStatus}"

    override fun onGetTemplate(): Template {
        val s = snap
        drawn(s)
        val items = ItemList.Builder()
        for (status in CarUi.STATUSES) {
            val b = GridItem.Builder().setTitle(s.label("status.$status"))
                .setImage(CarUi.tile(carContext, CarUi.statusIcon(status), CarUi.statusColor(status)), GridItem.IMAGE_TYPE_LARGE)
                .setOnClickListener {
                    CarUi.post(carContext, "status") { put("status", status) }
                    CarUi.toast(carContext, s.label("statusSent"))
                    screenManager.pop()
                }
            if (status == s.myStatus) b.setText(s.label("statusCurrent"))
            items.addItem(b.build())
        }
        // Lot 27 (card « Disponible » par défaut, choice 3): « Aucun statut »
        // stays a choice, for who does not want to show one.
        val none = GridItem.Builder().setTitle(s.label("noStatus"))
            .setImage(CarUi.tile(carContext, CarUi.statusIcon(null), CarUi.statusColor(null)), GridItem.IMAGE_TYPE_LARGE)
            .setOnClickListener {
                CarUi.post(carContext, "status") { put("status", "") }
                CarUi.toast(carContext, s.label("statusSent"))
                screenManager.pop()
            }
        if (s.myStatus == null) none.setText(s.label("statusCurrent"))
        items.addItem(none.build())
        return GridTemplate.Builder().setSingleList(items.build())
            .setTitle(s.label("myStatus"))
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
