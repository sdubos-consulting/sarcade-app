import AVFoundation
import CarPlay
import UIKit

/// Data of the application as read by the CarPlay screen.
struct CarSnap {
    let json: [String: Any]

    var ready: Bool { return json["labels"] != nil }
    var lang: String { return json["lang"] as? String ?? "fr" }
    var distress: Bool { return json["distress"] as? Bool ?? false }

    func label(_ key: String) -> String {
        return (json["labels"] as? [String: Any])?[key] as? String ?? key
    }

    func items(_ key: String) -> [[String: Any]] {
        return json[key] as? [[String: Any]] ?? []
    }

    /// « Données de 10:42 : ouvrez SARCADE sur le téléphone » after 2 min
    /// without data from the application.
    func staleText() -> String? {
        guard let at = (json["at"] as? NSNumber)?.doubleValue, at > 0 else { return nil }
        let date = Date(timeIntervalSince1970: at / 1000)
        if Date().timeIntervalSince(date) < 120 { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return label("stale").replacingOccurrences(of: "{time}", with: f.string(from: date))
    }
}

extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String { return self[key] as? String ?? "" }
    func num(_ key: String) -> Double { return (self[key] as? NSNumber)?.doubleValue ?? 0 }
    func int(_ key: String, _ fallback: Int) -> Int { return (self[key] as? NSNumber)?.intValue ?? fallback }
}

/**
 * SARCADE screen in CarPlay (card « Voiture : vraie interface SARCADE avec
 * onglets », lot 17, step 2b): tabs Messages, Ordres, Points, Équipe, as on
 * Android Auto; « SOS » in the navigation bar of every tab, confirmed.
 * No typing, no SARCADE map; « Naviguer » opens Plans.
 *
 * Inactive until Apple grants the CarPlay entitlement (« Sécurité
 * publique »): tool/patch_ios.py declares this scene only with
 * SARCADE_CARPLAY=1, together with the entitlement.
 */
@available(iOS 14.0, *)
@objc(SarcadeCarPlaySceneDelegate)
public class SarcadeCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private static let tabs = ["messages", "orders", "points", "team"]
    private static let defaultColor = 0xFF1E88E5

    private var interface: CPInterfaceController?
    private var scene: CPTemplateApplicationScene?
    private var lists: [String: CPListTemplate] = [:]
    private var observer: NSObjectProtocol?
    private let speech = AVSpeechSynthesizer()

    private var snap: CarSnap { return CarSnap(json: SarcadeCarData.shared.snapshot) }

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                         didConnect interfaceController: CPInterfaceController) {
        scene = templateApplicationScene
        interface = interfaceController
        SarcadeCarData.shared.sessionChanged(1)
        let s = snap
        var templates: [CPTemplate] = []
        for id in Self.tabs {
            let list = CPListTemplate(title: s.label("tab.\(id)"), sections: [])
            list.tabTitle = s.label("tab.\(id)")
            list.tabImage = Self.symbol(Self.tabSymbols(id))
            list.trailingNavigationBarButtons = [CPBarButton(title: s.label("sos")) { [weak self] _ in self?.confirmSos() }]
            lists[id] = list
            templates.append(list)
        }
        interfaceController.setRootTemplate(CPTabBarTemplate(templates: templates), animated: false, completion: nil)
        observer = NotificationCenter.default.addObserver(forName: SarcadeCarData.changed, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                         didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        SarcadeCarData.shared.sessionChanged(-1)
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
        speech.stopSpeaking(at: .immediate)
        lists = [:]
        interface = nil
        scene = nil
    }

    // MARK: - Tabs

    private func refresh() {
        let s = snap
        for id in Self.tabs {
            guard let list = lists[id] else { continue }
            var items: [CPListItem] = []
            if !s.ready {
                let fr = (Locale.preferredLanguages.first ?? "fr").hasPrefix("fr")
                items.append(CPListItem(text: fr ? "Ouvrez SARCADE une fois sur le téléphone" : "Open SARCADE on the phone once", detailText: nil))
            } else if let stale = s.staleText() {
                items.append(CPListItem(text: stale, detailText: nil))
            }
            switch id {
            case "messages": items += s.items("messages").map { conversationItem(s, $0) }
            case "orders": items += s.items("orders").map { orderItem(s, $0) }
            case "points": items += s.items("points").map { pointItem(s, $0) }
            default: items += s.items("team").map { teammateItem($0) }
            }
            list.emptyViewTitleVariants = [s.label("empty.\(id)")]
            list.updateSections([CPListSection(items: Array(items.prefix(Int(CPListTemplate.maximumItemCount))))])
        }
    }

    private func conversationItem(_ s: CarSnap, _ c: [String: Any]) -> CPListItem {
        let prio = c.str("prioLabel")
        let unread = c.int("unread", 0)
        let text = (prio.isEmpty ? "" : "\(prio) · ") + c.str("text")
        let item = CPListItem(text: unread > 0 ? "\(c.str("title")) (\(unread))" : c.str("title"), detailText: text,
                              image: Self.tile(Self.operatorSymbols(c.str("icon")), c.int("color", Self.defaultColor)))
        if let dot = Self.priorityDot(c.str("prio")) { item.setAccessoryImage(dot) }
        item.handler = { [weak self] _, done in
            self?.openConversation(c)
            done()
        }
        return item
    }

    private func orderItem(_ s: CarSnap, _ o: [String: Any]) -> CPListItem {
        let item = CPListItem(text: o.str("title"), detailText: o.str("text"),
                              image: Self.tile(["flag.fill"], o.int("color", Self.defaultColor)))
        item.handler = { [weak self] _, done in
            self?.openOrder(o)
            done()
        }
        return item
    }

    private func pointItem(_ s: CarSnap, _ p: [String: Any]) -> CPListItem {
        let item = CPListItem(text: p.str("title"), detailText: p.str("text"),
                              image: Self.tile(Self.pointSymbols(p.str("icon")), p.int("color", Self.defaultColor)))
        item.handler = { [weak self] _, done in
            self?.navigate(p.num("lat"), p.num("lon"))
            done()
        }
        return item
    }

    private func teammateItem(_ t: [String: Any]) -> CPListItem {
        return CPListItem(text: t.str("title"), detailText: t.str("text"),
                          image: Self.tile(Self.operatorSymbols(t.str("icon")), t.int("color", Self.defaultColor)))
    }

    // MARK: - Detail screens

    /// A conversation: its last messages and « Lire »; opening it marks it as
    /// read. The answer goes through Siri (notifications, lot 1c): CarPlay
    /// gives no dictation to this category.
    private func openConversation(_ c: [String: Any]) {
        let s = snap
        SarcadeCarData.shared.post(["type": "read", "conversation": c.str("id")])
        let lines = c.str("body").split(separator: "\n").map { CPInformationItem(title: nil, detail: String($0)) }
        let read = CPTextButton(title: s.label("read"), textStyle: .confirm) { [weak self] _ in
            self?.speak(c.str("speak"), s.lang)
        }
        let info = CPInformationTemplate(title: c.str("title"), layout: .leading, items: lines, actions: [read])
        interface?.pushTemplate(info, animated: true, completion: nil)
    }

    /// An order: Refuser / Accepter while sent, Je suis arrivé / Naviguer
    /// once accepted, Naviguer afterwards.
    private func openOrder(_ o: [String: Any]) {
        let s = snap
        var items = [CPInformationItem(title: o.str("title"), detail: o.str("text"))]
        if !o.str("note").isEmpty { items.append(CPInformationItem(title: s.label("note"), detail: o.str("note"))) }
        func answer(_ status: String, _ label: String, _ style: CPTextButton.Style) -> CPTextButton {
            return CPTextButton(title: s.label(label), textStyle: style) { [weak self] _ in
                SarcadeCarData.shared.post(["type": "order", "id": o.str("id"), "status": status])
                self?.interface?.popTemplate(animated: true, completion: nil)
            }
        }
        let go = CPTextButton(title: s.label("navigate"), textStyle: .confirm) { [weak self] _ in
            self?.navigate(o.num("lat"), o.num("lon"))
        }
        let actions: [CPTextButton]
        switch o.str("status") {
        case "sent": actions = [answer("refused", "refuse", .cancel), answer("accepted", "accept", .confirm)]
        case "accepted": actions = [answer("arrived", "arrived", .normal), go]
        default: actions = [go]
        }
        let info = CPInformationTemplate(title: s.label("order"), layout: .leading, items: items, actions: actions)
        interface?.pushTemplate(info, animated: true, completion: nil)
    }

    /// SOS (choice 3), confirmed; « Fin de détresse » during a distress.
    private func confirmSos() {
        let s = snap
        let end = s.distress
        let cancel = CPAlertAction(title: s.label("cancel"), style: .cancel) { [weak self] _ in
            self?.interface?.dismissTemplate(animated: true, completion: nil)
        }
        let confirm = CPAlertAction(title: s.label(end ? "sosEnd" : "sosSend"), style: end ? .default : .destructive) { [weak self] _ in
            SarcadeCarData.shared.post(["type": end ? "sosEnd" : "sos"])
            self?.interface?.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [s.label(end ? "sosOn" : "sosAsk")], actions: [cancel, confirm])
        interface?.presentTemplate(alert, animated: true, completion: nil)
    }

    private func navigate(_ lat: Double, _ lon: Double) {
        guard let url = URL(string: "maps://?daddr=\(lat),\(lon)") else { return }
        scene?.open(url, options: nil, completionHandler: nil)
    }

    private func speak(_ text: String, _ lang: String) {
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: lang == "en" ? "en-GB" : "fr-FR")
        speech.stopSpeaking(at: .immediate)
        speech.speak(u)
    }

    // MARK: - Images

    private static func symbol(_ names: [String]) -> UIImage? {
        for n in names { if let i = UIImage(systemName: n) { return i } }
        return UIImage(systemName: "circle.fill")
    }

    /// Round tile (choice 4): the icon in white on the colour of the operator.
    private static func tile(_ names: [String], _ argb: Int) -> UIImage {
        let size = CGSize(width: 44, height: 44)
        let color = UIColor(red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                            blue: CGFloat(argb & 0xFF) / 255, alpha: 1)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        return UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            if let s = symbol(names)?.withConfiguration(config).withTintColor(.white, renderingMode: .alwaysOriginal) {
                s.draw(in: CGRect(x: (size.width - s.size.width) / 2, y: (size.height - s.size.height) / 2,
                                  width: s.size.width, height: s.size.height))
            }
        }
    }

    /// Priority in colour (choice 4): urgent red, immediate orange.
    private static func priorityDot(_ priority: String) -> UIImage? {
        let color: UIColor
        switch priority {
        case "urgent", "distress": color = .systemRed
        case "immediate": color = .systemOrange
        default: return nil
        }
        let size = CGSize(width: 14, height: 14)
        return UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
    }

    private static func tabSymbols(_ id: String) -> [String] {
        switch id {
        case "messages": return ["message.fill"]
        case "orders": return ["flag.fill"]
        case "points": return ["mappin.and.ellipse", "mappin"]
        default: return ["person.3.fill"]
        }
    }

    /// Operator icons (lib/src/features/map/operator_icons.dart).
    private static func operatorSymbols(_ id: String) -> [String] {
        switch id {
        case "walk": return ["figure.walk"]
        case "bike", "moto": return ["bicycle"]
        case "car", "4x4": return ["car.fill"]
        case "truck": return ["truck.box.fill", "bus.fill"]
        case "ambulance": return ["cross.case.fill", "cross.fill"]
        case "fire": return ["flame.fill"]
        case "boat": return ["ferry.fill", "drop.fill"]
        case "helicopter", "plane": return ["airplane"]
        case "fixed": return ["house.fill"]
        case "relay": return ["antenna.radiowaves.left.and.right"]
        case "pco": return ["flag.fill"]
        case "channel": return ["person.3.fill"]
        default: return ["person.fill"]
        }
    }

    /// Point icons (lib/src/features/poi/poi_icons.dart, high points, relays).
    private static func pointSymbols(_ id: String) -> [String] {
        switch id {
        case "gathering": return ["person.3.fill"]
        case "command_post": return ["building.2.fill", "house.fill"]
        case "danger": return ["exclamationmark.triangle.fill"]
        case "parking": return ["parkingsign.circle.fill", "p.circle.fill"]
        case "water": return ["drop.fill"]
        case "helipad", "vehicle": return [id == "helipad" ? "airplane" : "car.fill"]
        case "viewpoint": return ["eye.fill"]
        case "medical": return ["cross.fill"]
        case "radio", "relay": return ["antenna.radiowaves.left.and.right"]
        case "shelter": return ["house.fill"]
        case "flag": return ["flag.fill"]
        case "high": return ["mountain.2.fill", "triangle.fill"]
        default: return ["mappin"]
        }
    }
}
