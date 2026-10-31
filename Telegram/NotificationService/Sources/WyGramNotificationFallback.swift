import Foundation
import UserNotifications

func wygramNotificationWithoutSharedStorage(_ initial: UNNotificationContent) -> UNNotificationContent {
    guard let content = initial.mutableCopy() as? UNMutableNotificationContent else { return initial }
    let aps = content.userInfo["aps"] as? [String: Any]
    // Preserve silent pushes. A fallback must not expose encrypted message text.
    guard aps?["alert"] != nil || !content.title.isEmpty || !content.body.isEmpty else { return initial }
    if content.title.isEmpty { content.title = "WyGram" }
    if content.body.isEmpty {
        let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        content.body = chinese ? "你收到一条新通知，打开 WyGram 查看。" : "You have a new notification. Open WyGram to view it."
        content.categoryIdentifier = ""
    }
    return content
}
