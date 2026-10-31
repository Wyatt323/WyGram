import UIKit
import QuickLook
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
    return StoreMessage(id: MessageId(peerId: peerId, namespace: peerId.namespace == Namespaces.Peer.SecretChat ? Namespaces.Message.SecretIncoming : Namespaces.Message.Cloud, id: number), customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: 1792857600, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: peer, text: text, attributes: attributes, media: media)
}

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { initializeAccountManagement(); return true }
}
@objc(RetainedPhotoProbeSceneDelegate)
final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var disposables: [Disposable] = []
    var postboxes: [Postbox] = []
    var checks: [String] = [] {
        didSet { try? self.checks.joined(separator: "\n").write(to: self.documents.appendingPathComponent("progress.txt"), atomically: true, encoding: .utf8) }
    }
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
                    let records = await self.value(wygramMessageHistory(postbox: a))
                    try check(records.count == 3 && records.allSatisfy { $0.reason == "disappearing" }, "Three retained photos survive process restart")
                    for entry in records {
                        let retained = await self.value(a.transaction { $0.getMessage(entry.id) })
                        try check(retained?.wygramRetainedPhotoAttribute?.archiveKey == entry.key, "Retained attribute and chat photo survive restart")
                        let resource = (retained!.media[0] as! TelegramMediaImage).representations[0].resource as! LocalFileMediaResource
                        let restored = try Data(contentsOf: URL(fileURLWithPath: wygramRetainedPhotoPath(mediaBox: a.mediaBox, resource: resource)))
                        try check(UIImage(data: restored) != nil, "Saved photo decodes after restart and cache removal")
                    }
                    self.checks.append("All three retained photos, message markers and readable files survive process restart")
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
        let migrated = try JSONDecoder().decode(WyGramMessageHistorySettings.self, from: Data("{\"keepDeletedMessages\":false,\"keepEditHistory\":false}".utf8))
        try check(!migrated.keepDeletedMessages && !migrated.keepEditHistory && migrated.keepDisappearingPhotos, "Upgrade preserves old off switches and enables new photo setting")
        self.checks.append("Existing settings migrate without resetting disabled anti-delete/edit preferences")
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240)).image { ctx in
            UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
            ("WyGram 已保留" as NSString).draw(at: CGPoint(x: 25, y: 100), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white])
        }.jpegData(compressionQuality: 0.95)!
        let resource = LocalFileMediaResource(fileId: 755111, size: Int64(jpeg.count))
        let thumbnail = LocalFileMediaResource(fileId: 755112, size: Int64(jpeg.count))
        let missing = LocalFileMediaResource(fileId: 755113, size: Int64(jpeg.count))
        a.mediaBox.storeResourceData(resource.id, data: jpeg, synchronous: true)
        a.mediaBox.storeResourceData(thumbnail.id, data: jpeg, synchronous: true)
        func photo(_ number: Int64, full: MediaResource) -> TelegramMediaImage {
            return TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: number), representations: [
                TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 40, height: 30), resource: thumbnail, progressiveSizes: [], immediateThumbnailData: nil),
                TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 320, height: 240), resource: full as! TelegramMediaResource, progressiveSizes: [], immediateThumbnailData: nil)
            ], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        }
        let image = photo(755111, full: resource)
        let once = AutoclearTimeoutMessageAttribute(timeout: viewOnceTimeout, countdownBeginTime: nil)
        let timed = AutoclearTimeoutMessageAttribute(timeout: 3, countdownBeginTime: nil)
        let secretPeer = PeerId(namespace: Namespaces.Peer.SecretChat, id: PeerId.Id._internalFromInt64Value(8001))
        let ids = [201, 202, 203].map { MessageId(peerId: $0 == 203 ? secretPeer : peer, namespace: $0 == 203 ? Namespaces.Message.SecretIncoming : Namespaces.Message.Cloud, id: Int32($0)) }
        _ = await self.value(a.transaction { transaction -> Void in
            let user = TelegramUser(id: peer, accessHash: nil, firstName: "测试联系人", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
            transaction.updatePeersInternal([user], update: { _, updated in updated })
            _ = transaction.addMessages([
                message(201, text: "仅查看一次照片", attributes: [once, ConsumableContentMessageAttribute(consumed: false)], media: [image]),
                message(202, text: "三秒倒计时照片", attributes: [timed], media: [photo(755114, full: resource)]),
                message(203, text: "秘密聊天倒计时照片", peerId: secretPeer, attributes: [AutoremoveTimeoutMessageAttribute(timeout: 10, countdownBeginTime: nil)], media: [photo(755115, full: resource)])
            ], location: .Random)
        })
        // The real interactive consumer must save before its zero-delay timer can fire.
        _ = await self.value(_internal_markMessageContentAsConsumedInteractively(postbox: a, messageId: ids[0]))
        _ = await self.value(a.transaction { transaction -> Void in
            // The real remote consumer would otherwise replace this immediately with expired content.
            markMessageContentAsConsumedRemotely(transaction: transaction, mediaBox: a.mediaBox, messageId: ids[1], consumeDate: 1)
            _internal_expireMessage(transaction: transaction, mediaBox: a.mediaBox, messageId: ids[2], isRemove: true)
            for id in ids {
                _internal_expireMessage(transaction: transaction, mediaBox: a.mediaBox, messageId: id, isRemove: false)
                _internal_expireMessage(transaction: transaction, mediaBox: a.mediaBox, messageId: id, isRemove: true)
            }
        })
        for id in ids {
            let stored = await self.value(a.transaction { $0.getMessage(id) })
            try check(stored?.wygramRetainedPhotoAttribute != nil && stored?.minAutoremoveOrClearTimeout == nil, "Photo survives expiry and countdown is removed only after save")
            try check(stored?.media.first is TelegramMediaImage, "Photo is not an expired placeholder")
            try check((stored?.media.first as? TelegramMediaImage)?.imageId.namespace == Namespaces.Media.LocalImage, "Retained photo has a separate local identity immune to cloud media replacement")
        }
        let consumed = await self.value(a.transaction { $0.getMessage(ids[0]) })
        try check((consumed?.attributes.first { $0 is ConsumableContentMessageAttribute } as? ConsumableContentMessageAttribute)?.consumed == true, "Consumption bookkeeping remains intact")
        self.checks.append("Interactive view-once consumption, remote already-expired receipt and secret-chat expiry retain complete photos")
        self.checks.append("Both real expiry branches preserve retained images and remove their timer entries")
        let firstRecords = await self.value(wygramMessageHistory(postbox: a))
        try check(firstRecords.count == 3, "Repeated expiry does not duplicate records")
        _ = await self.value(a.transaction { transaction -> Void in
            let expired = message(201, text: "", media: [TelegramMediaExpiredContent(data: .image)])
            let prepared = wygramPrepareRemoteMessages(transaction: transaction, mediaBox: a.mediaBox, messages: [expired])
            _ = transaction.addMessages(prepared, location: .Random)
            let deleting = wygramPrepareRemoteMessageDeletion(transaction: transaction, mediaBox: a.mediaBox, ids: ids)
            transaction.deleteMessages(deleting, forEachMedia: nil)
        })
        let afterRemote = await self.value(a.transaction { transaction in ids.compactMap { transaction.getMessage($0) } })
        try check(afterRemote.count == 3 && afterRemote.allSatisfy { $0.wygramRetainedPhotoAttribute != nil }, "Server expired refresh and deletion must retain saved photos")
        let afterRemoteRecords = await self.value(wygramMessageHistory(postbox: a))
        try check(afterRemoteRecords.count == 3, "Remote replay must not generate false edit versions")
        self.checks.append("Remote expired replacements, deletions and duplicate replays preserve chat photos without extra edit records")
        let exclusions = await self.value(a.transaction { transaction -> [Bool] in
            let fixtures = [
                message(210, text: "缩略图不能代替原图", attributes: [once], media: [photo(755116, full: missing)]),
                message(211, text: "普通照片", media: [image]),
                message(212, text: "自己发送的照片", incoming: false, attributes: [once], media: [image]),
                message(213, text: "自动删除文字", attributes: [timed]),
                message(214, text: "已过期照片", media: [TelegramMediaExpiredContent(data: .image)])
            ]
            _ = transaction.addMessages(fixtures, location: .Random)
            return (210...214).map { wygramRetainDisappearingPhoto(transaction: transaction, mediaBox: a.mediaBox, messageId: MessageId(peerId: peer, namespace: 0, id: Int32($0))) }
        })
        try check(exclusions.allSatisfy { !$0 }, "Incomplete, normal, outgoing, text and expired messages must not be mislabeled saved")
        self.checks.append("Thumbnail-only and expired photos cannot report success; normal/outgoing photos and timed text are excluded")
        // Exercise failure after a complete download: a file occupying the directory prevents the durable copy.
        let blockedDirectory = wygramMessageHistoryDirectory(mediaBox: b.mediaBox)
        try FileManager.default.createDirectory(at: blockedDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: blockedDirectory)
        b.mediaBox.storeResourceData(resource.id, data: jpeg, synchronous: true)
        let blocked = await self.value(b.transaction { transaction -> Bool in
            _ = transaction.addMessages([message(220, text: "存储失败", attributes: [once], media: [image])], location: .Random)
            return wygramRetainDisappearingPhoto(transaction: transaction, mediaBox: b.mediaBox, messageId: MessageId(peerId: peer, namespace: 0, id: 220))
        })
        try check(!blocked, "Failed durable storage must not remove timers or claim preservation")
        try FileManager.default.removeItem(at: blockedDirectory)
        let other = await self.value(wygramMessageHistory(postbox: b))
        try check(other.isEmpty, "Separate account does not inherit saved photos")
        self.checks.append("Durable-copy failure and account isolation leave no false saved record")
        _ = await self.value(wygramUpdateMessageHistorySettings(postbox: a, settings: WyGramMessageHistorySettings(keepDisappearingPhotos: false)))
        let disabled = await self.value(a.transaction { transaction -> Bool in
            let id = MessageId(peerId: peer, namespace: 0, id: 221)
            _ = transaction.addMessages([message(221, text: "停用后照片", attributes: [once], media: [image])], location: .Random)
            let saved = wygramRetainDisappearingPhoto(transaction: transaction, mediaBox: a.mediaBox, messageId: id)
            _internal_expireMessage(transaction: transaction, mediaBox: a.mediaBox, messageId: id, isRemove: false)
            return !saved && transaction.getMessage(id)?.media.first is TelegramMediaExpiredContent
        })
        try check(disabled, "Disabled setting keeps normal expiry behavior")
        _ = await self.value(a.transaction { transaction -> Void in
            _internal_expireMessage(transaction: transaction, mediaBox: a.mediaBox, messageId: ids[0], isRemove: true)
        })
        let existing = await self.value(a.transaction { $0.getMessage(ids[0]) })
        try check(existing?.wygramRetainedPhotoAttribute != nil, "Switch off does not erase already saved photo")
        _ = await self.value(wygramUpdateMessageHistorySettings(postbox: a, settings: WyGramMessageHistorySettings()))
        self.checks.append("Off switch stops new retention while previously saved photos remain readable")
        // Remove original and local cache bytes; fetch must use the independent account-relative copy.
        let localResources = afterRemote.map { ($0.media[0] as! TelegramMediaImage).representations[0].resource as! LocalFileMediaResource }
        await self.completion(a.mediaBox.removeCachedResources([resource.id, thumbnail.id] + localResources.map(\.id), force: true))
        a.mediaBox.fetchResource = { resource, _, _ in
            wygramFetchRetainedPhoto(mediaBox: a.mediaBox, resource: resource) ?? .fail(.generic)
        }
        for local in localResources {
            let path = wygramRetainedPhotoPath(mediaBox: a.mediaBox, resource: local)
            let savedBytes = try Data(contentsOf: URL(fileURLWithPath: path))
            try check(savedBytes == jpeg, "Durable saved photo matches complete original bytes")
            self.checks.append("Cache refetch started for \(local.id.stringRepresentation)")
            await self.completion(a.mediaBox.fetchedResource(local, parameters: nil) |> `catch` { _ in .complete() })
            self.checks.append("Cache refetch completion received for \(local.id.stringRepresentation)")
            let data = await self.value(a.mediaBox.resourceData(local) |> filter { $0.complete } |> take(1))
            self.checks.append("Complete resource-data event received")
            let cacheBytes = try Data(contentsOf: URL(fileURLWithPath: data.path))
            try check(cacheBytes == jpeg, "Production media fetch reloads the exact image after cache clearing")
        }
        self.checks.append("Complete originals survive cache eviction and reload through the production local-resource fetch path")
        // Delete a retained record and ensure its corresponding local bubble cannot keep a broken resource.
        let selected = firstRecords.first { $0.id == ids[1] }!
        _ = await self.value(wygramRemoveMessageHistory(postbox: a, keys: [selected.key]))
        let removed = await self.value(a.transaction { $0.getMessage(ids[1]) })
        try check(removed == nil, "Removing a photo record removes the local retained bubble")
        try check(!FileManager.default.fileExists(atPath: wygramMessageHistoryDirectory(mediaBox: a.mediaBox).appendingPathComponent(selected.attachments[0].localFileName!).path), "Removing a photo record removes the durable bytes")
        self.checks.append("Explicit record deletion removes its retained chat photo and durable file")
        // Restore a third record for the UI and restart checks.
        a.mediaBox.storeResourceData(resource.id, data: jpeg, synchronous: true)
        _ = await self.value(a.transaction { transaction -> Void in
            _ = transaction.addMessages([message(202, text: "三秒倒计时照片", attributes: [timed], media: [photo(755114, full: resource)])], location: .Random)
            _ = wygramRetainDisappearingPhoto(transaction: transaction, mediaBox: a.mediaBox, messageId: ids[1])
        })
        let finalResources = await self.value(a.transaction { transaction in
            ids.compactMap { transaction.getMessage($0) }.flatMap { message in
                message.media.compactMap { $0 as? TelegramMediaImage }.flatMap { $0.representations.map { $0.resource.id } }
            }
        })
        await self.completion(a.mediaBox.removeCachedResources([resource.id, thumbnail.id] + finalResources, force: true))
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
                    guard let textView = detail.legacyController.view.subviews.first(where: { $0 is UITextView }) as? UITextView, textView.text.contains("已保留的阅后即焚图片") else {
                        self.writeReport(passed: false, error: "Saved-version detail did not render saved text"); return
                    }
                    guard table.tableView.numberOfRows(inSection: 0) == 3,
                          let button = detail.legacyController.view.subviews.first(where: { $0 is UIButton }) as? UIButton,
                          !button.isHidden else {
                        self.writeReport(passed: false, error: "Photo toggle or saved attachment button missing"); return
                    }
                    button.sendActions(for: .touchUpInside)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard let preview = detail.legacyController.presentedViewController as? QLPreviewController,
                              preview.dataSource?.numberOfPreviewItems(in: preview) == 1,
                              let url = preview.dataSource?.previewController(preview, previewItemAt: 0).previewItemURL,
                              let bytes = try? Data(contentsOf: url), UIImage(data: bytes) != nil else {
                            self.writeReport(passed: false, error: "Saved attachment preview did not load a readable image"); return
                        }
                        self.checks.append("Production three-toggle history list opens saved-photo detail and Quick Look displays a valid saved JPEG")
                        self.writeReport(passed: true, error: nil)
                    }
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
