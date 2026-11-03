package org.sarcade.car

import android.content.Context
import android.os.Looper
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.HandshakeInfo
import androidx.car.app.OnDoneCallback
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.TabTemplate
import androidx.car.app.testing.TestAppManager
import androidx.car.app.testing.TestCarContext
import androidx.car.app.testing.TestScreenManager
import androidx.test.core.app.ApplicationProvider
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Car screens of SARCADE without a car (lot 20, card « Android Auto : ordres
 * de déplacement peu utilisables… », choice 4), with the test library of
 * the Car App Library (androidx.car.app:app-testing) on Robolectric: what
 * the tabs, the buttons, the SOS and the order alert give to Android Auto,
 * and the navigation intent. The data are those the application writes
 * (lib/src/features/car/car_screen.dart).
 *
 * Run by the CI (job android-build): ./gradlew :sarcade_car:test
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CarScreensTest {
    private lateinit var app: Context
    private lateinit var car: TestCarContext

    private fun order(id: String, status: String) = JSONObject()
        .put("id", id).put("title", "Point de la carte").put("status", status)
        .put("text", "PCO-iphone-apps · envoyé · 3 km au nord-ouest").put("note", "")
        .put("from", "PCO-iphone-apps").put("away", "3 km NO")
        .put("lat", 48.8191).put("lon", 1.921).put("color", 0xFFFF5722.toInt())

    private fun mate(id: String, text: String, lat: Double? = 48.83) = JSONObject()
        .put("id", id).put("title", id).put("icon", "car").put("color", 0xFF43A047.toInt()).put("text", text)
        .apply { if (lat != null) put("lat", lat).put("lon", 1.95) }

    private fun snapshot(
        orders: JSONArray = JSONArray().put(order("o1", "sent")),
        at: Long = System.currentTimeMillis(),
        team: JSONArray = JSONArray(),
    ): JSONObject {
        val labels = JSONObject()
        mapOf(
            "tab.messages" to "Messages", "tab.orders" to "Ordres", "tab.points" to "Points", "tab.team" to "Équipe",
            "empty.messages" to "Aucun message", "empty.orders" to "Aucun ordre", "empty.points" to "Aucun point",
            "empty.team" to "Personne", "sos" to "SOS", "navigateCar" to "Naviguer (application de la voiture)",
            "navigateCarShort" to "Naviguer · voiture", "navigateFailed" to "Navigation impossible : installez Google Maps ou Waze sur le téléphone",
            "accept" to "Accepter", "refuse" to "Refuser", "arrived" to "Je suis arrivé", "sent" to "Envoyé",
            "go" to "Y aller", "view" to "Voir", "orderAlert" to "Ordre de déplacement", "order" to "Ordre",
            "note" to "Consigne", "gone" to "Plus disponible", "stale" to "Données de {time}",
            "operator" to "Opérateur", "write" to "Écrire", "writeTo" to "Message à {who}",
            "lastMessage" to "Dernier message", "noPosition" to "Position inconnue",
            "point" to "Point", "onSite" to "Je suis sur place", "writePco" to "Écrire au PCO", "pcoTitle" to "Message au PCO",
            "myStatus" to "Mon statut", "noStatus" to "Aucun statut", "statusSent" to "Statut envoyé", "statusCurrent" to "Actuel",
            "status.en_route" to "En route", "status.sur_place" to "Sur place", "status.disponible" to "Disponible",
            "status.pause" to "Pause", "arrivalTitle" to "Vous êtes arrivé à {point}", "arrivalAsk" to "Signaler l’arrivée ?",
            "yes" to "Oui", "later" to "Plus tard",
        ).forEach { (k, v) -> labels.put(k, v) }
        val points = JSONArray()
            .put(JSONObject().put("id", "poi1").put("kind", "poi").put("icon", "gathering").put("color", 0xFF1E88E5.toInt())
                .put("title", "PC").put("text", "3 km NO").put("lat", 48.8191).put("lon", 1.921))
            .put(JSONObject().put("id", "h1").put("kind", "high").put("icon", "high").put("color", 0xFF6D4C41.toInt())
                .put("title", "Butte").put("text", "3 km NE · Point haut · 412 m").put("lat", 48.8191).put("lon", 1.979))
        return JSONObject().put("v", 1).put("at", at).put("lang", "fr").put("distress", false)
            .put("labels", labels).put("messages", JSONArray()).put("orders", orders)
            .put("points", points).put("team", team)
    }

    private fun write(json: JSONObject) {
        CarData.update(app, json.toString())
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext()
        app.getSharedPreferences("sarcade_car_screen", Context.MODE_PRIVATE).edit().clear().commit()
        car = TestCarContext.createCarContext(app)
        // Android Auto of the owner's car: car API level 8 (tabs, 2 row buttons).
        car.updateHandshakeInfo(HandshakeInfo("com.google.android.projection.gearhead", 8))
        write(snapshot())
    }

    /** List of a tab, in the layout in force (tabs again since lot 24) or
     *  one section at a time as in lot 23 ([inStrip] true). */
    private fun tab(id: String, inStrip: Boolean = CarUi.SOS_IN_STRIP): ListTemplate {
        val screen = MainScreen(car, SarcadeSession())
        screen.sosInStrip = inStrip
        screen.tab = id
        val t = screen.onGetTemplate()
        return if (t is TabTemplate) t.tabContents.template as ListTemplate else t as ListTemplate
    }

    private fun rows(list: ListTemplate): List<Row> = list.singleList!!.items.map { it as Row }

    private fun click(action: Action) {
        action.onClickDelegate!!.sendClick(object : OnDoneCallback {})
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun pointsTab_eachRowHasTheItineraryIcon_andAShortLine() {
        val r = rows(tab(MainScreen.POINTS))
        assertEquals(listOf("PC", "Butte"), r.map { it.title.toString() })
        assertEquals("3 km NO", r[0].texts[0].toString())
        for (row in r) {
            val go = row.actions.single()
            assertNotNull("round button without icon (grey disc)", go.icon)
        }
    }

    @Test
    fun ordersTab_rowButtonsHaveIcons() {
        val r = rows(tab(MainScreen.ORDERS))
        assertEquals("Point de la carte", r.single().title.toString())
        val actions = r.single().actions
        assertEquals(2, actions.size)
        actions.forEach { assertNotNull(it.icon) }
        write(snapshot(JSONArray().put(order("o1", "accepted"))))
        rows(tab(MainScreen.ORDERS)).single().actions.forEach { assertNotNull(it.icon) }
    }

    @Test
    fun ordersTab_emptyMessage() {
        write(snapshot(JSONArray()))
        assertEquals("Aucun ordre", tab(MainScreen.ORDERS).singleList!!.noItemsMessage.toString())
    }

    @Test
    fun tabs_withTheRoundSosButton_whiteOnTheColourOfAndroidAuto() {
        // Lot 24 (card « Android Auto : retour aux onglets, SOS en bouton
        // rond »): the car of the owner (API level 8) shows the tabs
        // Messages, Ordres, Points, Équipe again, the SOS in the round button.
        assertFalse(CarUi.SOS_IN_STRIP)
        val screen = MainScreen(car, SarcadeSession())
        val t = screen.onGetTemplate() as TabTemplate
        assertEquals(listOf("Messages", "Ordres", "Points", "Équipe"), t.tabs.map { it.title.toString() })
        assertEquals(MainScreen.TABS, t.tabs.map { it.contentId })
        for (id in MainScreen.TABS) {
            val sos = tab(id).actions.single()
            assertEquals(CarUi.SOS_WHITE, sos.icon!!.tint)
            assertTrue("a round button carries no title", sos.title == null)
            assertEquals(CarUi.SOS_BACKGROUND, sos.backgroundColor)
        }
    }

    @Test
    fun sosInTheTopStrip_layoutOfLot23_stillAccepted() {
        for (id in MainScreen.TABS) {
            val list = tab(id, inStrip = true)
            assertTrue("round button left in $id", list.actions.isEmpty())
            assertEquals(Snapshot(CarData.snapshot(car)).label("tab.$id"), list.title.toString())
            val strip = list.actionStrip!!.actions
            assertEquals(2, strip.size)
            assertEquals("SOS", strip[1].title.toString())
            assertEquals(CarColor.RED, strip[1].icon!!.tint)
        }
    }

    @Test
    fun sosInTheTopStrip_asOnOlderCars_isAccepted() {
        // Cars below API level 6: one section, « Rubriques » and « SOS » at
        // the top, whatever CarUi.SOS_IN_STRIP says.
        car.updateHandshakeInfo(HandshakeInfo("com.google.android.projection.gearhead", 5))
        val screen = MainScreen(car, SarcadeSession())
        screen.tab = MainScreen.ORDERS
        val list = screen.onGetTemplate() as ListTemplate
        val sos = list.actionStrip!!.actions[1]
        assertEquals("SOS", sos.title.toString())
        assertEquals(CarColor.RED, sos.icon!!.tint)
    }

    @Test
    fun pointRow_opensTheNavigationOfTheCar_towardsThePoint() {
        click(rows(tab(MainScreen.POINTS))[0].actions.single())
        val intent = car.startCarAppIntents.last()
        assertEquals(CarContext.ACTION_NAVIGATE, intent.action)
        assertEquals("geo:48.819100,1.921000", intent.dataString)
        // Lot 24: touching the row itself opens the card of the point.
        val before = car.startCarAppIntents.size
        rows(tab(MainScreen.POINTS))[1].onClickDelegate!!.sendClick(object : OnDoneCallback {})
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(before, car.startCarAppIntents.size)
        assertTrue(car.getCarService(TestScreenManager::class.java).screensPushed.last() is PointScreen)
    }

    @Test
    fun pointCard_typeDistanceAltitudeAuthor_onSiteAndGo() {
        // Lot 24 (card « fiches dans les onglets Points et Ordres », choice 1).
        val json = CarData.snapshot(car)
        json.getJSONArray("points").getJSONObject(1)
            .put("type", "Point haut").put("away", "3 km au nord-est").put("alt", "Altitude 412 m")
        json.getJSONArray("points").getJSONObject(0)
            .put("type", "Rassemblement").put("away", "3 km au nord-ouest").put("by", "Créé par PCO")
        write(json)
        val high = PointScreen(car, "h1").onGetTemplate() as PaneTemplate
        assertEquals("Butte", high.title.toString())
        assertEquals(listOf("Point haut", "3 km au nord-est"), high.pane.rows.map { it.title.toString() })
        assertEquals("Altitude 412 m", high.pane.rows[1].texts[0].toString())
        val poi = PointScreen(car, "poi1").onGetTemplate() as PaneTemplate
        assertEquals("Créé par PCO", poi.pane.rows[0].texts[0].toString())
        val actions = poi.pane.actions
        assertEquals(listOf("Je suis sur place", "Y aller"), actions.map { it.title.toString() })
        click(actions[1])
        assertEquals("geo:48.819100,1.921000", car.startCarAppIntents.last().dataString)
        click(actions[0])
        val sent = JSONArray(CarData.takeActions(app)).getJSONObject(0)
        assertEquals("onSite", sent.getString("type"))
        assertEquals("poi1", sent.getString("id"))
    }

    @Test
    fun orderCard_writeToThePco_answersWhileSent_arrivedKeptOnceAccepted() {
        // Lot 24 (card « fiches dans les onglets Points et Ordres », choice 2).
        val sent = OrderScreen(car, "o1").onGetTemplate() as PaneTemplate
        assertEquals(listOf("Refuser", "Accepter"), sent.pane.actions.map { it.title.toString() })
        assertEquals(listOf("Écrire au PCO"), sent.actionStrip!!.actions.map { it.title.toString() })
        write(snapshot(JSONArray().put(order("o1", "accepted"))))
        val accepted = OrderScreen(car, "o1").onGetTemplate() as PaneTemplate
        assertEquals(listOf("Écrire", "Y aller"), accepted.pane.actions.map { it.title.toString() })
        assertEquals(listOf("Je suis arrivé"), accepted.actionStrip!!.actions.map { it.title.toString() })
        click(accepted.actionStrip!!.actions[0])
        val answer = JSONArray(CarData.takeActions(app)).getJSONObject(0)
        assertEquals("order", answer.getString("type"))
        assertEquals("arrived", answer.getString("status"))
        click(accepted.pane.actions[0])
        assertTrue(car.getCarService(TestScreenManager::class.java).screensPushed.last() is ReplyScreen)
        write(snapshot(JSONArray().put(order("o1", "arrived"))))
        val arrived = OrderScreen(car, "o1").onGetTemplate() as PaneTemplate
        assertEquals(listOf("Écrire au PCO", "Y aller"), arrived.pane.actions.map { it.title.toString() })
        assertTrue(arrived.actionStrip == null)
    }

    @Test
    fun teamTab_arrowGuidesToTheLastPosition_rowOpensTheCard_noArrowWithoutPosition() {
        // Lot 23 (card « Android Auto, onglet Équipe : naviguer vers un
        // opérateur ») and lot 24 (card « fiche d'un opérateur avec
        // actions », choice 1: the row opens the card, the arrow navigates).
        write(snapshot(team = JSONArray()
            .put(mate("TEL-2", "3 km au nord · vu il y a moins de 5 min"))
            .put(mate("TEL-3", "position de 20 h 05", lat = null))))
        val all = rows(tab(MainScreen.TEAM))
        // Lot 24 (card « statut en un appui »): « Mon statut » first.
        assertEquals("Mon statut", all[0].title.toString())
        val r = all.drop(1)
        assertEquals(listOf("TEL-2", "TEL-3"), r.map { it.title.toString() })
        assertEquals("position de 20 h 05", r[1].texts[0].toString())
        val go = r[0].actions.single()
        assertNotNull(go.icon)
        click(go)
        assertEquals(CarContext.ACTION_NAVIGATE, car.startCarAppIntents.last().action)
        assertEquals("geo:48.830000,1.950000", car.startCarAppIntents.last().dataString)
        // No position: no arrow.
        assertTrue(r[1].actions.isEmpty())
        // The person moved: touching the arrow again, without a new drawing,
        // guides to the new position.
        write(snapshot(team = JSONArray().put(mate("TEL-2", "3 km au nord · vu il y a moins de 5 min", lat = 48.85))))
        click(go)
        assertEquals("geo:48.850000,1.950000", car.startCarAppIntents.last().dataString)
        // Touching the row opens the card, it does not navigate.
        val before = car.startCarAppIntents.size
        r[0].onClickDelegate!!.sendClick(object : OnDoneCallback {})
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(before, car.startCarAppIntents.size)
        assertTrue(car.getCarService(TestScreenManager::class.java).screensPushed.last() is TeammateScreen)
    }

    @Test
    fun teammateCard_nameRoleDistanceAgeBatteryLastMessage_goAndWrite() {
        write(snapshot(team = JSONArray()
            .put(mate("TEL-2", "3 km au nord · vu il y a moins de 5 min")
                .put("role", "Équipe 1 · F4ABC").put("away", "3 km au nord").put("seen", "vu il y a moins de 5 min")
                .put("battery", "Batterie 80 %").put("last", "20:05 · J'arrive"))
            .put(mate("TEL-3", "position de 20 h 05", lat = null).put("seen", "position de 20 h 05"))))
        val t = TeammateScreen(car, "TEL-2").onGetTemplate() as PaneTemplate
        assertEquals("TEL-2", t.title.toString())
        val r = t.pane.rows
        assertEquals(listOf("Équipe 1 · F4ABC", "3 km au nord", "Dernier message"), r.map { it.title.toString() })
        assertEquals("Batterie 80 %", r[0].texts[0].toString())
        assertEquals("vu il y a moins de 5 min", r[1].texts[0].toString())
        assertEquals("20:05 · J'arrive", r[2].texts[0].toString())
        // Two buttons at most: « Écrire », « Y aller » (main one).
        val actions = t.pane.actions
        assertEquals(listOf("Écrire", "Y aller"), actions.map { it.title.toString() })
        assertTrue(actions[1].flags and Action.FLAG_PRIMARY != 0)
        click(actions[1])
        assertEquals("geo:48.830000,1.950000", car.startCarAppIntents.last().dataString)
        // « Écrire »: dictation screen, the message goes to the operator.
        click(actions[0])
        assertTrue(car.getCarService(TestScreenManager::class.java).screensPushed.last() is ReplyScreen)
        // No position: « Position inconnue », no « Y aller ».
        val n = TeammateScreen(car, "TEL-3").onGetTemplate() as PaneTemplate
        assertEquals("Position inconnue", n.pane.rows[1].title.toString())
        assertEquals(listOf("Écrire"), n.pane.actions.map { it.title.toString() })
    }

    @Test
    fun myStatus_firstRowOfTeam_gridOfFour_oneTouchSends() {
        // Lot 24 (card « Android Auto : statut en un appui », choices 1 to 3).
        val first = rows(tab(MainScreen.TEAM))[0]
        assertEquals("Aucun statut", first.texts[0].toString())
        // Nobody else: the message stays below « Mon statut ».
        assertEquals("Personne", rows(tab(MainScreen.TEAM))[1].title.toString())
        first.onClickDelegate!!.sendClick(object : OnDoneCallback {})
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(car.getCarService(TestScreenManager::class.java).screensPushed.last() is StatusScreen)
        val grid = StatusScreen(car).onGetTemplate() as GridTemplate
        val items = grid.singleList!!.items.map { it as GridItem }
        assertEquals(listOf("En route", "Sur place", "Disponible", "Pause"), items.map { it.title.toString() })
        items.forEach { assertNotNull(it.image) }
        items[1].onClickDelegate!!.sendClick(object : OnDoneCallback {})
        shadowOf(Looper.getMainLooper()).idle()
        val sent = JSONArray(CarData.takeActions(app)).getJSONObject(0)
        assertEquals("status", sent.getString("type"))
        assertEquals("sur_place", sent.getString("status"))
        // The application tells the status back: shown, and « Actuel » in the grid.
        write(CarData.snapshot(car).put("me", JSONObject().put("status", "sur_place")))
        assertEquals("Sur place", rows(tab(MainScreen.TEAM))[0].texts[0].toString())
        val again = (StatusScreen(car).onGetTemplate() as GridTemplate).singleList!!.items.map { it as GridItem }
        assertEquals("Actuel", again[1].text.toString())
        assertTrue(again[0].text == null)
    }

    @Test
    fun arrival_onceByOrder_within100m_yesSendsTheArrival() {
        // Lot 24 (card « Android Auto : arrivée détectée près du point d'un
        // ordre », choices 1, 3 and 4).
        write(snapshot(JSONArray().put(order("o1", "accepted"))))
        assertTrue(ArrivalAlerts.take(app, Snapshot(CarData.snapshot(car))).isEmpty())
        write(snapshot(JSONArray().put(order("o1", "accepted").put("near", true)).put(order("o2", "sent").put("near", true))))
        val asked = ArrivalAlerts.take(app, Snapshot(CarData.snapshot(car)))
        assertEquals(listOf("o1"), asked.map { it.optString("id") })
        // Driving around the point: not asked again.
        assertTrue(ArrivalAlerts.take(app, Snapshot(CarData.snapshot(car))).isEmpty())
        val snap = Snapshot(CarData.snapshot(car))
        assertEquals("Vous êtes arrivé à Point de la carte. Signaler l’arrivée ?", ArrivalAlerts.question(snap, asked[0]))
        var ended = false
        val alert = ArrivalAlerts.alert(car, snap, asked[0]) { ended = true }
        assertEquals("Vous êtes arrivé à Point de la carte", alert.title.toString())
        assertEquals(listOf("Oui", "Plus tard"), alert.actions.map { it.title.toString() })
        click(alert.actions[0])
        assertTrue(ended)
        val sent = JSONArray(CarData.takeActions(app)).getJSONObject(0)
        assertEquals("arrival", sent.getString("type"))
        assertEquals("o1", sent.getString("id"))
    }

    @Test
    fun arrival_spokenAnswer() {
        assertEquals(true, ArrivalAlerts.spokenAnswer("Oui"))
        assertEquals(true, ArrivalAlerts.spokenAnswer("oui je suis arrivé"))
        assertEquals(true, ArrivalAlerts.spokenAnswer("d'accord"))
        assertEquals(false, ArrivalAlerts.spokenAnswer("plus tard"))
        assertEquals(false, ArrivalAlerts.spokenAnswer("non"))
        assertEquals(true, ArrivalAlerts.spokenAnswer("yes"))
        assertEquals(null, ArrivalAlerts.spokenAnswer("euh"))
        assertEquals(null, ArrivalAlerts.spokenAnswer(null))
    }

    @Test
    fun quickMessages_inTheConversationAndTheOrder_oneTouchSends() {
        // Lot 24 (card « Android Auto : messages types en un appui »).
        val json = snapshot(JSONArray().put(order("o1", "accepted")))
        json.getJSONObject("labels").put("quick", "Messages types").put("read", "Lire").put("reply", "Répondre")
        json.put("quick", JSONArray()
            .put(JSONObject().put("text", "Bien reçu").put("priority", "routine").put("prioLabel", ""))
            .put(JSONObject().put("text", "Besoin d’aide").put("priority", "urgent").put("prioLabel", "URGENT")))
        json.put("messages", JSONArray().put(JSONObject().put("id", "u:PCO").put("title", "PCO").put("text", "PCO : Allez au P2")
            .put("body", "09:00 · PCO : Allez au P2").put("speak", "PCO : Allez au P2.").put("canReply", true).put("replyTo", "PCO")))
        write(json)
        val c = ConversationScreen(car, SarcadeSession(), "u:PCO").onGetTemplate() as MessageTemplate
        val quick = c.actionStrip!!.actions.single()
        assertEquals("Messages types", quick.title.toString())
        click(quick)
        assertTrue(car.getCarService(TestScreenManager::class.java).screensPushed.last() is QuickScreen)
        CarData.takeActions(app)
        val list = QuickScreen(car, conversation = "u:PCO").onGetTemplate() as ListTemplate
        val r = rows(list)
        assertEquals(listOf("Bien reçu", "Besoin d’aide"), r.map { it.title.toString() })
        assertEquals("URGENT", r[1].texts[0].toString())
        assertTrue(r[0].texts.isEmpty())
        r[1].onClickDelegate!!.sendClick(object : OnDoneCallback {})
        shadowOf(Looper.getMainLooper()).idle()
        val sent = JSONArray(CarData.takeActions(app)).getJSONObject(0)
        assertEquals("quick", sent.getString("type"))
        assertEquals("Besoin d’aide", sent.getString("text"))
        assertEquals("urgent", sent.getString("priority"))
        assertEquals("u:PCO", sent.getString("conversation"))
        // Card of an accepted order: « Je suis arrivé » titled, the quick
        // messages as an icon (one titled button in the strip).
        val o = OrderScreen(car, "o1").onGetTemplate() as PaneTemplate
        val strip = o.actionStrip!!.actions
        assertEquals("Je suis arrivé", strip[0].title.toString())
        assertTrue(strip[1].title == null)
        assertNotNull(strip[1].icon)
        click(strip[1])
        assertTrue(car.getCarService(TestScreenManager::class.java).screensPushed.last() is QuickScreen)
    }

    @Test
    fun heardHere_firstRowOfPoints_duringSaterOnly_cancelWithin10s() {
        // Lot 24 (card « Android Auto : « Signal entendu ici » (SATER) »).
        assertEquals(listOf("PC", "Butte"), rows(tab(MainScreen.POINTS)).map { it.title.toString() })
        val json = snapshot().put("sater", JSONObject().put("ready", true))
        json.getJSONObject("labels").put("heard", "Signal entendu ici").put("heardHelp", "Position, cap et heure au PCO")
            .put("heardSent", "Point d’écoute envoyé").put("heardCancelled", "Point d’écoute annulé").put("cancel", "Annuler")
        write(json)
        val r = rows(tab(MainScreen.POINTS))
        assertEquals(listOf("Signal entendu ici", "PC", "Butte"), r.map { it.title.toString() })
        assertTrue(r[0].actions.isEmpty())
        r[0].onClickDelegate!!.sendClick(object : OnDoneCallback {})
        shadowOf(Looper.getMainLooper()).idle()
        val heard = JSONArray(CarData.takeActions(app)).getJSONObject(0)
        assertEquals("heard", heard.getString("type"))
        assertTrue(heard.getString("id").isNotEmpty())
        assertTrue(heard.getLong("at") > 0)
        val alert = HeardAlert.alert(car, Snapshot(CarData.snapshot(car)), heard.getString("id"))
        assertEquals("Point d’écoute envoyé", alert.title.toString())
        assertEquals(HeardAlert.CANCEL_MS, alert.durationMillis)
        click(alert.actions.single())
        val cancel = JSONArray(CarData.takeActions(app)).getJSONObject(0)
        assertEquals("heardCancel", cancel.getString("type"))
        assertEquals(heard.getString("id"), cancel.getString("id"))
        // No position: nothing sent, the reason shown.
        write(CarData.snapshot(car).put("sater", JSONObject().put("ready", false)))
        val none = rows(tab(MainScreen.POINTS))[0]
        none.onClickDelegate!!.sendClick(object : OnDoneCallback {})
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("[]", CarData.takeActions(app))
    }

    @Test
    fun teamTab_notRedrawn_whenAnOperatorOnlyMoves() {
        val t = System.currentTimeMillis()
        val a = Snapshot(snapshot(at = t, team = JSONArray().put(mate("TEL-2", "3 km au nord", lat = 48.83))))
        val b = Snapshot(snapshot(at = t, team = JSONArray().put(mate("TEL-2", "3 km au nord", lat = 48.8301))))
        assertEquals(a.signature(MainScreen.TEAM), b.signature(MainScreen.TEAM))
        // Position lost: the arrow goes, drawn again.
        val c = Snapshot(snapshot(at = t, team = JSONArray().put(mate("TEL-2", "3 km au nord", lat = null))))
        assertFalse(a.signature(MainScreen.TEAM) == c.signature(MainScreen.TEAM))
    }

    @Test
    fun navigation_withoutPoint_saysWhy() {
        CarUi.navigate(car, Snapshot(CarData.snapshot(car)), Double.NaN, 1.0)
        val toasts = car.getCarService(TestAppManager::class.java).toastsShown.map { it.toString() }
        assertTrue(toasts.last().startsWith("Navigation impossible"))
    }

    @Test
    fun orderAlert_nameOfThePointFirst_goAndView() {
        val snap = Snapshot(CarData.snapshot(car))
        var viewed = false
        val alert = OrderAlerts.alert(car, snap, snap.items("orders").single()) { viewed = true }
        assertEquals("Point de la carte", alert.title.toString())
        assertEquals("Ordre de déplacement · PCO-iphone-apps · 3 km NO", alert.subtitle.toString())
        assertEquals(listOf("Y aller", "Voir"), alert.actions.map { it.title.toString() })
        click(alert.actions[0])
        assertEquals("geo:48.819100,1.921000", car.startCarAppIntents.last().dataString)
        click(alert.actions[1])
        assertTrue(viewed)
    }

    @Test
    fun orderAlert_onceByOrder_noBurstAfterTheUpdate() {
        // First time ever: the orders already there are only remembered.
        assertTrue(OrderAlerts.take(app, Snapshot(CarData.snapshot(car))).isEmpty())
        write(snapshot(JSONArray().put(order("o1", "sent")).put(order("o2", "sent"))))
        assertEquals(listOf("o2"), OrderAlerts.take(app, Snapshot(CarData.snapshot(car))).map { it.optString("id") })
        assertTrue(OrderAlerts.take(app, Snapshot(CarData.snapshot(car))).isEmpty())
        // An answered order is not announced.
        write(snapshot(JSONArray().put(order("o3", "accepted"))))
        assertTrue(OrderAlerts.take(app, Snapshot(CarData.snapshot(car))).isEmpty())
    }

    @Test
    fun redrawn_onlyWhenTheShownTabChanges() {
        val t = System.currentTimeMillis()
        val before = Snapshot(snapshot(at = t)).signature(MainScreen.ORDERS)
        // Written again a minute later, same content: same screen.
        assertEquals(before, Snapshot(snapshot(at = t + 60_000L)).signature(MainScreen.ORDERS))
        // A new order: drawn again.
        val other = Snapshot(snapshot(JSONArray().put(order("o1", "sent")).put(order("o2", "sent")), at = t + 60_000L))
        assertFalse(before == other.signature(MainScreen.ORDERS))
        // The Points tab did not change.
        assertEquals(Snapshot(snapshot(at = t)).signature(MainScreen.POINTS), other.signature(MainScreen.POINTS))
    }

    @Test
    fun appManagerOfTheTests_isUsed() {
        // Guard: the toasts and alerts of these tests go to the fake host.
        assertTrue(car.getCarService(AppManager::class.java) is TestAppManager)
    }
}
