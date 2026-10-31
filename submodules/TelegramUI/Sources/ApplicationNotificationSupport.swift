import UserNotifications

func wygramForegroundNotificationOptions(isCurrentAccount: Bool, hasURL: Bool) -> UNNotificationPresentationOptions {
    // The active account uses Telegram's in-app banner. Unresolved and other
    // accounts need a system banner while the app is running.
    return isCurrentAccount && !hasURL ? [] : [.banner, .list, .sound]
}
