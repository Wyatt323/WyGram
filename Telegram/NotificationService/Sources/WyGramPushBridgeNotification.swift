import Foundation
import UserNotifications
import SGAppGroupIdentifier
import TelegramCore

// App-local account databases stay in place. A small, protected notification-key
// bridge lets the extension recognize authenticated messages without opening or
// copying the main account database. Compatibility alerts never reveal previews.
func wygramNotificationFromBridge(_ initial: UNNotificationContent, accounts: [WyGramPushBridgeAccount]) -> UNNotificationContent? {
    guard var encoded = initial.userInfo["p"] as? String, encoded.count <= 1024 * 1024 else { return nil }
    encoded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while encoded.count % 4 != 0 { encoded.append("=") }
    guard let packet = Data(base64Encoded: encoded), packet.count >= 40, (packet.count - 24) % 16 == 0,
          let keyId = notificationPayloadKeyId(data: packet),
          let account = accounts.first(where: { $0.keyId == keyId && $0.keyId.count == 8 && $0.key.count == 256 }),
          let decrypted = decryptedNotificationPayload(key: MasterNotificationKey(id: account.keyId, data: account.key), data: packet),
          let payload = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any],
          let content = initial.mutableCopy() as? UNMutableNotificationContent else { return nil }

    // State updates and silent notifications must not become new-message alerts.
    let outerAPS = initial.userInfo["aps"] as? [String: Any]
    let aps = payload["aps"] as? [String: Any]
    let serviceUpdate = payload["loc-key"] != nil
    let visible = !serviceUpdate && aps?["alert"] != nil && outerAPS?["alert"] != nil
    content.title = visible ? "WyGram" : ""
    content.subtitle = ""
    content.body = visible ? ((Locale.preferredLanguages.first?.hasPrefix("zh") ?? false) ? "你收到一条新消息，打开 WyGram 查看。" : "You have a new message. Open WyGram to view it.") : ""
    content.categoryIdentifier = ""
    content.attachments = []
    content.userInfo["accountId"] = String(account.recordId)
    if !visible || String(describing: payload["silent"] ?? "0") != "0" {
        content.sound = nil
    } else if content.sound == nil, let sound = aps?["sound"] as? String, !sound.isEmpty, sound != "0" {
        content.sound = .default
    }
    // Carry authenticated routing identifiers, never decrypted message text.
    for key in ["from_id", "chat_id", "channel_id", "msg_id", "topic_id"] {
        if let value = payload[key] as? String, Int64(value) != nil { content.userInfo[key] = value }
    }
    return content
}
