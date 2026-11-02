package org.sarcade.car

import android.content.Context
import android.os.Looper
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.HandshakeInfo
import androidx.car.app.OnDoneCallback
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.TabTemplate
import androidx.car.app.testing.TestAppManager
import androidx.car.app.testing.TestCarContext
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

    private fun snapshot(orders: JSONArray = JSONArray().put(order("o1", "sent")), at: Long = System.currentTimeMillis()): JSONObject {
        val labels = JSONObject()
        mapOf(
            "tab.messages" to "Messages", "tab.orders" to "Ordres", "tab.points" to "Points", "tab.team" to "Équipe",
            "empty.messages" to "Aucun message", "empty.orders" to "Aucun ordre", "empty.points" to "Aucun point",
            "empty.team" to "Personne", "sos" to "SOS", "navigateCar" to "Naviguer (application de la voiture)",
            "navigateCarShort" to "Naviguer · voiture", "navigateFailed" to "Navigation impossible : installez Google Maps ou Waze sur le téléphone",
            "accept" to "Accepter", "refuse" to "Refuser", "arrived" to "Je suis arrivé", "sent" to "Envoyé",
            "go" to "Y aller", "view" to "Voir", "orderAlert" to "Ordre de déplacement", "order" to "Ordre",
            "note" to "Consigne", "gone" to "Plus disponible", "stale" to "Données de {time}",
        ).forEach { (k, v) -> labels.put(k, v) }
        val points = JSONArray()
            .put(JSONObject().put("id", "poi1").put("kind", "poi").put("icon", "gathering").put("color", 0xFF1E88E5.toInt())
                .put("title", "PC").put("text", "3 km NO").put("lat", 48.8191).put("lon", 1.921))
            .put(JSONObject().put("id", "h1").put("kind", "high").put("icon", "high").put("color", 0xFF6D4C41.toInt())
                .put("title", "Butte").put("text", "3 km NE · Point haut · 412 m").put("lat", 48.8191).put("lon", 1.979))
        return JSONObject().put("v", 1).put("at", at).put("lang", "fr").put("distress", false)
            .put("labels", labels).put("messages", JSONArray()).put("orders", orders)
            .put("points", points).put("team", JSONArray())
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

    /** List of a tab or a section, in the layout in force (one section at
     *  a time since lot 23) or in the tabs of lot 20 ([inStrip] false). */
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
    fun sos_inTheTopStrip_noRoundButtonLeft() {
        // Lot 23 (card « Android Auto : SOS dans la barre du haut… », choice
        // 1): the car of the owner (API level 8) shows one section at a
        // time, « Rubriques » and a red « SOS » at the top, no round button.
        assertTrue(CarUi.SOS_IN_STRIP)
        for (id in MainScreen.TABS) {
            val screen = MainScreen(car, SarcadeSession())
            screen.tab = id
            val list = screen.onGetTemplate() as ListTemplate
            assertTrue("round button left in $id", list.actions.isEmpty())
            assertEquals(Snapshot(CarData.snapshot(car)).label("tab.$id"), list.title.toString())
            val strip = list.actionStrip!!.actions
            assertEquals(2, strip.size)
            assertEquals("SOS", strip[1].title.toString())
            assertEquals(CarColor.RED, strip[1].icon!!.tint)
        }
    }

    @Test
    fun sos_redIconAlone_onANeutralBackground_inTheTabsOfLot20() {
        val sos = tab(MainScreen.POINTS, inStrip = false).actions.single()
        assertEquals(CarColor.RED, sos.icon!!.tint)
        assertTrue(sos.title == null)
        assertEquals(CarUi.SOS_BACKGROUND, sos.backgroundColor)
    }

    @Test
    fun sosInTheTopStrip_asOnOlderCars_isAccepted() {
        // Layout of the fallback (CarUi.SOS_IN_STRIP) and of the cars below
        // API level 6: one section, « Rubriques » and « SOS » at the top.
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
        // Touching the row itself does the same.
        rows(tab(MainScreen.POINTS))[1].onClickDelegate!!.sendClick(object : OnDoneCallback {})
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("geo:48.819100,1.979000", car.startCarAppIntents.last().dataString)
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
