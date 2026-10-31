import Foundation
import UniformTypeIdentifiers
import UIKit
import SwiftSignalKit
import SGAppGroupIdentifier
import Postbox
import TelegramCore
import AccountContext
import Display
import AppLock
import TelegramPresentationData
import PresentationDataUtils

final class WyGramShareInboxPresenter {
    private let readyDisposable = MetaDisposable()
    private weak var context: AuthorizedApplicationContext?
    private var coordinator: WyGramShareInboxCoordinator?
    private var controller: ViewController?
    private var importObserver: NSObjectProtocol?

    init() {
        self.importObserver = NotificationCenter.default.addObserver(forName: WyGramShareInbox.importRequested, object: nil, queue: .main) { [weak self] _ in
            self?.coordinator?.refresh()
        }
    }

    func check(context: AuthorizedApplicationContext) {
        if self.context === context {
            self.coordinator?.refresh()
            return
        }
        self.coordinator?.stop()
        self.context = context
        self.controller?.dismiss()
        self.controller = nil
        guard let lock = context.context.sharedContext.appLockContext as? AppLockContextImpl else { return }
        let coordinator = WyGramShareInboxCoordinator(canPresent: { [weak context] in
            guard let context else { return false }
            return UIApplication.shared.applicationState == .active && context.rootController.currentWindow != nil
        }, present: { [weak self, weak context] entry in
            guard let self, let context else { return false }
            return self.present(context: context, inbox: entry.inbox, batch: entry.batch)
        }, status: { status in
            WyGramShareInbox.recordImportStatus(status)
        })
        self.coordinator = coordinator
        // Keep observing all three gates. A one-shot ready signal can fire
        // while the scene is inactive or before its root is in a window.
        self.readyDisposable.set((combineLatest(context.isReady.get(), lock.isCurrentlyLocked, context.context.sharedContext.applicationBindings.applicationIsActive)
        |> deliverOnMainQueue).start(next: { [weak coordinator] ready, locked, active in
            if !ready { WyGramShareInbox.recordImportStatus("waiting-account") }
            else if locked { WyGramShareInbox.recordImportStatus("locked") }
            else if !active { WyGramShareInbox.recordImportStatus("inactive") }
            coordinator?.setEligible(ready && !locked && active)
        }))
    }

    func deactivate() {
        self.readyDisposable.set(nil)
        self.coordinator?.stop()
        self.coordinator = nil
        self.context = nil
        self.controller?.dismiss()
        self.controller = nil
    }

    private func present(context: AuthorizedApplicationContext, inbox: WyGramShareInbox, batch: WyGramShareInbox.Batch) -> Bool {
        guard UIApplication.shared.applicationState == .active, let window = context.rootController.currentWindow else { return false }
        context.rootController.view.endEditing(true)
        let coordinator = self.coordinator
        let params = ShareControllerParams(subject: .fromExternal(batch.items.count, { [weak self, weak context] peerIds, threadIds, requireStars, text, account, silently in
            let sending: Signal<ShareControllerExternalStatus, ShareControllerError>
            if !peerIds.isEmpty, let appAccount = account as? ShareControllerAppAccountContext {
                let destination = appAccount.context.account
                sending = Self.prepare(inbox: inbox, batch: batch, account: destination)
            |> mapToSignal { files -> Signal<ShareControllerExternalStatus, ShareControllerError> in
                let signals = peerIds.map { peerId -> Signal<[MessageId?], NoError> in
                    var attributes: [MessageAttribute] = []
                    if silently { attributes.append(NotificationInfoMessageAttribute(flags: [.muted])) }
                    if let stars = requireStars[peerId] { attributes.append(PaidStarsMessageAttribute(stars: stars, postponeSending: false)) }
                    let messages: [EnqueueMessage] = files.enumerated().map { index, file in
                        return .message(text: index == 0 ? text : "", attributes: attributes, inlineStickers: [:], mediaReference: .standalone(media: file), threadId: threadIds[peerId], replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                    }
                    return enqueueMessages(account: destination, peerId: peerId, messages: messages)
                }
                return combineLatest(signals)
                |> castError(ShareControllerError.self)
                |> mapToSignal { ids -> Signal<ShareControllerExternalStatus, ShareControllerError> in
                    guard ids.allSatisfy({ $0.count == files.count && $0.allSatisfy({ $0 != nil }) }) else { return .fail(.generic) }
                    return .single(.done)
                }
            }
            } else {
                sending = .fail(.generic)
            }
            return .single(.preparing(false))
            |> then(sending)
            |> `catch` { _ -> Signal<ShareControllerExternalStatus, ShareControllerError> in
                Queue.concurrentDefaultQueue().async {
                    // Retire this batch before allowing another scan, including
                    // when enqueueing failed after a partially accepted send.
                    inbox.remove(id: batch.id)
                    Queue.mainQueue().async {
                        guard let self, let context, self.context === context else { return }
                        self.controller?.dismiss(completion: {
                            self.controller = nil
                            coordinator?.finished()
                            let presentationData = context.context.sharedContext.currentPresentationData.with { $0 }
                            let alert = textAlertController(context: context.context, title: "文件分享未完成", text: "文件未能完整加入发送队列。请到目标聊天确认发送情况，再通过“附件 → 文件”重试。", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})])
                            context.rootController.currentWindow?.present(alert, on: .root, blockInteraction: false, completion: {})
                        })
                    }
                }
                return .never()
            }
        }), fromForeignApp: true, externalShare: false, dismissed: { [weak self, weak context] _ in
            // Account changes/logout dismiss UI without consuming attachments.
            guard let self, let context, self.context === context else { return }
            // Copies already accepted into the account's MediaBox outlive the
            // inbox. Cancellation removes only this pending file handoff.
            self.controller = nil
            Queue.concurrentDefaultQueue().async {
                inbox.remove(id: batch.id)
                Queue.mainQueue().after(0.5) { coordinator?.finished() }
            }
        })
        let controller = context.context.sharedContext.makeShareController(context: context.context, params: params)
        self.controller = controller
        window.present(controller, on: .root, blockInteraction: false, completion: {})
        return true
    }

    private static func prepare(inbox: WyGramShareInbox, batch: WyGramShareInbox.Batch, account: Account) -> Signal<[TelegramMediaFile], ShareControllerError> {
        return Signal { subscriber in
            Queue.concurrentDefaultQueue().async {
                var paths: [String] = []
                do {
                    // Revalidate immediately before copying; do not trust URL
                    // schemes, stale manifests or paths supplied by another app.
                    guard inbox.pending().contains(where: { $0.id == batch.id }) else { throw CocoaError(.fileReadCorruptFile) }
                    var files: [TelegramMediaFile] = []
                    for item in batch.items {
                        let id = Int64.random(in: Int64.min ... Int64.max)
                        let resource = LocalFileMediaResource(fileId: id, size: item.size)
                        let path = account.postbox.mediaBox.resourcePath(resource)
                        try FileManager.default.copyItem(at: inbox.fileURL(batch: batch, item: item), to: URL(fileURLWithPath: path))
                        paths.append(path)
                        guard (try URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey])).fileSize == Int(item.size) else { throw CocoaError(.fileReadCorruptFile) }
                        let mime = UTType(filenameExtension: (item.name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        files.append(TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mime, size: item.size, attributes: [.FileName(fileName: item.name)], alternativeRepresentations: []))
                    }
                    subscriber.putNext(files)
                    subscriber.putCompletion()
                } catch {
                    for path in paths { try? FileManager.default.removeItem(atPath: path) }
                    subscriber.putError(.generic)
                }
            }
            return EmptyDisposable
        }
    }

    deinit {
        self.readyDisposable.dispose()
        self.coordinator?.stop()
        if let observer = self.importObserver { NotificationCenter.default.removeObserver(observer) }
    }
}
