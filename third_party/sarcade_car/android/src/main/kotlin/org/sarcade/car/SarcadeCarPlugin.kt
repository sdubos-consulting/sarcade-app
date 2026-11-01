package org.sarcade.car

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Channel between the application and the car screen (lot 17):
 * - `update` (JSON text): data shown in the car;
 * - `takeActions`: actions of the driver, as a JSON list;
 * - `state`: true while a car session is open;
 * and, towards the application, `active` (bool) and `actions` (some wait).
 *
 * The manifest of the plugin also declares SARCADE to Android Auto
 * (messaging by notifications, lot 1b; screen with tabs, lot 17).
 */
class SarcadeCarPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val c = MethodChannel(binding.binaryMessenger, CHANNEL)
        c.setMethodCallHandler(this)
        channel = c
        CarData.attach(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        CarData.detach(this)
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.error("detached", "SARCADE car plugin detached", null)
            return
        }
        when (call.method) {
            "update" -> {
                val json = call.arguments as? String
                if (json != null) CarData.update(ctx, json)
                result.success(null)
            }
            "takeActions" -> result.success(CarData.takeActions(ctx))
            "state" -> result.success(CarData.active)
            else -> result.notImplemented()
        }
    }

    internal fun notifyActions() {
        channel?.invokeMethod("actions", null)
    }

    internal fun notifyActive(active: Boolean) {
        channel?.invokeMethod("active", active)
    }

    companion object {
        const val CHANNEL = "org.sarcade.car/screen"
    }
}
