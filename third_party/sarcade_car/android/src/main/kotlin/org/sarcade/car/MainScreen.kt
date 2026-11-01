package org.sarcade.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
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
 */
internal class MainScreen(carContext: CarContext, private val session: SarcadeSession) : Screen(carContext) {
    private var tab = MESSAGES
    private val refresh: () -> Unit = { invalidate() }

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
        if (!snap.ready) {
            return MessageTemplate.Builder(carContext.getString(R.string.sarcade_car_open_phone))
                .setTitle("SARCADE")
                .setHeaderAction(Action.APP_ICON)
                .build()
        }
        return if (level >= TABS_LEVEL) tabs(snap) else sections(snap)
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
            POINTS -> snap.items("points").forEach { all.add(pointRow(snap, it)) }
            else -> snap.items("team").forEach { all.add(teammateRow(it)) }
        }
        all.take(limit).forEach { items.addItem(it) }
        if (all.isEmpty()) items.setNoItemsMessage(snap.label("empty.$id"))
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

    private fun pointRow(snap: Snapshot, p: JSONObject): Row {
        val go = { CarUi.navigate(carContext, snap, p.optDouble("lat"), p.optDouble("lon"), p.optString("title")) }
        val b = Row.Builder()
            .setTitle(p.optString("title"))
            .addText(p.optString("text"))
            .setImage(CarUi.tile(carContext, CarUi.pointIcon(p.optString("icon")), p.optInt("color", DEFAULT_COLOR)))
            .setOnClickListener { go() }
        if (level >= TABS_LEVEL) {
            b.addAction(Action.Builder().setTitle(CarUi.navigateTitle(carContext, snap)).setFlags(Action.FLAG_PRIMARY).setOnClickListener { go() }.build())
        }
        return b.build()
    }

    private fun teammateRow(t: JSONObject): Row = Row.Builder()
        .setTitle(t.optString("title"))
        .addText(t.optString("text"))
        .setImage(CarUi.tile(carContext, CarUi.operatorIcon(t.optString("icon")), t.optInt("color", DEFAULT_COLOR)))
        .build()

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

        fun tabIcon(id: String): Int = when (id) {
            MESSAGES -> R.drawable.sarcade_car_chat
            ORDERS -> R.drawable.sarcade_car_flag
            POINTS -> R.drawable.sarcade_car_place
            else -> R.drawable.sarcade_car_groups
        }

        /** Buttons of an order, the main one last: Refuser, Accepter while
         *  sent; Je suis arrivé, Naviguer once accepted; nothing after. */
        fun orderActions(context: CarContext, snap: Snapshot, o: JSONObject): List<Action> {
            val id = o.optString("id")
            fun answer(status: String, label: String, primary: Boolean): Action {
                val b = Action.Builder().setTitle(snap.label(label)).setOnClickListener {
                    CarUi.post(context, "order") { put("id", id); put("status", status) }
                    CarUi.toast(context, snap.label("sent"))
                }
                if (primary) b.setFlags(Action.FLAG_PRIMARY)
                return b.build()
            }
            return when (o.optString("status")) {
                "sent" -> listOf(answer("refused", "refuse", false), answer("accepted", "accept", true))
                "accepted" -> listOf(
                    answer("arrived", "arrived", false),
                    Action.Builder().setTitle(CarUi.navigateTitle(context, snap)).setFlags(Action.FLAG_PRIMARY)
                        .setOnClickListener { CarUi.navigate(context, snap, o.optDouble("lat"), o.optDouble("lon"), o.optString("title")) }
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
