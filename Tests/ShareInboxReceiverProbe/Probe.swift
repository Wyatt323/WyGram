import Foundation
import UIKit
import SwiftSignalKit
import SGAppGroupIdentifier

// Shells expose the same readiness/lock/activity signals. They contain no
// Telegram accounts and do not replace the receiver's control flow.
final class ViewController: UIViewController {
    func dismiss(completion: (() -> Void)? = nil) { self.dismiss(animated: false, completion: completion) }
}
final class ProbeRoot: UIViewController {
    var currentWindow: UIWindow? { self.view.window }
}
final class AppLockContextImpl {
    let locked = Promise<Bool>(false)
    var isCurrentlyLocked: Signal<Bool, NoError> { self.locked.get() }
}
final class Bindings {
    let active = Promise<Bool>(true)
    var applicationIsActive: Signal<Bool, NoError> { self.active.get() }
}
final class Shared {
    let appLockContext: Any? = AppLockContextImpl()
    let applicationBindings = Bindings()
}
final class AccountShell { let sharedContext = Shared() }
final class AuthorizedApplicationContext {
    let context = AccountShell()
    let rootController = ProbeRoot()
    let isReady = Promise<Bool>(true)
    var lock: AppLockContextImpl { self.context.sharedContext.appLockContext as! AppLockContextImpl }
    var active: Promise<Bool> { self.context.sharedContext.applicationBindings.active }
}

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
@objc(ShareReceiverProbeScene) final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    let host = UIViewController()
    var checks: [[String: Any]] = []
    var started = false
    var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        let window = UIWindow(windowScene: scene as! UIWindowScene)
        window.rootViewController = host
        host.view.backgroundColor = .systemBackground
        self.window = window
        window.makeKeyAndVisible()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !started else { return }; started = true
        Task { @MainActor in await run() }
    }
    func check(_ name: String, _ passed: Bool) {
        checks.append(["name": name, "passed": passed])
        print("\(passed ? "PASS" : "FAIL") \(name)")
    }
    func pause(_ seconds: Double = 0.12) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    func wait(_ condition: () -> Bool) async { for _ in 0..<40 { if condition() { return }; await pause() } }
    func attach(_ context: AuthorizedApplicationContext) {
        host.addChild(context.rootController)
        context.rootController.view.frame = host.view.bounds
        host.view.addSubview(context.rootController.view)
        context.rootController.didMove(toParent: host)
    }
    func detach(_ context: AuthorizedApplicationContext) {
        context.rootController.willMove(toParent: nil)
        context.rootController.view.removeFromSuperview()
        context.rootController.removeFromParent()
    }
    func inbox(_ name: String) -> WyGramShareInbox { WyGramShareInbox(directory: docs.appendingPathComponent("fixtures/" + name)) }
    @discardableResult func publish(_ inbox: WyGramShareInbox) -> WyGramShareInbox.Batch {
        let source = docs.appendingPathComponent("fixture.txt")
        try! Data("NON-SECRET SHARED FILE FIXTURE".utf8).write(to: source)
        let id = UUID().uuidString
        try! inbox.begin(id: id)
        let item = try! inbox.copy(source: source, name: "fixture.txt", id: id, index: 0, remainingBytes: 1024)
        return try! inbox.finish(id: id, items: [item])
    }
    func startedScan(_ semaphore: DispatchSemaphore) -> Bool { semaphore.wait(timeout: .now()) == .success }
    func run() async {
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("fixtures"))
        check("probe-really-active", UIApplication.shared.applicationState == .active)
        do {
            let context = AuthorizedApplicationContext(), inbox = inbox("legacy-window")
            let batch = publish(inbox)
            let receiver = LegacyReceiver(); receiver.testInboxes = [inbox]
            receiver.check(context: context)
            await pause(0.25)
            attach(context)
            await pause(0.7)
            check("legacy-drops-ready-before-window-reproduced", receiver.presentations.isEmpty && context.rootController.currentWindow != nil)
            check("legacy-failure-leaves-batch-on-disk", inbox.pending().map { $0.id } == [batch.id])
            detach(context)
        }
        do {
            let context = AuthorizedApplicationContext(), inbox = inbox("fixed-window")
            let batch = publish(inbox)
            let receiver = FixedReceiver(); receiver.testInboxes = [inbox]
            receiver.check(context: context)
            await pause(0.25)
            check("fixed-waits-for-window", receiver.presentations.isEmpty)
            attach(context)
            await wait { !receiver.presentations.isEmpty }
            check("fixed-retries-after-real-window-attachment", receiver.presentations == [batch.id])
            for _ in 0..<10 { receiver.check(context: context) }
            NotificationCenter.default.post(name: WyGramShareInbox.importRequested, object: nil)
            await pause(0.65)
            check("repeated-foreground-and-manual-check-no-duplicate", receiver.presentations == [batch.id])
            check("presenting-does-not-delete-or-send-file", inbox.pending().count == 1 && (try? Data(contentsOf: inbox.fileURL(batch: batch, item: batch.items[0]))) == Data("NON-SECRET SHARED FILE FIXTURE".utf8))
            receiver.deactivate(); detach(context)
        }
        for gate in ["ready", "active", "lock"] {
            let context = AuthorizedApplicationContext(), inbox = inbox(gate)
            let batch = publish(inbox)
            attach(context)
            if gate == "ready" { context.isReady.set(.single(false)) }
            if gate == "active" { context.active.set(.single(false)) }
            if gate == "lock" { context.lock.locked.set(.single(true)) }
            let receiver = FixedReceiver(); receiver.testInboxes = [inbox]
            receiver.check(context: context)
            await pause(0.2)
            check("waits-for-\(gate)", receiver.presentations.isEmpty)
            context.isReady.set(.single(true)); context.active.set(.single(true)); context.lock.locked.set(.single(false))
            await wait { !receiver.presentations.isEmpty }
            check("continuous-signal-resumes-after-\(gate)", receiver.presentations == [batch.id])
            receiver.deactivate(); detach(context)
        }
        do {
            let context = AuthorizedApplicationContext(), inbox = inbox("late-publication")
            attach(context)
            let receiver = FixedReceiver(); receiver.testInboxes = [inbox]
            receiver.check(context: context)
            await pause(0.25)
            check("empty-scan-shows-no-picker", receiver.presentations.isEmpty)
            let batch = publish(inbox)
            await wait { !receiver.presentations.isEmpty }
            check("publication-after-initial-scan-is-received", receiver.presentations == [batch.id])
            receiver.deactivate(); detach(context)
        }
        do {
            let context = AuthorizedApplicationContext(), inbox = inbox("no-more-window")
            attach(context)
            _ = publish(inbox)
            let gate = DispatchSemaphore(value: 0), started = DispatchSemaphore(value: 0)
            var seen = 0
            let c = WyGramShareInboxCoordinator(inboxes: { started.signal(); gate.wait(); return [inbox] }, canPresent: { context.rootController.currentWindow != nil }, present: { _ in seen += 1; return true }, retryInterval: 0.03)
            c.setEligible(true)
            await pause(0.1)
            check("disk-scan-started", startedScan(started))
            detach(context)
            gate.signal()
            await pause(0.15)
            check("window-loss-during-io-does-not-present", seen == 0)
            attach(context); gate.signal()
            await wait { seen == 1 }
            check("window-return-during-io-retry-presents-once", seen == 1)
            c.stop(); detach(context)
        }
        for stop in [false, true] {
            let inbox = inbox("race-\(stop)"); _ = publish(inbox)
            let gate = DispatchSemaphore(value: 0)
            var seen = 0
            let c = WyGramShareInboxCoordinator(inboxes: { gate.wait(); return [inbox] }, canPresent: { true }, present: { _ in seen += 1; return true }, retryInterval: 0.03)
            c.setEligible(true)
            await pause(0.1)
            if stop { c.stop() } else { c.setEligible(false) }
            gate.signal()
            await pause(0.15)
            check("\(stop ? "logout" : "lock-or-background")-during-io-blocks-picker", seen == 0 && inbox.pending().count == 1)
            if !stop {
                gate.signal(); c.setEligible(true)
                await wait { seen == 1 }
                check("unlock-or-foreground-after-io-receives-preserved-file", seen == 1)
            }
            c.stop()
        }
        do {
            let inbox = inbox("manual-after-bounded-retry")
            let scans = Atomic<Int>(value: 0)
            var seen = 0
            let c = WyGramShareInboxCoordinator(inboxes: { _ = scans.modify { $0 + 1 }; return [inbox] }, canPresent: { true }, present: { _ in seen += 1; return true }, retryInterval: 0.02, retryLimit: 2)
            c.setEligible(true)
            await pause(0.3)
            check("empty-retries-are-bounded", scans.with { $0 == 3 })
            _ = publish(inbox)
            await pause(0.1)
            check("no-indefinite-disk-polling", seen == 0 && scans.with { $0 == 3 })
            c.refresh()
            await wait { seen == 1 }
            check("explicit-refresh-receives-after-retry-budget", seen == 1)
            c.stop()
        }
        do {
            let first = inbox("order-first"), second = inbox("order-second")
            let oldest = publish(second)
            await pause(0.05)
            let newest = publish(first)
            var seen: [String] = []
            let c = WyGramShareInboxCoordinator(inboxes: { [first, second] }, canPresent: { true }, present: { seen.append($0.batch.id); return true }, retryInterval: 0.02)
            c.setEligible(true)
            await wait { !seen.isEmpty }
            check("oldest-batch-across-containers-first", seen == [oldest.id])
            second.remove(id: oldest.id)
            c.finished()
            await wait { seen.count == 2 }
            check("next-batch-after-user-dismissal", seen == [oldest.id, newest.id])
            c.stop()
        }
        let result: [String: Any] = ["runID": ProcessInfo.processInfo.environment["PROBE_RUN_ID"] ?? "", "passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks]
        try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: docs.appendingPathComponent("results.json"))
    }
}
