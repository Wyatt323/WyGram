import Foundation
import UIKit
import WGAppUpdate
import SGSettingsUI
import Display
import LegacyUI
import NavigationBarImpl
import TelegramPresentationData

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static var responseCode = 200
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.github.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let value: [String: Any] = ["tag_name": "v1.0.12-b19", "draft": false, "prerelease": false,
            "body": "修复问题并增加在线更新。\n完整测试更新说明 · Release notes.",
            "assets": [["name": "WyGram.1.0.12.ipa", "size": 72000000, "digest": "sha256:" + String(repeating: "a", count: 64), "browser_download_url": "https://github.com/Wyatt323/WyGram/releases/download/v1.0.12-b19/WyGram.1.0.12.ipa"]]]
        let data = try! JSONSerialization.data(withJSONObject: value)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.responseCode, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@_silgen_name("WGCheckCryptoCoexistence") private func checkCryptoCoexistence()

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UserDefaults.standard.set(false, forKey: "WyGram.AppUpdate.Check")
        URLProtocol.registerClass(FixtureProtocol.self)
        return true
    }
}

@objc(OnlineUpdateProbeScene) final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var display: Window1?
    var checks: [[String: Any]] = []
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    func check(_ name: String, _ value: Bool) { checks.append(["name": name, "passed": value]) }
    func pause(_ seconds: Double = 0.4) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
    func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    func snapshot(_ name: String) {
        guard let window else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try? image.pngData()?.write(to: documents.appendingPathComponent(name + ".png"))
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        let first = UIWindow(windowScene: scene as! UIWindowScene)
        first.rootViewController = UIViewController(); first.makeKeyAndVisible(); window = first
        Task { @MainActor in await run(scene as! UIWindowScene) }
    }
    func run(_ scene: UIWindowScene) async {
        checkCryptoCoexistence()
        check("signer-and-network-crypto-coexist", true)
        defaultNavigationBarImpl = { NavigationBarImpl(presentationData: $0) }
        let dark = CommandLine.arguments.contains("--dark"), large = CommandLine.arguments.contains("--large"), english = CommandLine.arguments.contains("--english")
        let theme = dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme
        let strings = PresentationStrings(primaryComponent: .init(languageCode: english ? "en" : "zh-hans", localizedName: "Test", pluralizationRulesCode: nil, dict: [:]), secondaryComponent: nil, groupingSeparator: ",")
        let updater = WGAppUpdater(sessionConfiguration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FixtureProtocol.self]
            return configuration
        })
        let controller = wygramAppUpdateViewController(theme: theme, strings: strings, updater: updater, presentMessage: { _, _ in })
        let bar = NavigationBarTheme(overallDarkAppearance: dark, buttonColor: theme.rootController.navigationBar.accentTextColor, disabledButtonColor: .gray, primaryTextColor: theme.rootController.navigationBar.primaryTextColor, backgroundColor: theme.rootController.navigationBar.opaqueBackgroundColor, enableBackgroundBlur: true, separatorColor: .clear, badgeBackgroundColor: .systemBlue, badgeStrokeColor: .white, badgeTextColor: .white, accentButtonColor: .systemBlue, accentDisabledButtonColor: .gray, accentForegroundColor: .white)
        let navigation = NavigationController(mode: .single, theme: NavigationControllerTheme(statusBar: dark ? .white : .black, navigationBar: bar, emptyAreaColor: theme.list.blocksBackgroundColor))
        let root = ViewController(navigationBarPresentationData: NavigationBarPresentationData(theme: bar, strings: NavigationBarStrings(back: "返回", close: "关闭"))); root.title = "设置"
        navigation.setViewControllers([root], animated: false)
        let (window, host) = nativeWindowHostView(); window.windowScene = scene; window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        let display = Window1(hostView: host, statusBarHost: ProbeStatusHost(window: window)); display.viewController = navigation; self.display = display
        self.window?.isHidden = true; self.window = window; window.makeKeyAndVisible()
        await pause()
        navigation.pushViewController(controller)
        if large { navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: controller) }
        await pause(1.5)
        guard let legacy = controller as? LegacyController, let table = legacy.legacyController as? UITableViewController else { return }
        check("four-settings-groups", table.tableView.numberOfSections == 4)
        let navBottom = controller.navigationLayout(layout: controller.currentlyAppliedLayout!).navigationFrame.maxY
        check("content-below-navigation", table.view.convert(table.view.bounds, to: controller.view).minY >= navBottom - 1)
        check("grouped-layout", table.tableView.style == .insetGrouped)
        check("correct-title-and-brand", controller.title?.hasPrefix("WyGram") == true)
        check("signer-not-configured-without-certificate", !updater.isConfigured)
        let credentialCell = table.tableView.dataSource!.tableView(table.tableView, cellForRowAt: IndexPath(row: 0, section: 2))
        check("no-fake-certificate-status", credentialCell.textLabel?.text == wygramUpdateText("AppUpdate.NotConfigured", chinese: !english))
        snapshot("initial")
        FixtureProtocol.responseCode = 404; updater.check(); await pause(1)
        check("no-release-is-not-a-connection-error", updater.stage == .noRelease)
        FixtureProtocol.responseCode = 200; updater.check(); await pause(1)
        check("actual-check-parses-release", updater.release?.version == "1.0.12" && updater.release?.build == 19 && updater.stage == .available)
        check("two-new-version-rows", table.tableView.numberOfRows(inSection: 0) == 6)
        check("github-release-is-wygram", updater.githubReleaseURL.absoluteString == "https://github.com/Wyatt323/WyGram/releases/tag/v1.0.12-b19")
        let prepare = table.tableView.dataSource!.tableView(table.tableView, cellForRowAt: IndexPath(row: 5, section: 0))
        check("signing-is-disabled-without-certificate", !prepare.isUserInteractionEnabled && prepare.detailTextLabel?.text?.isEmpty == false)
        table.tableView.delegate?.tableView?(table.tableView, didSelectRowAt: IndexPath(row: 4, section: 0)); await pause()
        let notes = table.tableView.dataSource!.tableView(table.tableView, cellForRowAt: IndexPath(row: 4, section: 0))
        check("release-notes-expand-with-full-text", notes.detailTextLabel?.text == updater.release?.notes)
        table.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false); await pause()
        let first = table.tableView.cellForRow(at: IndexPath(row: 0, section: 0))!
        check("dynamic-type", !large || (first.textLabel?.font.pointSize ?? 0) > 30)
        table.tableView.setContentOffset(.zero, animated: false); await pause()
        snapshot("available")
        for _ in 0..<3 { table.tableView.scrollToRow(at: IndexPath(row: 0, section: 3), at: .bottom, animated: false); await pause(0.2); table.tableView.layoutIfNeeded() }
        let last = table.tableView.convert(table.tableView.rectForRow(at: IndexPath(row: 0, section: 3)), to: window)
        check("last-setting-above-home-indicator", last.maxY <= window.bounds.height - controller.currentlyAppliedLayout!.intrinsicInsets.bottom + 1)
        snapshot("certificate")
        FixtureProtocol.responseCode = 503; updater.check(); await pause(1)
        if case .failed = updater.stage { check("network-failure-shown", true) } else { check("network-failure-shown", false) }
        updater.cancel()
        check("retry-retains-selected-release", updater.stage == .available && updater.release?.build == 19)
        check("credentials-not-imported-by-update-check", updater.certificateName.isEmpty && updater.savedProfileCount == 0)
        let report: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks, "dark": dark, "large": large, "english": english, "runID": ProcessInfo.processInfo.environment["WYGRAM_UPDATE_PROBE_RUN_ID"] ?? "none"]
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: documents.appendingPathComponent("results.json"))
    }
}

private final class ProbeStatusHost: StatusBarHost {
    weak var window: UIWindow?; init(window: UIWindow) { self.window = window }
    var isApplicationInForeground: Bool { true }
    var statusBarFrame: CGRect { window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero }
    var keyboardWindow: UIWindow? { nil }
    var keyboardView: UIView? { nil }
}
