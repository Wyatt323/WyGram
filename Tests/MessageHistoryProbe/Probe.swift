import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import TelegramPresentationData
import SGSettingsUI
import NavigationBarImpl
import LegacyUI

private enum TestFailure: Error { case failed(String) }
private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw TestFailure.failed(message) }
}
private let peer = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(2001))
private let otherPeer = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(3001))
private func message(_ number: Int32, text: String, edited: Int32? = nil, incoming: Bool = true, peerId: PeerId = peer, attributes: [MessageAttribute] = [], media: [Media] = []) -> StoreMessage {
    var attributes = attributes
    if let edited { attributes.append(EditedMessageAttribute(date: edited, isHidden: false)) }
    return StoreMessage(id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: number), customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: 1792857600, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: peer, text: text, attributes: attributes, media: media)
}

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { initializeAccountManagement(); return true }
}
@objc(MessageHistoryProbeSceneDelegate)
final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var disposables: [Disposable] = []
    var postboxes: [Postbox] = []
    var checks: [String] = []
    var displayWindow: Window1?
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController(); window.rootViewController?.view.backgroundColor = .systemBackground
        self.window = window; window.makeKeyAndVisible()
        TempBox.initializeShared(basePath: self.documents.appendingPathComponent("temp").path, processType: "tests", launchSpecificId: 1)
        Task { @MainActor in
            do {
                let a = await self.open("account-a"), b = await self.open("account-b")
                if CommandLine.arguments.contains("--restart") {
                    let saved = await self.value(wygramMessageHistory(postbox: a))
                    try check(saved.count == 3, "Three saved versions must survive process restart")
                    try check(saved.contains { $0.text == "第一版：周五见面" }, "Original text survives restart")
                    try check(saved.contains { $0.reason == "deleted" && $0.text == "第三版：周日见面" }, "Deleted final version survives restart")
                    self.checks.append("Saved original, intermediate and deleted final versions survive process restart")
                    let retained = await self.value(a.transaction { $0.getMessage(MessageId(peerId: peer, namespace: 0, id: 101)) })
                    try check(retained?.wygramHistoryAttribute?.deletedAt != nil && retained?.wygramHistoryAttribute?.hasPreviousVersions == true, "Inline deletion and history attributes survive process restart")
                    self.checks.append("Inline retained message and deletion/history attributes survive process restart")
                    let empty = await self.value(wygramMessageHistory(postbox: b))
                    try check(empty.isEmpty, "Account B must not see account A history")
                    self.checks.append("Account isolation survives process restart")
                    let files = saved.flatMap { $0.attachments.compactMap(\.localFileName) }
                    try check(!files.isEmpty, "Downloaded media must be retained")
                    let directory = wygramMessageHistoryDirectory(mediaBox: a.mediaBox)
                    try check(files.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }, "Saved media survives source deletion")
                    self.checks.append("Downloaded image remains available after original cache removal and restart")
                    _ = await self.value(wygramRemoveMessageHistory(postbox: a, keys: [saved[0].key]))
                    let afterOne = await self.value(wygramMessageHistory(postbox: a))
                    try check(afterOne.count == 2, "Deleting one record must retain the others")
                    _ = await self.value(wygramRemoveMessageHistory(postbox: a))
                    let cleared = await self.value(wygramMessageHistory(postbox: a))
                    try check(cleared.isEmpty, "Clear must remove records")
                    try check(files.allSatisfy { !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }, "Clear must remove archived attachment files")
                    self.checks.append("Individual deletion and clear remove only archived records and associated files")
                }
                try await self.exercise(a, b)
                self.showHistory(a)
                if !CommandLine.arguments.contains("--detail") { self.writeReport(passed: true, error: nil) }
            } catch { self.writeReport(passed: false, error: String(describing: error)) }
        }
    }
    func value<T>(_ signal: Signal<T, NoError>) async -> T {
        return await withCheckedContinuation { continuation in
            self.disposables.append((signal |> take(1)).start(next: { continuation.resume(returning: $0) }))
        }
    }
    func completion<T>(_ signal: Signal<T, NoError>) async {
        await withCheckedContinuation { continuation in
            self.disposables.append(signal.start(completed: { continuation.resume() }))
        }
    }
    func open(_ name: String) async -> Postbox {
        let encryption = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: false, key: .init(data: Data(repeating: 7, count: 32))!, salt: .init(data: Data(repeating: 9, count: 16))!)
        let signal = openPostbox(basePath: self.documents.appendingPathComponent(name).appendingPathComponent("postbox").path, seedConfiguration: telegramPostboxSeedConfiguration, encryptionParameters: encryption, timestampForAbsoluteTimeBasedOperations: Int32(Date().timeIntervalSince1970), isMainProcess: true, isTemporary: false, isReadOnly: false, useCopy: false, useCaches: true, removeDatabaseOnError: false) |> mapToSignal { result -> Signal<Postbox, NoError> in
            if case let .postbox(postbox) = result { return .single(postbox) }; return .complete()
        }
        let postbox = await self.value(signal); self.postboxes.append(postbox); return postbox
    }
    func exercise(_ a: Postbox, _ b: Postbox) async throws {
        _ = await self.value(wygramRemoveMessageHistory(postbox: a))
        _ = await self.value(wygramUpdateMessageHistorySettings(postbox: a, settings: WyGramMessageHistorySettings()))
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { ctx in UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0,y: 0,width: 40,height: 40)) }.jpegData(compressionQuality: 0.9)!
        let resource = LocalFileMediaResource(fileId: 8444, size: Int64(jpeg.count))
        a.mediaBox.storeResourceData(resource.id, data: jpeg, synchronous: true)
        let image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 8444), representations: [TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 40, height: 40), resource: resource, progressiveSizes: [], immediateThumbnailData: nil)], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        _ = await self.value(a.transaction { transaction -> Void in
            let user = TelegramUser(id: peer, accessHash: nil, firstName: "测试联系人", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
            transaction.updatePeersInternal([user], update: { _, updated in updated })
            _ = transaction.addMessages([message(101, text: "第一版：周五见面", attributes: [TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: 0..<3, type: .Bold)])], media: [image])], location: .Random)
            let second = message(101, text: "第二版：周六见面", edited: 1792857700, media: [image])
            wygramArchivePreviousVersion(transaction: transaction, mediaBox: a.mediaBox, replacement: second)
            // Repeated updates must not duplicate one saved version.
            wygramArchivePreviousVersion(transaction: transaction, mediaBox: a.mediaBox, replacement: second)
            let savedSecond = wygramApplyLocalMessageHistory(transaction: transaction, replacement: second)
            transaction.updateMessage(MessageId(peerId: peer, namespace: 0, id: 101), update: { _ in .update(savedSecond) })
            let third = message(101, text: "第三版：周日见面", edited: 1792857800, media: [image])
            wygramArchivePreviousVersion(transaction: transaction, mediaBox: a.mediaBox, replacement: third)
            let savedThird = wygramApplyLocalMessageHistory(transaction: transaction, replacement: third)
            transaction.updateMessage(MessageId(peerId: peer, namespace: 0, id: 101), update: { _ in .update(savedThird) })
            wygramArchivePreviousVersion(transaction: transaction, mediaBox: a.mediaBox, replacement: third)
            let ids = transaction.messageIdsForGlobalIds([101])
            let removed = wygramPrepareRemoteMessageDeletion(transaction: transaction, mediaBox: a.mediaBox, ids: ids)
            transaction.deleteMessages(removed, forEachMedia: nil)
        })
        let retained = await self.value(a.transaction { $0.getMessage(MessageId(peerId: peer, namespace: 0, id: 101)) })
        try check(retained?.text == "第三版：周日见面" && retained?.wygramHistoryAttribute?.deletedAt != nil && retained?.wygramHistoryAttribute?.hasPreviousVersions == true, "Deleted message remains in chat with a persisted deletion marker and history")
        self.checks.append("Deleted message stays in normal chat with its original content, deletion marker and edit-history marker")
        let records = await self.value(wygramMessageHistory(postbox: a))
        try check(records.count == 3, "Repeated updates must produce exactly three distinct versions")
        try check(Set(records.map(\.text)).count == 3, "Each intermediate version must be saved")
        try check(records.filter { $0.reason == "deleted" }.count == 1, "Deleted version must be clearly labeled")
        let original = records.first { $0.text == "第一版：周五见面" }
        try check(original?.entities == [MessageTextEntity(range: 0..<3, type: .Bold)], "Original text formatting survives archive encoding")
        try check((original?.media.first as? TelegramMediaImage)?.imageId == image.imageId, "Archived media metadata decodes correctly")
        self.checks.append("Text formatting and image metadata survive archive encoding and decoding")
        self.checks.append("Two consecutive edits, duplicate update, metadata-only replay and global deletion retain exactly three versions")
        let localDeleteSucceeded = await self.value(a.transaction { transaction -> Bool in
            // Manual deletion is local and must not erase the independent archive.
            _internal_deleteMessages(transaction: transaction, mediaBox: a.mediaBox, ids: [MessageId(peerId: peer, namespace: 0, id: 101)])
            let deletedLocally = transaction.getMessage(MessageId(peerId: peer, namespace: 0, id: 101)) == nil
            let retained = message(101, text: "第三版：周日见面", edited: 1792857800, attributes: [WyGramMessageHistoryAttribute(deletedAt: 1792857900, hasPreviousVersions: true)], media: [image])
            _ = transaction.addMessages([retained], location: .Random)
            let outgoing = message(102, text: "自己发送", incoming: false)
            let ttl = message(103, text: "自动销毁", attributes: [AutoremoveTimeoutMessageAttribute(timeout: 10, countdownBeginTime: nil)])
            _ = transaction.addMessages([outgoing, ttl], location: .Random)
            let excluded = wygramPrepareRemoteMessageDeletion(transaction: transaction, mediaBox: a.mediaBox, ids: [102, 103].map { MessageId(peerId: peer, namespace: 0, id: $0) })
            transaction.deleteMessages(excluded, forEachMedia: nil)
            // Channel IDs must not collide with user-dialog IDs.
            _ = transaction.addMessages([message(101, text: "频道消息", peerId: otherPeer)], location: .Random)
            let removed = wygramPrepareRemoteMessageRangeDeletion(transaction: transaction, mediaBox: a.mediaBox, peerId: otherPeer, namespace: Namespaces.Message.Cloud, maxId: 101)
            transaction.deleteMessages(removed, forEachMedia: nil)
            return deletedLocally
        })
        try check(localDeleteSucceeded, "Retained messages can still be manually deleted locally")
        self.checks.append("Manual local deletion removes the retained chat bubble without erasing saved versions")
        let channel = await self.value(wygramMessageHistory(postbox: a, peerId: otherPeer))
        try check(channel.count == 1 && channel[0].text == "频道消息", "Channel-scoped message ID isolation")
        let all = await self.value(wygramMessageHistory(postbox: a))
        try check(all.count == 4, "Outgoing and disappearing messages are excluded")
        _ = await self.value(wygramRemoveMessageHistory(postbox: a, keys: channel.map(\.key)))
        self.checks.append("Channel deletion handled separately; outgoing and disappearing messages excluded")
        _ = await self.value(wygramUpdateMessageHistorySettings(postbox: a, settings: WyGramMessageHistorySettings(keepDeletedMessages: false, keepEditHistory: false)))
        _ = await self.value(a.transaction { transaction -> Void in
            _ = transaction.addMessages([message(104, text: "停用后不保存")], location: .Random)
            wygramArchivePreviousVersion(transaction: transaction, mediaBox: a.mediaBox, replacement: message(104, text: "改变", edited: 1792857900))
            let removed = wygramPrepareRemoteMessageDeletion(transaction: transaction, mediaBox: a.mediaBox, ids: [MessageId(peerId: peer, namespace: 0, id: 104)])
            transaction.deleteMessages(removed, forEachMedia: nil)
        })
        let disabled = await self.value(wygramMessageHistory(postbox: a))
        try check(disabled.count == 3, "Disabled toggles must stop saving without deleting prior history")
        let bSettings = await self.value(wygramMessageHistorySettings(postbox: b))
        try check(bSettings.keepDeletedMessages && bSettings.keepEditHistory, "Settings are isolated per account")
        let other = await self.value(wygramMessageHistory(postbox: b))
        try check(other.isEmpty, "Account B archive is empty")
        _ = await self.value(wygramUpdateMessageHistorySettings(postbox: a, settings: WyGramMessageHistorySettings()))
        await self.completion(a.mediaBox.removeCachedResources([resource.id], force: true))
        self.checks.append("Both off switches stop capture; retained records and per-account settings remain correct")
    }
    func showHistory(_ postbox: Postbox) {
        defaultNavigationBarImpl = { NavigationBarImpl(presentationData: $0) }
        let strings = PresentationStrings(primaryComponent: PresentationStrings.Component(languageCode: "zh-hans", localizedName: "简体中文", pluralizationRulesCode: nil, dict: [:]), secondaryComponent: nil, groupingSeparator: "")
        let controller = wygramLocalMessageHistoryController(postbox: postbox, theme: defaultPresentationTheme, strings: strings)
        let theme = NavigationControllerTheme(statusBar: .black, navigationBar: NavigationBarTheme(overallDarkAppearance: false, buttonColor: .systemBlue, disabledButtonColor: .gray, primaryTextColor: .black, backgroundColor: .systemGroupedBackground, enableBackgroundBlur: true, separatorColor: .clear, badgeBackgroundColor: .systemBlue, badgeStrokeColor: .white, badgeTextColor: .white, accentButtonColor: .systemBlue, accentDisabledButtonColor: .gray, accentForegroundColor: .white), emptyAreaColor: .systemGroupedBackground)
        let navigation = NavigationController(mode: .single, theme: theme)
        navigation.setViewControllers([controller], animated: false)
        let scene = self.window!.windowScene!
        let (window, host) = nativeWindowHostView()
        window.windowScene = scene; window.frame = scene.coordinateSpace.bounds
        let display = Window1(hostView: host, statusBarHost: ProbeStatusHost(window: window))
        display.viewController = navigation; self.displayWindow = display
        self.window?.isHidden = true; self.window = window; window.makeKeyAndVisible()
        if CommandLine.arguments.contains("--detail") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                guard let legacy = controller as? LegacyController, let table = legacy.legacyController as? UITableViewController, table.tableView.numberOfRows(inSection: 1) == 3 else {
                    self.writeReport(passed: false, error: "History list did not load three versions"); return
                }
                table.tableView.delegate?.tableView?(table.tableView, didSelectRowAt: IndexPath(row: 0, section: 1))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard let detail = navigation.viewControllers.last as? LegacyController, detail !== legacy else {
                        self.writeReport(passed: false, error: "Saved-version navigation did not open"); return
                    }
                    detail.legacyController.loadViewIfNeeded()
                    guard let textView = detail.legacyController.view.subviews.first(where: { $0 is UITextView }) as? UITextView, textView.text.contains("第三版：周日见面") else {
                        self.writeReport(passed: false, error: "Saved-version detail did not render saved text"); return
                    }
                    self.checks.append("Production history list opens saved-version detail with selectable archived text")
                    self.writeReport(passed: true, error: nil)
                }
            }
        }
    }
    func writeReport(passed: Bool, error: String?) {
        let data: [String: Any] = ["passed": passed, "checks": self.checks, "phase": CommandLine.arguments.contains("--detail") ? "detail" : CommandLine.arguments.contains("--restart") ? "restart" : "initial", "error": error ?? "none"]
        try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: self.documents.appendingPathComponent("results.json"))
    }
}

private final class ProbeStatusHost: StatusBarHost {
    weak var window: UIWindow?
    init(window: UIWindow) { self.window = window }
    var isApplicationInForeground: Bool { true }
    var statusBarFrame: CGRect { window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero }
    var keyboardWindow: UIWindow? { nil }
    var keyboardView: UIView? { nil }
}
