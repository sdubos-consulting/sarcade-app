package org.sarcade.car

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText
import androidx.car.app.model.ForegroundCarColorSpan
import androidx.core.graphics.drawable.IconCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Data written by the application, read by the screens (see CarData). */
internal class Snapshot(private val json: JSONObject) {
    val ready: Boolean get() = json.has("labels")
    val lang: String get() = json.optString("lang", "fr")
    val distress: Boolean get() = json.optBoolean("distress", false)
    private val at: Long get() = json.optLong("at", 0L)

    fun label(key: String): String = json.optJSONObject("labels")?.optString(key, key) ?: key

    fun items(key: String): List<JSONObject> {
        val list: JSONArray = json.optJSONArray(key) ?: return emptyList()
        return (0 until list.length()).mapNotNull { list.optJSONObject(it) }
    }

    fun item(key: String, id: String): JSONObject? = items(key).firstOrNull { it.optString("id") == id }

    /** What a tab shows, as text: the screen is drawn again only when it
     *  changes (lot 20, card « Android Auto : l'écran clignote… », choice
     *  4); the time of the write is not in it. */
    fun signature(key: String): String =
        listOf(ready, lang, distress, staleText() ?: "", json.optJSONArray(key)?.toString() ?: "").joinToString("|")

    /** « Données de 10:42 : ouvrez SARCADE sur le téléphone » when the
     *  application has not written for 2 minutes; null otherwise. */
    fun staleText(now: Long = System.currentTimeMillis()): String? {
        if (at <= 0L || now - at < STALE_MS) return null
        val time = SimpleDateFormat("HH:mm", Locale.FRANCE).format(Date(at))
        return label("stale").replace("{time}", time)
    }

    companion object {
        const val STALE_MS = 120_000L
    }
}

internal object CarUi {
    const val ORANGE = 0xFFFB8C00.toInt()

    /** Priority in colour (choice 4): urgent red, immediate orange, distress red. */
    fun priorityColor(priority: String): CarColor? = when (priority) {
        "urgent", "distress" -> CarColor.RED
        "immediate" -> CarColor.createCustom(ORANGE, 0xFFFFB74D.toInt())
        else -> null
    }

    /** « URGENT · F4JPO : texte », the priority word coloured. */
    fun withPriority(prefix: String, priority: String, rest: String): CharSequence {
        val color = priorityColor(priority)
        if (prefix.isEmpty() || color == null) return rest
        val text = SpannableString("$prefix · $rest")
        text.setSpan(ForegroundCarColorSpan.create(color), 0, prefix.length, Spanned.SPAN_INCLUSIVE_EXCLUSIVE)
        return text
    }

    fun icon(context: CarContext, res: Int, tint: CarColor? = CarColor.DEFAULT): CarIcon {
        val b = CarIcon.Builder(IconCompat.createWithResource(context, res))
        if (tint != null) b.setTint(tint)
        return b.build()
    }

    /** Round tile of an operator or a point (choice 4): its icon in white on
     *  its colour, as the avatars of the phone. [iconArgb] and [pad]: SOS
     *  badge (see [sosAction]). */
    fun tile(context: CarContext, res: Int, argb: Int, iconArgb: Int = Color.WHITE, pad: Int = 96 / 5): CarIcon {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = argb or 0xFF000000.toInt()
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        val drawable = context.resources.getDrawable(res, null)
        drawable.mutate()
        drawable.setTint(iconArgb)
        drawable.setBounds(pad, pad, size - pad, size - pad)
        drawable.draw(canvas)
        return CarIcon.Builder(IconCompat.createWithBitmap(bitmap)).build()
    }

    /** Icon of an operator (ids of lib/src/features/map/operator_icons.dart). */
    fun operatorIcon(id: String?): Int = when (id) {
        "walk" -> R.drawable.sarcade_car_directions_walk
        "bike" -> R.drawable.sarcade_car_pedal_bike
        "moto" -> R.drawable.sarcade_car_two_wheeler
        "car" -> R.drawable.sarcade_car_directions_car
        "4x4" -> R.drawable.sarcade_car_directions_car_filled
        "truck" -> R.drawable.sarcade_car_local_shipping
        "ambulance" -> R.drawable.sarcade_car_emergency
        "fire" -> R.drawable.sarcade_car_fire_truck
        "boat" -> R.drawable.sarcade_car_directions_boat
        "helicopter" -> R.drawable.sarcade_car_airplanemode_active
        "plane" -> R.drawable.sarcade_car_flight
        "fixed" -> R.drawable.sarcade_car_home
        "relay" -> R.drawable.sarcade_car_cell_tower
        "pco" -> R.drawable.sarcade_car_flag
        "channel" -> R.drawable.sarcade_car_groups
        else -> R.drawable.sarcade_car_person
    }

    /** Icon of a point (ids of lib/src/features/poi/poi_icons.dart, plus the
     *  high points and relays of the radio reference). */
    fun pointIcon(id: String?): Int = when (id) {
        "gathering" -> R.drawable.sarcade_car_groups
        "command_post" -> R.drawable.sarcade_car_home_work
        "danger" -> R.drawable.sarcade_car_warning_amber
        "parking" -> R.drawable.sarcade_car_local_parking
        "water" -> R.drawable.sarcade_car_water_drop
        "helipad" -> R.drawable.sarcade_car_flight
        "vehicle" -> R.drawable.sarcade_car_directions_car
        "viewpoint" -> R.drawable.sarcade_car_visibility
        "medical" -> R.drawable.sarcade_car_local_hospital
        "radio", "relay" -> R.drawable.sarcade_car_cell_tower
        "shelter" -> R.drawable.sarcade_car_cottage
        "flag" -> R.drawable.sarcade_car_flag
        "high" -> R.drawable.sarcade_car_terrain
        else -> R.drawable.sarcade_car_location_on
    }

    /** Most rows a list may show in this car (6 when the host cannot tell). */
    fun listLimit(context: CarContext): Int = runCatching {
        if (context.carAppApiLevel < 2) 6
        else context.getCarService(ConstraintManager::class.java).getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
    }.getOrDefault(6).coerceAtLeast(1)

    /** Title of « Naviguer » (lot 18, card « Android Auto : « Naviguer »
     *  ouvre directement une application… », choice 1): « Naviguer
     *  (application de la voiture) », Android Auto choosing the navigation
     *  application itself; « Naviguer · voiture » when the long title does
     *  not fit the button (text variants, car API level 2). */
    fun navigateTitle(context: CarContext, snap: Snapshot): CarText {
        val b = CarText.Builder(snap.label("navigateCar"))
        if (context.carAppApiLevel >= 2) b.addVariant(snap.label("navigateCarShort"))
        return b.build()
    }

    /** Intent of the navigation application of the car towards a point
     *  (lot 20, card « Android Auto : ordres de déplacement peu
     *  utilisables… », choice 3). Car App Library (CarContext.startCarApp)
     *  and Android Auto navigation intents: action ACTION_NAVIGATE, data
     *  « geo:latitude,longitude ». Until lot 19 a query « ?q=lat,lon(name) »
     *  was added: Google Maps and Waze then search that text as an address
     *  and may start nothing, without error. Coordinates with a dot. */
    fun navigateIntent(lat: Double, lon: Double): Intent =
        Intent(CarContext.ACTION_NAVIGATE, Uri.parse("geo:${coord(lat)},${coord(lon)}"))

    private fun coord(v: Double): String = String.format(Locale.US, "%.6f", v)

    /** « Naviguer », « Y aller » : Google Maps or Waze of the car, guided
     *  towards the point; a clear message when no application takes it. */
    fun navigate(context: CarContext, snap: Snapshot, lat: Double, lon: Double) {
        if (lat.isNaN() || lon.isNaN()) {
            toast(context, snap.label("navigateFailed"))
            return
        }
        try {
            context.startCarApp(navigateIntent(lat, lon))
        } catch (e: Exception) {
            toast(context, snap.label("navigateFailed"))
        }
    }

    fun toast(context: CarContext, text: String) {
        CarToast.makeText(context, text, CarToast.LENGTH_LONG).show()
    }

    /** Lot 20 (card « Android Auto, onglet Points : boutons ronds gris
     *  vides, SOS en disque blanc… », choice 2): where the SOS is.
     *  - false (choice of the owner, tried first): round button of the
     *    lists, the SOS icon alone tinted red, on a neutral background;
     *  - true (fallback, if Android Auto still paints the icon): no round
     *    button, the SOS in the action strip at the top (red icon and the
     *    word « SOS »); the car then shows one section at a time (button
     *    « Rubriques » of the strip) instead of the tabs, the strip not
     *    existing in the tabs of the Car App Library 1.7. */
    const val SOS_IN_STRIP = false

    /** Neutral background of the round SOS button: white by day, dark grey
     *  by night. The Car App Library refuses a round button without a
     *  background colour (IllegalArgumentException, found by the tests of
     *  the car screens); a red background would hide the red icon. */
    val SOS_BACKGROUND: CarColor = CarColor.createCustom(Color.WHITE, 0xFF303030.toInt())

    /** Red SOS action (choice 3 of lot 17), always reachable; [floating]:
     *  the round button of the lists (icon only: a round button cannot
     *  carry a title), otherwise the action strip (« SOS » written; the
     *  strip accepts no colour in its titles, the icon stays red).
     *
     *  History: lot 17 asked a red background, which Android Auto replaced
     *  by its blue; lot 18 drew « SOS » in red on a white disc in the
     *  picture, which Android Auto painted in one colour (white disc, photo
     *  of 2 Nov 2026). Lot 20: the icon of the library, tinted CarColor.RED,
     *  on a neutral background. */
    fun sosAction(context: CarContext, snap: Snapshot, floating: Boolean, onClick: () -> Unit): Action {
        val b = Action.Builder()
            .setIcon(icon(context, R.drawable.sarcade_car_sos, CarColor.RED))
            .setOnClickListener { onClick() }
        if (floating) b.setBackgroundColor(SOS_BACKGROUND) else b.setTitle(snap.label("sos"))
        return b.build()
    }

    fun post(context: CarContext, type: String, fill: JSONObject.() -> Unit = {}) {
        val action = JSONObject().put("type", type)
        action.fill()
        CarData.post(context, action)
    }
}
