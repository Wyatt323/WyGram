import UIKit
import Foundation
import CryptoKit
import UserNotifications
import MtProtoKit
import TelegramCore
import SGAppGroupIdentifier
import SGSettingsUI
import TelegramPresentationData
import Display
import LegacyUI
import NavigationBarImpl

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
@objc(PushCompatibilityProbeSceneDelegate) final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var displayWindow: Window1?
    var checks: [String] = []
    var uiAttempts = 0
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); self.checks.append(label) }
    func packet(_ json: [String: Any], account: WyGramPushBridgeAccount) -> String {
        let jsonData = try! JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
        var length = Int32(jsonData.count).littleEndian
        var plain = withUnsafeBytes(of: &length) { Data($0) } + jsonData
        let padding = 16 - plain.count % 16 + 16
        plain.append(Data(repeating: 99, count: padding))
        func hash(_ value: Data) -> Data { Data(SHA256.hash(data: value)) }
        let key = account.key
        let msgKey = hash(key.subdata(in: 96 ..< 128) + plain).subdata(in: 8 ..< 24)
        let a = hash(msgKey + key.subdata(in: 8 ..< 44)), b = hash(key.subdata(in: 48 ..< 84) + msgKey)
        let aesKey = a.subdata(in: 0 ..< 8) + b.subdata(in: 8 ..< 24) + a.subdata(in: 24 ..< 32)
        let iv = b.subdata(in: 0 ..< 8) + a.subdata(in: 8 ..< 24) + b.subdata(in: 24 ..< 32)
        return (account.keyId + msgKey + MTAesEncrypt(plain, aesKey, iv)!).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func request(_ json: [String: Any], account: WyGramPushBridgeAccount, alert: Bool = true) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let aps: [String: Any]
        if alert { aps = ["alert": ["body": "Encrypted notification"], "mutable-content": 1] }
        else { aps = ["content-available": 1] }
        content.userInfo = ["p": self.packet(json, account: account), "aps": aps]
        content.sound = .default
        return content
    }
    func exercise() {
        let a = WyGramPushBridgeAccount(recordId: 17, keyId: Data(repeating: 1, count: 8), key: Data((0 ..< 256).map { UInt8($0) }))
        let b = WyGramPushBridgeAccount(recordId: 18, keyId: Data(repeating: 2, count: 8), key: a.key)
        let payload: [String: Any] = ["aps": ["alert": ["title": "Private sender", "body": "PRIVATE_TEST_MESSAGE"], "sound": "default"], "from_id": "123456", "msg_id": "7"]
        let incoming = self.request(payload, account: a)
        let result = wygramNotificationFromBridge(incoming, accounts: [b, a])!
        self.check(result.title == "WyGram" && !result.body.isEmpty && result.sound != nil, "Authenticated incoming message becomes a visible generic notification")
        self.check(!result.body.contains("PRIVATE_TEST_MESSAGE") && !result.title.contains("Private sender"), "App-local compatibility mode never exposes message or sender previews")
        self.check(result.userInfo["accountId"] as? String == "17" && result.userInfo["from_id"] as? String == "123456", "Authenticated routing selects the correct account without its database")
        self.check(result.userInfo["p"] as? String == incoming.userInfo["p"] as? String, "The original encrypted payload remains intact")
        self.check(wygramNotificationFromBridge(incoming, accounts: [b]) == nil, "Another account's key cannot process the message")
        let silent = wygramNotificationFromBridge(self.request(payload, account: a, alert: false), accounts: [a])!
        self.check(silent.title.isEmpty && silent.body.isEmpty && silent.sound == nil, "A silent outer push is never promoted to an alert")
        var mutedPayload = payload; mutedPayload["silent"] = "1"
        let muted = wygramNotificationFromBridge(self.request(mutedPayload, account: a), accounts: [a])!
        self.check(!muted.body.isEmpty && muted.sound == nil, "An authenticated silent-message flag does not acquire sound")
        for service in ["MESSAGE_DELETED", "READ_HISTORY", "MESSAGE_MUTED", "SESSION_REVOKE", "READ_REACTION"] {
            let content = wygramNotificationFromBridge(self.request(["loc-key": service], account: a), accounts: [a])!
            self.check(content.body.isEmpty && content.title.isEmpty && content.sound == nil, "Service update \(service) does not become a generic new message")
        }
        let corrupt = incoming.mutableCopy() as! UNMutableNotificationContent
        var bytes = Data(base64Encoded: self.packet(payload, account: a).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - self.packet(payload, account: a).count % 4) % 4))!
        bytes[bytes.count - 1] ^= 1; corrupt.userInfo["p"] = bytes.base64EncodedString()
        self.check(wygramNotificationFromBridge(corrupt, accounts: [a]) == nil, "Modified ciphertext fails Telegram's authentication check")
        for length in [0, 8, 16, 24, 39, 41] {
            let malformed = UNMutableNotificationContent(); malformed.userInfo = ["p": Data(repeating: 0, count: length).base64EncodedString()]
            self.check(wygramNotificationFromBridge(malformed, accounts: [a]) == nil, "Malformed encrypted length \(length) is rejected without a range trap")
        }
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let initial = UIWindow(windowScene: scene); initial.rootViewController = UIViewController(); initial.makeKeyAndVisible(); self.window = initial
        self.exercise()
        WyGramPushStatus.record("apple", value: CommandLine.arguments.contains("--failure") ? "failed_3000" : "registered")
        WyGramPushStatus.record("server.17", value: CommandLine.arguments.contains("--failure") ? "APP_PUSH_CERT_MISSING" : "accepted")
        defaultNavigationBarImpl = { NavigationBarImpl(presentationData: $0) }
        let strings = PresentationStrings(primaryComponent: PresentationStrings.Component(languageCode: "zh-hans", localizedName: "简体中文", pluralizationRulesCode: nil, dict: [:]), secondaryComponent: nil, groupingSeparator: "")
        let controller = wygramPushStatusViewController(theme: defaultPresentationTheme, strings: strings, accountId: 17, retry: {})
        let theme = NavigationControllerTheme(statusBar: .black, navigationBar: NavigationBarTheme(overallDarkAppearance: false, buttonColor: .systemBlue, disabledButtonColor: .gray, primaryTextColor: .black, backgroundColor: .systemGroupedBackground, enableBackgroundBlur: true, separatorColor: .clear, badgeBackgroundColor: .systemBlue, badgeStrokeColor: .white, badgeTextColor: .white, accentButtonColor: .systemBlue, accentDisabledButtonColor: .gray, accentForegroundColor: .white), emptyAreaColor: .systemGroupedBackground)
        let navigation = NavigationController(mode: .single, theme: theme); navigation.setViewControllers([controller], animated: false)
        let (window, host) = nativeWindowHostView(); window.windowScene = scene; window.frame = scene.coordinateSpace.bounds
        let display = Window1(hostView: host, statusBarHost: ProbeStatusHost(window: window)); display.viewController = navigation; self.displayWindow = display
        initial.isHidden = true; self.window = window; window.makeKeyAndVisible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.captureUI(controller) }
    }
    func captureUI(_ controller: ViewController) {
        guard let legacy = controller as? LegacyController, let table = legacy.legacyController as? UITableViewController else { preconditionFailure("No production status table") }
        self.uiAttempts += 1
        if table.tableView.numberOfRows(inSection: 0) != 7 && self.uiAttempts < 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.captureUI(controller) }
            return
        }
        self.check(table.tableView.numberOfRows(inSection: 0) == 7, "Production notification status view renders all seven diagnostic rows")
        self.check(table.tableView.numberOfRows(inSection: 1) == 4, "Production notification status view renders retry, local test, copy and system-settings actions")
        let server = table.tableView.dataSource!.tableView(table.tableView, cellForRowAt: IndexPath(row: 2, section: 0)).detailTextLabel?.text ?? ""
        self.check(server.contains(CommandLine.arguments.contains("--failure") ? "APP_PUSH_CERT_MISSING" : "待验证投递"), "Registration rejection and accepted-but-unverified delivery are displayed truthfully")
        let report: [String: Any] = ["passed": true, "checks": self.checks, "scope": "Production bridge decryptor tested with synthetic MTProto-authenticated encrypted notification packets and real status view. No actual Telegram account, signing install or remote APNs delivery."]
        try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: self.documents.appendingPathComponent("results.json"))
    }
}
private final class ProbeStatusHost: StatusBarHost {
    weak var window: UIWindow?
    init(window: UIWindow) { self.window = window }
    var isApplicationInForeground: Bool { true }
    var statusBarFrame: CGRect { self.window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero }
    var keyboardWindow: UIWindow? { nil }
    var keyboardView: UIView? { nil }
}
