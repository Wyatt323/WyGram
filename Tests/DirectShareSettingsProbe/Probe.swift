import UIKit
import Darwin
import SGAppGroupIdentifier

// The production settings class is compiled below. Only its presentation theme
// and outer legacy wrapper are replaced; table actions/alerts are actual UIKit.
struct PresentationTheme {
    struct List { let itemAccentColor = UIColor.systemBlue }
    let list = List()
}
class WyGramSettingsTableController: UITableViewController {
    let settingsTheme: PresentationTheme
    init(theme: PresentationTheme) { settingsTheme = theme; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    func style(_ cell: UITableViewCell) { cell.textLabel?.numberOfLines = 0; cell.detailTextLabel?.numberOfLines = 0 }
}
var probeGroups: [WyGramDirectShare.Group] = []
let probeDefaults = UserDefaults(suiteName: "app.wygram.settingsprobe." + UUID().uuidString)!
let probeBundle = "app.wygram.fixture"
func probeInboxes() -> [WyGramShareInbox] { probeGroups.map { WyGramShareInbox(directory: $0.url.appendingPathComponent("WyGramShareInbox/" + probeBundle)) } }

// PRODUCTION_SETTINGS_CLASS

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
@objc(DirectShareSettingsScene) final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var checks: [[String: Any]] = []
    func check(_ name: String, _ value: Bool) { checks.append(["name": name, "passed": value]) }
    func pause() async { try? await Task.sleep(nanoseconds: 350_000_000) }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        window = UIWindow(windowScene: scene as! UIWindowScene)
        Task { @MainActor in try await run() }
    }
    func run() async throws {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        for i in 0..<5 {
            let url = root.appendingPathComponent("group-\(i)")
            try fm.createDirectory(at: url.appendingPathComponent("telegram-data/accounts-metadata"), withIntermediateDirectories: true)
            try Data(repeating: UInt8(i), count: 48).write(to: url.appendingPathComponent("telegram-data/.tempkey"))
            probeGroups.append(.init(identifier: "group.fixture.\(i)", url: url))
        }
        probeDefaults.set("local", forKey: WyGramDirectShare.selectionKey)
        probeDefaults.set("occupied", forKey: WyGramDirectShare.resultKey)
        let controller = WyGramDirectShareSettings(theme: PresentationTheme(), chinese: true)
        window?.rootViewController = UINavigationController(rootViewController: controller)
        window?.makeKeyAndVisible()
        await pause()
        let row = IndexPath(row: 0, section: 1)
        func action() -> UITableViewCell { controller.tableView(controller.tableView, cellForRowAt: row) }
        check("five-legacy-root-stores-occupied", WyGramDirectShare.vacantGroups(probeGroups).isEmpty)
        check("enable-row-interactive-when-all-roots-occupied", action().isUserInteractionEnabled)
        if action().isUserInteractionEnabled { controller.tableView(controller.tableView, didSelectRowAt: row) }
        await pause()
        let alert = controller.presentedViewController as? UIAlertController
        check("tap-opens-enable-confirmation", alert?.title == "启用直接分享" && alert?.actions.count == 2)
        check("tap-does-not-migrate-before-confirmation", probeDefaults.string(forKey: WyGramDirectShare.requestKey) == nil)
        controller.dismiss(animated: false)
        await pause()
        let candidate = WyGramDirectShare.setupGroups(probeGroups)[0]
        _ = WyGramDirectShare.request(group: candidate, defaults: probeDefaults)
        controller.viewWillAppear(false)
        check("pending-action-stays-interactive", action().isUserInteractionEnabled && action().textLabel?.text == "取消启用")
        controller.tableView(controller.tableView, didSelectRowAt: row)
        check("cancel-clears-group-and-relative-location", probeDefaults.string(forKey: WyGramDirectShare.requestKey) == nil && probeDefaults.string(forKey: WyGramDirectShare.requestPathKey) == nil)
        let existing = probeGroups[0]
        for inbox in probeInboxes() { inbox.publishAccountStorage(group: existing.url) }
        probeDefaults.set("shared", forKey: WyGramDirectShare.selectionKey)
        controller.viewWillAppear(false)
        check("ready-mode-does-not-request-another-migration", !action().isUserInteractionEnabled)
        let status = controller.tableView(controller.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        check("ready-label-is-unambiguous", status.textLabel?.text == "直接分享已就绪")
        probeGroups = []
        probeDefaults.set("local", forKey: WyGramDirectShare.selectionKey)
        controller.viewWillAppear(false)
        check("missing-permission-row-is-actionable", action().isUserInteractionEnabled)
        if action().isUserInteractionEnabled { controller.tableView(controller.tableView, didSelectRowAt: row) }
        await pause()
        let missing = controller.presentedViewController as? UIAlertController
        check("missing-permission-explains-reason", missing?.title == "暂时无法启用" && (missing?.message?.contains("共同") ?? false))
        check("missing-permission-does-not-save-request", probeDefaults.string(forKey: WyGramDirectShare.requestKey) == nil)
        controller.dismiss(animated: false)
        await pause()
        probeGroups = [existing]
        precondition(chmod(existing.url.path, 0o500) == 0)
        defer { _ = chmod(existing.url.path, 0o700) }
        controller.viewWillAppear(false)
        check("denied-write-remains-actionable", action().isUserInteractionEnabled)
        controller.tableView(controller.tableView, didSelectRowAt: row)
        await pause()
        let denied = controller.presentedViewController as? UIAlertController
        check("denied-write-alert-has-real-posix-step", (denied?.message?.contains("probe-mkdir(") ?? false) && (denied?.message?.contains("系统拒绝") ?? false))
        controller.dismiss(animated: false)
        await pause()
        controller.tableView(controller.tableView, didSelectRowAt: IndexPath(row: 0, section: 3))
        let copied = UIPasteboard.general.string ?? ""
        check("copied-diagnostics-include-stage-and-code", copied.contains("目录实测:") && copied.contains("probe-mkdir("))
        check("copied-diagnostics-exclude-container-paths", !copied.contains(root.path) && !copied.contains("group.fixture"))
        let report: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks, "runID": ProcessInfo.processInfo.environment["WYGRAM_SHARE_PROBE_RUN_ID"] ?? "", "scope": "Production settings class with actual UIKit tables and alerts; injected signed-group discovery and defaults, minimal theme superclass. Not full Legacy wrapper, authenticated native ShareController or physical-device permissions."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: documents.appendingPathComponent("results.json"))
    }
}
