import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

@main final class App: UIResponder, UIApplicationDelegate {
    private var checks: [[String: Any]] = []

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    private func check(_ name: String, _ value: Bool) {
        self.checks.append(["name": name, "passed": value])
    }

    fileprivate func runChecks() {
        var now: TimeInterval = 0
        let foreground = ValuePromise<Bool>(true)
        var readers: [ValuePromise<Bool>] = []
        var loading: WyGramChatListLoading? = WyGramChatListLoading(foreground: foreground.get(), readLocalState: {
            let ready = ValuePromise<Bool>(false)
            readers.append(ready)
            return ready.get()
        }, clock: { now })
        var phase: WyGramChatListLoading.Phase = .idle
        let subscription = loading!.phase.start(next: { phase = $0 })
        self.check("cold-start-does-not-add-artificial-loading", phase == .idle && readers.isEmpty)

        foreground.set(false)
        now = 10
        foreground.set(true)
        self.check("brief-app-switch-has-no-resume-probe", phase == .idle && readers.isEmpty)

        now = 20
        foreground.set(false)
        now = 50
        foreground.set(true)
        self.check("long-background-immediately-shows-local-restore", phase == .restoring && readers.count == 1)
        now = 110
        self.check("one-minute-local-wait-keeps-feedback-visible", phase == .restoring)
        foreground.set(true)
        self.check("duplicate-foreground-does-not-restart-or-hide-restore", phase == .restoring && readers.count == 1)
        readers[0].set(false)
        self.check("not-ready-value-cannot-hide-loading", phase == .restoring)

        let id = loading!.beginOpening()!
        self.check("chat-tap-immediately-shows-opening", phase == .opening)
        self.check("repeated-chat-taps-do-not-enqueue-another-open", loading!.beginOpening() == nil)
        readers[0].set(true)
        self.check("local-ready-does-not-hide-pending-chat-open", phase == .opening)
        let chatReady = ValuePromise<Bool>(false)
        loading!.waitForOpenedChat(id, ready: chatReady.get())
        self.check("stack-change-before-chat-ready-keeps-activity", phase == .opening)
        chatReady.set(true)
        self.check("chat-ready-clears-activity", phase == .idle)

        let oldId = loading!.beginOpening()!
        foreground.set(false)
        self.check("background-clears-opening-and-rejects-stale-query", phase == .idle && !loading!.isCurrentOpening(oldId))
        self.check("background-cannot-start-navigation", loading!.beginOpening() == nil)
        now = 150
        foreground.set(true)
        self.check("new-long-resume-gets-a-fresh-readiness-probe", phase == .restoring && readers.count == 2)
        readers[0].set(true)
        self.check("previous-resume-cannot-clear-new-feedback", phase == .restoring)
        let newId = loading!.beginOpening()!
        loading!.finishOpening(oldId)
        self.check("old-navigation-completion-cannot-clear-new-open", phase == .opening && loading!.isCurrentOpening(newId))
        loading!.cancelOpening()
        self.check("leaving-list-clears-open-but-preserves-resume", phase == .restoring)
        readers[1].set(true)
        self.check("acknowledged-local-readiness-clears-resume", phase == .idle)

        now = 200
        foreground.set(false)
        now = 260
        foreground.set(true)
        now = 270
        foreground.set(false)
        readers[2].set(true)
        self.check("late-readiness-after-background-stays-idle", phase == .idle)
        now = 280
        foreground.set(true)
        self.check("short-next-return-does-not-reuse-old-restore", phase == .idle)

        let data = defaultPresentationData()
        for local in [WyGramChatListLoading.Phase.restoring, .opening] {
            let title = productionTitle(networkState: .online(proxy: nil), localLoading: local, presentationData: data)
            self.check("online-\(local)-uses-loading-text-and-spinner", title.activity && title.text == data.strings.Channel_NotificationLoading)
            let waiting = productionTitle(networkState: .waitingForNetwork, localLoading: local, presentationData: data)
            self.check("offline-\(local)-keeps-network-explanation", waiting.activity && waiting.text == data.strings.State_WaitingForNetwork)
            let connecting = productionTitle(networkState: .connecting(proxy: nil), localLoading: local, presentationData: data)
            self.check("connecting-\(local)-keeps-connection-explanation", connecting.activity && connecting.text == data.strings.State_Connecting)
            let updating = productionTitle(networkState: .updating(proxy: nil), localLoading: local, presentationData: data)
            self.check("syncing-\(local)-keeps-sync-explanation", updating.activity && updating.text == data.strings.State_Updating)
        }
        let idle = productionTitle(networkState: .online(proxy: nil), localLoading: .idle, presentationData: data)
        self.check("fully-ready-restores-normal-chat-title", !idle.activity && idle.text == data.strings.DialogList_Title)

        let isReleased = { [weak loading] in loading == nil }
        loading = nil
        self.check("controller-release-disposes-lifecycle-observer", isReleased())
        subscription.dispose()
        let report: [String: Any] = [
            "passed": self.checks.allSatisfy { $0["passed"] as? Bool == true },
            "checks": self.checks,
            "runID": ProcessInfo.processInfo.environment["WYGRAM_LOADING_PROBE_RUN_ID"] ?? "",
            "scope": "Production loading coordinator and verbatim production header switch, real SwiftSignalKit on iOS; controlled readiness/monotonic clock. No signed-device suspension, real account or complete chat navigation."
        ]
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("results.json")
        try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path)
        print("Loading checks: \(self.checks.count), passed: \(report["passed"]!)")
    }
}

@objc(WyGramChatListLoadingProbeScene)
final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var started = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !self.started else { return }
        self.started = true
        DispatchQueue.main.async { (UIApplication.shared.delegate as? App)?.runChecks() }
    }
}
