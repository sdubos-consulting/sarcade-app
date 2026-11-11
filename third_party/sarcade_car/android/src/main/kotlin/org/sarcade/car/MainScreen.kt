package org.sarcade.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarText
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Tab
import androidx.car.app.model.TabContents
import androidx.car.app.model.TabTemplate
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import org.json.JSONObject

/**
 * Main car screen (card « Voiture : vraie interface SARCADE avec onglets »,
 * choices of 1 Nov 2026, 11 h 00): tabs Messages, Ordres, Points, Équipe;
 * SOS always there. No map, no typing.
 *
 * - car API level 6 and more: TabTemplate, each tab a list with the red
 *   SOS round button; rows with their buttons (2 from level 8, 1 before);
 * - older hosts: a list per section with an action strip « Rubriques » and
 *   « SOS ».
 *
 * Lot 23 tried the second layout everywhere (CarUi.SOS_IN_STRIP); lot 24
 * (card « Android Auto : retour aux onglets, SOS en bouton rond »): back to
 * the tabs, « SOS » white in the round button.
 */
internal class MainScreen(carContext: CarContext, private val session: SarcadeSession) : Screen(carContext) {
    /** Tab shown (internal: the tests of the car screens choose it). */
    internal var tab = MESSAGES

    /** SOS in the top strip, one section at a time (CarUi.SOS_IN_STRIP,
     *  false again since lot 24); internal: the tests of the car screens
     *  also draw the layout of lot 23. */
    internal var sosInStrip = CarUi.SOS_IN_STRIP

    /** What the shown tab displayed when last drawn (lot 20, choices 4 and
     *  5): new data that do not change it are not drawn again, so the car
     *  neither flickers nor moves the list. */
    private var shown: String? = null
    private val refresh: () -> Unit = {
        if (Snapshot(CarData.snapshot(carContext)).signature(tab) != shown) invalidate()
    }

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                CarData.addListener(refresh)
            }

            override fun onDestroy(owner: LifecycleOwner) {
                CarData.removeListener(refresh)
            }
        })
    }

    private val level: Int get() = carContext.carAppApiLevel

    override fun onGetTemplate(): Template {
        val snap = Snapshot(CarData.snapshot(carContext))
        shown = snap.signature(tab)
        if (!snap.ready) {
            return MessageTemplate.Builder(carContext.getString(R.string.sarcade_car_open_phone))
                .setTitle("SARCADE")
                .setHeaderAction(Action.APP_ICON)
                .build()
        }
        // Tabs with the round SOS button (lot 24); the action strip with one
        // section at a time on the older hosts (and with CarUi.SOS_IN_STRIP).
        return if (level >= TABS_LEVEL && !sosInStrip) tabs(snap) else sections(snap)
    }

    // --- Tabs (car API 6+) ---------------------------------------------------

    private fun tabs(snap: Snapshot): Template {
        val b = TabTemplate.Builder(object : TabTemplate.TabCallback {
            override fun onTabSelected(tabContentId: String) {
                tab = tabContentId
                invalidate()
            }
        }).setHeaderAction(Action.APP_ICON)
        // Titles and icons never change: a new tab content is a refresh, not
        // a new step of the car (limit of 5 steps).
        for (id in TABS) {
            b.addTab(
                Tab.Builder().setTitle(snap.label("tab.$id")).setContentId(id)
                    .setIcon(CarUi.icon(carContext, tabIcon(id))).build()
            )
        }
        val list = ListTemplate.Builder().setSingleList(rows(snap, tab))
            .addAction(CarUi.sosAction(carContext, snap, floating = true) { openSos() })
            .build()
        return b.setTabContents(TabContents.Builder(list).build()).setActiveTabContentId(tab).build()
    }

    // --- Older hosts: one section at a time, action strip --------------------

    private fun sections(snap: Snapshot): Template {
        val strip = ActionStrip.Builder()
            .addAction(
                Action.Builder().setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_menu))
                    .setOnClickListener { screenManager.push(SectionsScreen(carContext, snap) { tab = it; invalidate() }) }
                    .build()
            )
            .addAction(CarUi.sosAction(carContext, snap, floating = false) { openSos() })
            .build()
        return ListTemplate.Builder().setSingleList(rows(snap, tab))
            .setTitle(snap.label("tab.$tab"))
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(strip)
            .build()
    }

    // --- Rows of a tab ---------------------------------------------------------

    private fun rows(snap: Snapshot, id: String): ItemList {
        val items = ItemList.Builder()
        val limit = CarUi.listLimit(carContext)
        val all = mutableListOf<Row>()
        snap.staleText()?.let { all.add(Row.Builder().setTitle(it).build()) }
        when (id) {
            MESSAGES -> snap.items("messages").forEach { all.add(conversationRow(snap, it)) }
            ORDERS -> snap.items("orders").forEach { all.add(orderRow(snap, it)) }
            POINTS -> {
                // Lot 24 (card « Signal entendu ici »): first row during a
                // SATER event.
                heardRow(snap)?.let { all.add(it) }
                snap.items("points").forEach { all.add(pointRow(snap, it)) }
            }
            else -> {
                // Lot 24 (card « statut en un appui », choice 1): « Mon
                // statut » first; « Personne d'autre en ligne » kept below.
                all.add(myStatusRow(snap))
                val team = snap.items("team")
                team.forEach { all.add(teammateRow(snap, it)) }
                if (team.isEmpty()) all.add(Row.Builder().setTitle(snap.label("empty.$id")).build())
            }
        }
        // Lot 24 (card « télécommandes de relais depuis la voiture », choice
        // 1): « Télécommandes » at the bottom of Points, always shown.
        val remotes = if (id == POINTS && snap.items("remotes").isNotEmpty())
            RemotesScreen.row(carContext, snap) { screenManager.push(RemotesScreen(carContext)) } else null
        val shownRows = if (remotes == null) all.take(limit) else all.take((limit - 1).coerceAtLeast(0)) + remotes
        shownRows.forEach { items.addItem(it) }
        if (shownRows.isEmpty()) items.setNoItemsMessage(snap.label("empty.$id"))
        return items.build()
    }

    private fun conversationRow(snap: Snapshot, c: JSONObject): Row {
        val b = Row.Builder()
            .setTitle(c.optString("title"))
            .addText(CarUi.withPriority(c.optString("prioLabel"), c.optString("prio"), c.optString("text")))
            .setImage(CarUi.tile(carContext, CarUi.operatorIcon(c.optString("icon")), c.optInt("color", DEFAULT_COLOR)))
            .setOnClickListener { screenManager.push(ConversationScreen(carContext, session, c.optString("id"))) }
        val unread = c.optInt("unread", 0)
        if (unread > 0 && level >= TABS_LEVEL) b.setNumericDecoration(unread)
        return b.build()
    }

    private fun orderRow(snap: Snapshot, o: JSONObject): Row {
        val id = o.optString("id")
        val b = Row.Builder()
            .setTitle(o.optString("title"))
            .addText(o.optString("text"))
            .setImage(CarUi.tile(carContext, R.drawable.sarcade_car_flag, o.optInt("color", DEFAULT_COLOR)))
            .setOnClickListener { screenManager.push(OrderScreen(carContext, id)) }
        if (level >= TABS_LEVEL) {
            // Two buttons from the car API level 8 (one before): the main
            // one stays, the other is on the order screen.
            val actions = orderActions(carContext, snap, o)
            val shown = if (level >= TWO_ROW_ACTIONS_LEVEL) actions else actions.takeLast(1)
            shown.forEach { b.addAction(it) }
        }
        return b.build()
    }

    /** Lot 24 (card « fiches dans les onglets Points et Ordres », choice
     *  1): touching the row opens the card of the point; the arrow keeps
     *  the direct navigation. */
    private fun pointRow(snap: Snapshot, p: JSONObject): Row {
        val go = { CarUi.navigate(carContext, snap, p.optDouble("lat"), p.optDouble("lon")) }
        val id = p.optString("id")
        val b = Row.Builder()
            .setTitle(p.optString("title"))
            .addText(p.optString("text"))
            .setImage(CarUi.tile(carContext, CarUi.pointIcon(p.optString("icon")), p.optInt("color", DEFAULT_COLOR)))
            .setOnClickListener { screenManager.push(PointScreen(carContext, id)) }
        if (level >= TABS_LEVEL) {
            // Lot 20 (card « boutons ronds gris vides », choice 1): the car
            // only shows the icon of a row button, so it must have one.
            b.addAction(
                Action.Builder().setTitle(CarUi.navigateTitle(carContext, snap))
                    .setIcon(CarUi.icon(carContext, R.drawable.sarcade_car_directions))
                    .setFlags(Action.FLAG_PRIMARY).setOnClickListener { go() }.build()
            )
        }
        return b.build()
    }

    /** Lot 23 (card « Android Auto, onglet Équipe : naviguer vers un
     *  opérateur »): the itinerary arrow on the right, as in Points, guides
     *  Maps or Waze to the last known position of the operator, read when
     *  touched (the person moves: touching again updates the destination;
     *  the screen is not drawn again for a move, see [Snapshot.signature]).
     *  No position, no arrow.
     *
     *  Lot 24 (card « Android Auto, onglet Équipe : fiche d'un opérateur
     *  avec actions », choice 1): touching the row opens the card of the
     *  operator; only the arrow navigates directly. */
    private fun teammateRow(snap: Snapshot, t: JSONObject): Row {
        val id = t.optString("id")
        val b = Row.Builder()
            .setTitle(t.optString("title"))
            .addText(t.optString("text"))
            .setImage(CarUi.tile(carContext, CarUi.operatorIcon(t.optString("icon")), t.optInt("color", DEFAULT_COLOR)))
            .setOnClickListener { screenManager.push(TeammateScreen(carContext, id)) }
        if (hasPosition(t) && level >= TABS_LEVEL) b.addAction(goToTeammate(carContext, snap, id, t))
        return b.build()
    }

    private fun heardRow(snap: Snapshot): Row? {
        val sater = snap.sater ?: return null
        val ready = sater.optBoolean("ready", false)
        return Row.Builder().setTitle(snap.label("heard"))
            .addText(snap.label(if (ready) "heardHelp" else "noPosition"))
            .setImage(CarUi.tile(carContext, R.drawable.sarcade_car_cell_tower, HeardAlert.COLOR))
            .setOnClickListener {
                if (ready) HeardAlert.send(carContext, Snapshot(CarData.snapshot(carContext)))
                else CarUi.toast(carContext, snap.label("noPosition"))
            }
            .build()
    }

    /** « Mon statut : Disponible » on one line, lower than a row of two
     *  (card « Android Auto, onglet Équipe : Mon statut sur une seule
     *  ligne », validated on 8 Nov 2026, choice 1). */
    private fun myStatusRow(snap: Snapshot): Row {
        val status = snap.myStatus
        return Row.Builder().setTitle(myStatusLine(snap, status))
            .setImage(CarUi.tile(carContext, CarUi.statusIcon(status), CarUi.statusColor(status)))
            .setOnClickListener { screenManager.push(StatusScreen(carContext)) }
            .build()
    }

    private fun myStatusLine(snap: Snapshot, status: String?): String {
        val value = status?.let { snap.label("status.$it") } ?: snap.label("statusNone")
        val line = snap.label("myStatusLine")
        // Labels of an older application: the two texts side by side.
        return if (line.contains("{s}")) line.replace("{s}", value) else "${snap.label("myStatus")} : $value"
    }

    private fun openSos() {
        screenManager.push(SosScreen(carContext))
    }

    companion object {
        const val MESSAGES = "messages"
        const val ORDERS = "orders"
        const val POINTS = "points"
        const val TEAM = "team"
        val TABS = listOf(MESSAGES, ORDERS, POINTS, TEAM)
        const val DEFAULT_COLOR = 0xFF1E88E5.toInt()
        /** Car API level of TabTemplate, row buttons, floating buttons. */
        const val TABS_LEVEL = 6
        /** Car API level from which a row shows 2 buttons (1 before). */
        const val TWO_ROW_ACTIONS_LEVEL = 8

        /** « Naviguer » towards operator [id]: his last known position,
         *  read when touched ([fallback]: the one drawn). */
        fun goToTeammate(context: CarContext, snap: Snapshot, id: String, fallback: JSONObject, title: CarText? = null): Action {
            val go = {
                val now = Snapshot(CarData.snapshot(context))
                val last = now.item("team", id)?.takeIf { hasPosition(it) } ?: fallback
                CarUi.navigate(context, now, last.optDouble("lat"), last.optDouble("lon"))
            }
            return Action.Builder().setTitle(title ?: CarUi.navigateTitle(context, snap))
                .setIcon(CarUi.icon(context, R.drawable.sarcade_car_directions))
                .setFlags(Action.FLAG_PRIMARY).setOnClickListener { go() }.build()
        }

        /** An operator with a known position (lot 23, choice 4). */
        fun hasPosition(t: JSONObject): Boolean =
            t.has("lat") && t.has("lon") && !t.optDouble("lat").isNaN() && !t.optDouble("lon").isNaN()

        fun tabIcon(id: String): Int = when (id) {
            MESSAGES -> R.drawable.sarcade_car_chat
            ORDERS -> R.drawable.sarcade_car_flag
            POINTS -> R.drawable.sarcade_car_place
            else -> R.drawable.sarcade_car_groups
        }

        /** « Y aller » towards the point of an order: the navigation of the
         *  car, and the application follows the estimated time of arrival
         *  (lot 24, card « heure d'arrivée estimée envoyée au PCO »). */
        fun goToOrder(context: CarContext, snap: Snapshot, o: JSONObject) {
            CarUi.post(context, "go") { put("id", o.optString("id")) }
            CarUi.navigate(context, snap, o.optDouble("lat"), o.optDouble("lon"))
        }

        /** Buttons of an order, the main one last: Refuser, Accepter while
         *  sent; Je suis arrivé, Naviguer once accepted; nothing after. */
        fun orderActions(context: CarContext, snap: Snapshot, o: JSONObject): List<Action> {
            val id = o.optString("id")
            // Each button with its icon (lot 20): the rows of the car only
            // show the icon of their buttons.
            fun answer(status: String, label: String, icon: Int, primary: Boolean): Action {
                val b = Action.Builder().setTitle(snap.label(label))
                    .setIcon(CarUi.icon(context, icon)).setOnClickListener {
                    CarUi.post(context, "order") { put("id", id); put("status", status) }
                    CarUi.toast(context, snap.label("sent"))
                }
                if (primary) b.setFlags(Action.FLAG_PRIMARY)
                return b.build()
            }
            return when (o.optString("status")) {
                "sent" -> listOf(
                    answer("refused", "refuse", R.drawable.sarcade_car_close, false),
                    answer("accepted", "accept", R.drawable.sarcade_car_check, true),
                )
                "accepted" -> listOf(
                    answer("arrived", "arrived", R.drawable.sarcade_car_flag, false),
                    Action.Builder().setTitle(CarUi.navigateTitle(context, snap)).setFlags(Action.FLAG_PRIMARY)
                        .setIcon(CarUi.icon(context, R.drawable.sarcade_car_directions))
                        .setOnClickListener { goToOrder(context, snap, o) }
                        .build(),
                )
                else -> emptyList()
            }
        }
    }
}

/** Older hosts: choice of the section (Messages, Ordres, Points, Équipe). */
internal class SectionsScreen(
    carContext: CarContext,
    private val snap: Snapshot,
    private val onPick: (String) -> Unit,
) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val items = ItemList.Builder()
        for (id in MainScreen.TABS) {
            items.addItem(
                Row.Builder().setTitle(snap.label("tab.$id"))
                    .setImage(CarUi.icon(carContext, MainScreen.tabIcon(id), CarColor.DEFAULT))
                    .setOnClickListener { onPick(id); screenManager.pop() }
                    .build()
            )
        }
        return ListTemplate.Builder().setSingleList(items.build())
            .setTitle(snap.label("sections"))
            .setHeaderAction(Action.BACK)
            .build()
    }
}
