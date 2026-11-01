import Flutter
import UIKit

/// Data written by the application for the car (lib/src/features/car/
/// car_screen.dart) and actions of the driver read back by it: same channel
/// and same content as on Android (android/src/main/kotlin/.../CarData.kt).
final class SarcadeCarData {
    static let shared = SarcadeCarData()
    static let changed = Notification.Name("SarcadeCarDataChanged")

    private let defaults = UserDefaults.standard
    private let snapshotKey = "sarcade_car_screen.snapshot"
    private let actionsKey = "sarcade_car_screen.actions"
    private var cached: [String: Any]?
    private var sessions = 0
    let plugins = NSHashTable<SarcadeCarPlugin>.weakObjects()

    /// A CarPlay screen shows SARCADE.
    var active: Bool { return sessions > 0 }

    /// Last data written by the application; empty before its first run.
    var snapshot: [String: Any] {
        if let c = cached { return c }
        var read: [String: Any] = [:]
        if let raw = defaults.string(forKey: snapshotKey), let data = raw.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            read = obj
        }
        cached = read
        return read
    }

    func update(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        cached = obj
        defaults.set(json, forKey: snapshotKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: SarcadeCarData.changed, object: nil)
        }
    }

    /// Keeps an action of the driver until the application takes it.
    func post(_ action: [String: Any]) {
        var a = action
        a["uid"] = UUID().uuidString
        a["at"] = Int(Date().timeIntervalSince1970 * 1000)
        var list: [Any] = []
        if let raw = defaults.string(forKey: actionsKey), let data = raw.data(using: .utf8),
           let old = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            list = old
        }
        list.append(a)
        if let data = try? JSONSerialization.data(withJSONObject: list), let text = String(data: data, encoding: .utf8) {
            defaults.set(text, forKey: actionsKey)
        }
        DispatchQueue.main.async {
            for p in self.plugins.allObjects { p.notifyActions() }
        }
    }

    func takeActions() -> String {
        let raw = defaults.string(forKey: actionsKey) ?? "[]"
        defaults.removeObject(forKey: actionsKey)
        return raw
    }

    func sessionChanged(_ delta: Int) {
        sessions = max(0, sessions + delta)
        let now = active
        DispatchQueue.main.async {
            for p in self.plugins.allObjects { p.notifyActive(now) }
        }
    }
}

/// Channel `org.sarcade.car/screen` (see the Android plugin). The CarPlay
/// screen itself is SarcadeCarPlaySceneDelegate, declared to iOS only once
/// Apple grants the CarPlay entitlement (tool/patch_ios.py).
public class SarcadeCarPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SarcadeCarPlugin()
        let channel = FlutterMethodChannel(name: "org.sarcade.car/screen", binaryMessenger: registrar.messenger())
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        SarcadeCarData.shared.plugins.add(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "update":
            if let json = call.arguments as? String { SarcadeCarData.shared.update(json) }
            result(nil)
        case "takeActions":
            result(SarcadeCarData.shared.takeActions())
        case "state":
            result(SarcadeCarData.shared.active)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func notifyActions() {
        channel?.invokeMethod("actions", arguments: nil)
    }

    func notifyActive(_ on: Bool) {
        channel?.invokeMethod("active", arguments: on)
    }
}
