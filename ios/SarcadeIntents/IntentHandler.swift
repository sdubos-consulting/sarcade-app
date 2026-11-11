import Foundation
import Intents

/// Data shared with the application through the App Group: the car data it
/// writes (third_party/sarcade_car/ios/Classes/SarcadeCarPlugin.swift, same
/// keys) and the actions Siri leaves for it.
enum SharedCar {
    static let group = "group.org.sarcade.sarcadeApp"
    static let snapshotKey = "sarcade_car_screen.snapshot"
    static let actionsKey = "sarcade_car_screen.actions"
    /// Darwin notification: the application, if it runs, takes the actions at once.
    static let actionsPosted = "org.sarcade.car.actions"

    static var defaults: UserDefaults { return UserDefaults(suiteName: group) ?? .standard }

    /// Conversations of the car screen: id, title, canReply...
    static func conversations() -> [[String: Any]] {
        guard let raw = defaults.string(forKey: snapshotKey), let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return obj["messages"] as? [[String: Any]] ?? []
    }

    /// Kept until the application sends it (same queue as CarPlay).
    static func post(_ action: [String: Any]) {
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
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(actionsPosted as CFString), nil, nil, true)
    }
}

/**
 * Siri module of SARCADE (card « Siri : messages SARCADE par un module Siri
 * séparé et lecture des notifications », validated on 9 Nov 2026): « Dis
 * Siri, envoie un message à Chromebook avec SARCADE ». The recipient is a
 * conversation of the car screen, recognised on a part of its title; the
 * message becomes a « reply » action, sent by the application like an answer
 * dictated in Android Auto.
 */
final class IntentHandler: INExtension, INSendMessageIntentHandling, INSetMessageAttributeIntentHandling {
    override func handler(for intent: INIntent) -> Any {
        return self
    }

    /// « Équipe Nord », « equipe-nord » and « ÉQUIPE NORD » are the same name.
    static func fold(_ s: String) -> String {
        return s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func str(_ c: [String: Any], _ key: String) -> String {
        return c[key] as? String ?? ""
    }

    private func person(_ c: [String: Any]) -> INPerson {
        let id = Self.str(c, "id")
        return INPerson(personHandle: INPersonHandle(value: id, type: .unknown), nameComponents: nil,
                        displayName: Self.str(c, "title"), image: nil, contactIdentifier: nil, customIdentifier: id)
    }

    private var replyable: [[String: Any]] {
        return SharedCar.conversations().filter { $0["canReply"] as? Bool ?? true }
    }

    /// Conversations whose title matches the name Siri heard (or a part of it).
    private func matches(_ p: INPerson, in all: [[String: Any]]) -> [[String: Any]] {
        if let id = p.customIdentifier, let c = all.first(where: { Self.str($0, "id") == id }) { return [c] }
        let heard = Self.fold(p.displayName.isEmpty ? (p.personHandle?.value ?? "") : p.displayName)
        guard !heard.isEmpty else { return [] }
        let exact = all.filter { Self.fold(Self.str($0, "title")) == heard }
        if !exact.isEmpty { return exact }
        return all.filter {
            let t = Self.fold(Self.str($0, "title"))
            return !t.isEmpty && (t.contains(heard) || heard.contains(t))
        }
    }

    // MARK: - Send a message

    func resolveRecipients(for intent: INSendMessageIntent,
                           with completion: @escaping ([INSendMessageRecipientResolutionResult]) -> Void) {
        guard let wanted = intent.recipients, !wanted.isEmpty else {
            completion([INSendMessageRecipientResolutionResult(personResolutionResult: INPersonResolutionResult.needsValue())])
            return
        }
        let all = replyable
        var results: [INSendMessageRecipientResolutionResult] = []
        for p in wanted {
            let found = matches(p, in: all)
            switch found.count {
            case 0:
                results.append(INSendMessageRecipientResolutionResult(personResolutionResult: INPersonResolutionResult.unsupported()))
            case 1:
                results.append(INSendMessageRecipientResolutionResult(personResolutionResult: INPersonResolutionResult.success(with: person(found[0]))))
            default:
                let options = found.prefix(5).map { person($0) }
                results.append(INSendMessageRecipientResolutionResult(personResolutionResult: INPersonResolutionResult.disambiguation(with: options)))
            }
        }
        completion(results)
    }

    func resolveContent(for intent: INSendMessageIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        let text = intent.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        completion(text.isEmpty ? INStringResolutionResult.needsValue() : INStringResolutionResult.success(with: text))
    }

    func handle(intent: INSendMessageIntent, completion: @escaping (INSendMessageIntentResponse) -> Void) {
        let text = intent.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let all = replyable
        let targets = (intent.recipients ?? []).compactMap { matches($0, in: all).first }
        guard !text.isEmpty, !targets.isEmpty else {
            completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
            return
        }
        for c in targets {
            SharedCar.post(["type": "reply", "conversation": Self.str(c, "id"), "text": text])
        }
        completion(INSendMessageIntentResponse(code: .success, userActivity: nil))
    }

    // MARK: - Mark as read

    func handle(intent: INSetMessageAttributeIntent, completion: @escaping (INSetMessageAttributeIntentResponse) -> Void) {
        if intent.attribute == .read {
            for id in intent.identifiers ?? [] where !id.isEmpty {
                SharedCar.post(["type": "read", "conversation": id])
            }
        }
        completion(INSetMessageAttributeIntentResponse(code: .success, userActivity: nil))
    }
}
