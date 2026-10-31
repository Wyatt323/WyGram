import Foundation
import UIKit
import UniformTypeIdentifiers
import SGAppGroupIdentifier

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
@objc(ShareProbeScene) final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    let root = UIViewController()
    var checks: [[String: Any]] = []
    var started = false
    var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        let window = UIWindow(windowScene: scene as! UIWindowScene)
        window.rootViewController = root
        root.view.backgroundColor = .systemBackground
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
    func pause(_ seconds: Double = 0.1) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    func wait(_ condition: () -> Bool) async { for _ in 0..<80 { if condition() { return }; await pause() } }
    func descendants(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(descendants) }
    func text(_ c: UIViewController) -> String { descendants(c.view).compactMap { ($0 as? UILabel)?.text }.joined(separator: "\n") }
    func button(_ c: UIViewController, _ title: String) -> UIButton? { descendants(c.view).compactMap { $0 as? UIButton }.first { $0.currentTitle == title } }
    func attach(_ c: UIViewController) {
        root.addChild(c); c.view.frame = root.view.bounds; root.view.addSubview(c.view); c.didMove(toParent: root)
    }
    func detach(_ c: UIViewController) { c.willMove(toParent: nil); c.view.removeFromSuperview(); c.removeFromParent() }
    func screenshot(_ name: String) {
        let renderer = UIGraphicsImageRenderer(bounds: root.view.bounds)
        let image = renderer.image { _ in root.view.drawHierarchy(in: root.view.bounds, afterScreenUpdates: true) }
        try? image.pngData()?.write(to: docs.appendingPathComponent(name + ".png"))
    }
    func provider(_ url: URL) -> NSItemProvider {
        let p = NSItemProvider()
        p.registerItem(forTypeIdentifier: UTType.fileURL.identifier, loadHandler: { completion, _, _ in completion?(url as NSURL, nil) })
        return p
    }
    var continueTitle: String {
        return "完成，手动打开 WyGram"
    }
    var cancelTitle: String {
        return "取消分享"
    }
    func fallback(inbox: WyGramShareInbox?, providers: [NSItemProvider], finish: @escaping () -> Void) -> WyGramShareFallbackController {
        return WyGramShareFallbackController(inbox: inbox, providers: providers, finish: finish)
    }
    func importInbox(_ inboxes: [WyGramShareInbox]) -> WyGramShareInbox? {
        return WyGramShareInbox.preparedForImport(inboxes: inboxes)
    }
    func run() async {
        let base = docs.appendingPathComponent("tests")
        try? FileManager.default.removeItem(at: base)
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let f1 = base.appendingPathComponent("证书测试.p12"), f2 = base.appendingPathComponent("描述测试.mobileprovision")
        try! Data("NON-SECRET P12 TEST".utf8).write(to: f1)
        try! Data("NON-SECRET PROFILE TEST".utf8).write(to: f2)
        let inbox = WyGramShareInbox(directory: base.appendingPathComponent("inbox"))
        let group = base.appendingPathComponent("canonical-group")
        check("no-group-cannot-use-account", !WyGramShareInbox.canUseSharedAccount(group: nil, inboxes: [inbox]))
        check("empty-group-does-not-create-account", !WyGramShareInbox.canUseSharedAccount(group: group, inboxes: [inbox]))
        try! FileManager.default.createDirectory(at: group.appendingPathComponent("telegram-data/accounts-metadata"), withIntermediateDirectories: true)
        check("missing-account-key-does-not-generate-replacement", !WyGramShareInbox.canUseSharedAccount(group: group, inboxes: [inbox]) && !FileManager.default.fileExists(atPath: group.appendingPathComponent("telegram-data/.tempkey").path))
        try! Data(repeating: 0x41, count: 48).write(to: group.appendingPathComponent("telegram-data/.tempkey"))
        check("unpublished-account-store-not-used-by-extension", !WyGramShareInbox.canUseSharedAccount(group: group, inboxes: [inbox]))
        inbox.publishStorage(shared: false)
        check("private-account-forces-file-handoff", !WyGramShareInbox.canUseSharedAccount(group: group, inboxes: [inbox]))
        inbox.publishStorage(shared: true)
        check("shared-mode-restores-native-eligibility", WyGramShareInbox.canUseSharedAccount(group: group, inboxes: [inbox]))

        let id = UUID().uuidString
        try! inbox.begin(id: id)
        let a = try! inbox.copy(source: f1, name: f1.lastPathComponent, id: id, index: 0, remainingBytes: WyGramShareInbox.maximumBytes)
        check("partial-copy-not-published", inbox.pending().isEmpty)
        let b = try! inbox.copy(source: f2, name: f2.lastPathComponent, id: id, index: 1, remainingBytes: WyGramShareInbox.maximumBytes-a.size)
        let batch = try! inbox.finish(id: id, items: [a,b])
        check("two-files-atomic-publication", inbox.pending().count == 1 && inbox.pending()[0].items.count == 2)
        check("names-and-bytes-preserved", batch.items.map(\.name) == [f1.lastPathComponent, f2.lastPathComponent] && (try? Data(contentsOf: inbox.fileURL(batch: batch, item: a))) == (try? Data(contentsOf: f1)))
        check("relaunch-discovers-pending-batch", WyGramShareInbox(directory: inbox.directory).pending().first?.id == id)
        check("reject-path-traversal-id", !WyGramShareInbox.validId("../outside"))
        inbox.remove(id: "../outside")
        check("invalid-cleanup-leaves-originals", FileManager.default.fileExists(atPath: f1.path))
        check("expired-batches-removed", inbox.pending(now: Date().addingTimeInterval(3601)).isEmpty && !FileManager.default.fileExists(atPath: inbox.directory.appendingPathComponent(id).path))
        let limitId = UUID().uuidString
        try! inbox.begin(id: limitId)
        do { _ = try inbox.copy(source: f1, name: "test", id: limitId, index: 0, remainingBytes: 1); check("file-size-limit", false) } catch { check("file-size-limit", true) }
        let symlink = base.appendingPathComponent("link")
        try! FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: f1)
        do { _ = try inbox.copy(source: symlink, name: "link", id: limitId, index: 0, remainingBytes: 1024); check("source-symlink-rejected", false) } catch { check("source-symlink-rejected", true) }
        inbox.remove(id: limitId)
        let corruptId = UUID().uuidString
        try! inbox.begin(id: corruptId)
        let c = try! inbox.copy(source: f1, name: "test.p12", id: corruptId, index: 0, remainingBytes: 1024)
        let corrupt = try! inbox.finish(id: corruptId, items: [c])
        try! Data("tamper".utf8).write(to: inbox.fileURL(batch: corrupt, item: c))
        check("modified-size-rejected", inbox.pending().isEmpty)
        inbox.remove(id: corruptId)

        let unprepared = WyGramShareInbox(directory: base.appendingPathComponent("unprepared"))
        let mainInbox = WyGramShareInbox(directory: base.appendingPathComponent("main-inbox"))
        check("no-false-success-for-extension-only-directory", importInbox([unprepared]) == nil)
        mainInbox.publishStorage(shared: false)
        check("prefer-inbox-actually-prepared-by-main-app", importInbox([unprepared, mainInbox])?.directory == mainInbox.directory)
        let malformed = WyGramShareInbox(directory: base.appendingPathComponent("malformed"))
        try! malformed.prepare()
        try! Data("invalid".utf8).write(to: malformed.directory.appendingPathComponent("storage-mode"))
        check("malformed-main-marker-rejected", importInbox([malformed]) == nil)

        var completed = 0
        var controller: WyGramShareFallbackController? = fallback(inbox: mainInbox, providers: [provider(f1), provider(f2)], finish: { completed += 1 })
        attach(controller!)
        await wait { !mainInbox.pending().isEmpty }
        await wait { button(controller!, continueTitle)?.isHidden == false }
        check("real-itemprovider-multi-file-load", mainInbox.pending().first?.items.count == 2)
        check("ready-ui-visible-no-blank", text(controller!).contains("文件已准备好"))
        screenshot("handoff-ready")
        check("files-never-auto-send", completed == 0)
        button(controller!, continueTitle)?.sendActions(for: .touchUpInside)
        await pause()
        await wait { completed == 1 }
        check("manual-close-completes-once", completed == 1)
        check("manual-close-preserves-selected-attachments", mainInbox.pending().first?.items.count == 2)
        button(controller!, cancelTitle)?.sendActions(for: .touchUpInside)
        await pause()
        check("late-cancel-after-completion-cannot-remove-batch", completed == 1 && mainInbox.pending().count == 1)
        detach(controller!)
        weak var released = controller
        controller = nil
        await pause()
        check("controller-release-does-not-delete-published-batch", released == nil && mainInbox.pending().count == 1)
        let receiver = WyGramShareInbox(directory: mainInbox.directory)
        check("main-relaunch-finds-original-bytes-and-names", receiver.pending().first.map { batch in
            batch.items.map(\.name) == [f1.lastPathComponent, f2.lastPathComponent] &&
            (try? Data(contentsOf: receiver.fileURL(batch: batch, item: batch.items[0]))) == (try? Data(contentsOf: f1)) &&
            (try? Data(contentsOf: receiver.fileURL(batch: batch, item: batch.items[1]))) == (try? Data(contentsOf: f2))
        } == true)
        for batch in receiver.pending() { receiver.remove(id: batch.id) }

        var cancelFinished = 0
        let cancelled = fallback(inbox: inbox, providers: [provider(f1)], finish: { cancelFinished += 1 })
        attach(cancelled)
        await wait { !inbox.pending().isEmpty }
        button(cancelled, cancelTitle)?.sendActions(for: .touchUpInside)
        await wait { cancelFinished == 1 }
        check("explicit-cancel-removes-only-pending-copies", inbox.pending().isEmpty && FileManager.default.fileExists(atPath: f1.path))
        button(cancelled, cancelTitle)?.sendActions(for: .touchUpInside)
        await pause()
        check("double-cancel-completes-once", cancelFinished == 1)
        detach(cancelled)

        let noGroup = fallback(inbox: nil, providers: [provider(f1)], finish: { completed += 1 })
        attach(noGroup)
        check("missing-entitlement-shows-actionable-ui", text(noGroup).contains("App Group") && text(noGroup).contains("附件 → 文件") && button(noGroup, continueTitle)?.isHidden == true)
        screenshot("missing-group")
        button(noGroup, cancelTitle)?.sendActions(for: .touchUpInside)
        await wait { completed == 2 }
        check("no-group-can-close", completed == 2)
        detach(noGroup)

        let errorProvider = NSItemProvider()
        errorProvider.registerItem(forTypeIdentifier: UTType.fileURL.identifier, loadHandler: { completion, _, _ in completion?(nil, CocoaError(.fileReadNoPermission)) })
        let bad = fallback(inbox: inbox, providers: [provider(f1), errorProvider], finish: {})
        attach(bad)
        await wait { text(bad).contains("无法读取") }
        check("provider-error-no-partial-handoff", text(bad).contains("无法读取") && inbox.pending().isEmpty)
        var errorClosed = false
        let failed = fallback(inbox: inbox, providers: [errorProvider], finish: { errorClosed = true })
        attach(failed)
        await wait { text(failed).contains("无法读取") }
        button(failed, cancelTitle)?.sendActions(for: .touchUpInside)
        await wait { errorClosed }
        check("failed-import-still-can-close", errorClosed && inbox.pending().isEmpty)
        detach(failed)
        detach(bad)

        // Exercise real loadFileRepresentation instead of the file-url branch.
        let represented = NSItemProvider()
        represented.suggestedName = "representation.p12"
        represented.registerFileRepresentation(forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all) { completion in completion(f1, false, nil); return nil }
        let representedController = fallback(inbox: inbox, providers: [represented], finish: {})
        attach(representedController)
        await wait { !inbox.pending().isEmpty }
        check("file-representation-copied-before-callback-ends", inbox.pending().first?.items.first?.name == "representation.p12")
        for batch in inbox.pending() { inbox.remove(id: batch.id) }
        detach(representedController)

        let delayed = NSItemProvider()
        delayed.registerItem(forTypeIdentifier: UTType.fileURL.identifier, loadHandler: { completion, _, _ in
            DispatchQueue.global().asyncAfter(deadline: .now()+0.5) { completion?(f1 as NSURL, nil) }
        })
        var delayedFinish = 0
        let cancelledLoading = fallback(inbox: inbox, providers: [delayed], finish: { delayedFinish += 1 })
        attach(cancelledLoading)
        button(cancelledLoading, cancelTitle)?.sendActions(for: .touchUpInside)
        await pause(0.8)
        check("late-provider-callback-after-cancel-ignored", delayedFinish == 1 && inbox.pending().isEmpty)
        detach(cancelledLoading)

        let report: [String:Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks, "runID": ProcessInfo.processInfo.environment["WYGRAM_SHARE_PROBE_RUN_ID"] ?? "none"]
        try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: docs.appendingPathComponent("results.json"))
        let summary = UILabel(frame: CGRect(x: 24, y: 100, width: root.view.bounds.width-48, height: root.view.bounds.height-130))
        summary.numberOfLines = 0
        summary.font = .systemFont(ofSize: 13)
        summary.text = "WyGram 分享组件检查\n" + checks.map { "\($0["passed"] as? Bool == true ? "✓" : "✗") \($0["name"]!)" }.joined(separator: "\n")
        root.view.addSubview(summary)
    }
}
