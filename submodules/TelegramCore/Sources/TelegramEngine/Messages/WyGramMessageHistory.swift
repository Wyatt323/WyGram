import Foundation
import CryptoKit
import Postbox
import SwiftSignalKit

public struct WyGramMessageHistorySettings: Codable {
    public var keepDeletedMessages: Bool
    public var keepEditHistory: Bool
    public var keepDisappearingPhotos: Bool
    public init(keepDeletedMessages: Bool = true, keepEditHistory: Bool = true, keepDisappearingPhotos: Bool = true) {
        self.keepDeletedMessages = keepDeletedMessages; self.keepEditHistory = keepEditHistory
        self.keepDisappearingPhotos = keepDisappearingPhotos
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.keepDeletedMessages = try values.decodeIfPresent(Bool.self, forKey: .keepDeletedMessages) ?? true
        self.keepEditHistory = try values.decodeIfPresent(Bool.self, forKey: .keepEditHistory) ?? true
        self.keepDisappearingPhotos = try values.decodeIfPresent(Bool.self, forKey: .keepDisappearingPhotos) ?? true
    }
}

private let wygramHistorySettingsKey: ValueBoxKey = {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: 0x57594d48)
    return key
}()

func wygramHistorySettings(transaction: Transaction) -> WyGramMessageHistorySettings {
    return transaction.getPreferencesEntry(key: wygramHistorySettingsKey)?.get(WyGramMessageHistorySettings.self) ?? WyGramMessageHistorySettings()
}

public func wygramMessageHistorySettings(postbox: Postbox) -> Signal<WyGramMessageHistorySettings, NoError> {
    return postbox.transaction { wygramHistorySettings(transaction: $0) }
}

public func wygramUpdateMessageHistorySettings(postbox: Postbox, settings: WyGramMessageHistorySettings) -> Signal<Void, NoError> {
    return postbox.transaction { transaction in
        transaction.updatePreferencesEntry(key: wygramHistorySettingsKey, { _ in PreferencesEntry(settings) })
    }
}

// A local, account-scoped ordered list. Server history and read state are not changed.
public let wygramMessageHistoryCollectionId: Int32 = 1976487

public struct WyGramArchivedAttachment: Codable {
    public let name: String
    public let mediaKey: String
    public let localFileName: String?
}

public struct WyGramArchivedMessage: Codable {
    public let key: Data
    public let peerId: Int64
    public let namespace: Int32
    public let messageId: Int32
    public let chatName: String
    public let authorName: String
    public let messageTimestamp: Int32
    public let versionTimestamp: Int32
    public let capturedAt: Int32
    public let reason: String
    public let text: String
    public let entities: [MessageTextEntity]
    public let mediaData: Data
    public let attachments: [WyGramArchivedAttachment]

    public var media: [Media] {
        let objects: [PostboxCoding] = PostboxDecoder(buffer: MemoryBuffer(data: self.mediaData)).decodeObjectArrayForKey("m")
        return objects.compactMap { $0 as? Media }
    }

    public var id: MessageId {
        return MessageId(peerId: PeerId(self.peerId), namespace: self.namespace, id: self.messageId)
    }
}

private func wygramPeerName(_ peer: Peer?) -> String {
    if let user = peer as? TelegramUser {
        return [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")
    } else if let group = peer as? TelegramGroup {
        return group.title
    } else if let channel = peer as? TelegramChannel {
        return channel.title
    }
    return ""
}

public func wygramMessageHistoryDirectory(mediaBox: MediaBox) -> URL {
    return URL(fileURLWithPath: mediaBox.basePath).deletingLastPathComponent().appendingPathComponent("wygram-message-history", isDirectory: true)
}

private func wygramCanArchive(_ message: Message) -> Bool {
    guard message.id.namespace == Namespaces.Message.Cloud,
          message.id.peerId.namespace != Namespaces.Peer.SecretChat,
          message.flags.contains(.Incoming) else { return false }
    // General edit/delete history excludes timed content; photos have a dedicated retention path.
    return !message.attributes.contains { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute || $0 is EphemeralMessageAttribute }
        && !message.media.contains { $0 is TelegramMediaAction }
}

private func wygramAttachmentKeys(_ media: [Media]) -> [String] {
    return media.compactMap { media in
        if let file = media as? TelegramMediaFile { return "file:\(file.fileId)" }
        if let image = media as? TelegramMediaImage { return "image:\(image.imageId)" }
        if let poll = media as? TelegramMediaPoll { return "poll:\(poll.pollId)" }
        if media is TelegramMediaWebpage { return nil }
        let encoder = PostboxEncoder()
        encoder.encodeRootObject(media)
        return String(describing: type(of: media)) + ":" + Data(SHA256.hash(data: encoder.makeData())).base64EncodedString()
    }
}

public func wygramArchivePreviousVersion(transaction: Transaction, mediaBox: MediaBox, replacement: StoreMessage) {
    if case let .Id(id) = replacement.id {
        _ = wygramRetainDisappearingPhoto(transaction: transaction, mediaBox: mediaBox, messageId: id)
    }
    guard wygramHistorySettings(transaction: transaction).keepEditHistory, case let .Id(id) = replacement.id,
          let previous = transaction.getMessage(id), wygramCanArchive(previous), previous.wygramRetainedPhotoAttribute == nil, previous.wygramHistoryAttribute?.deletedAt == nil else { return }
    let previousEntities = previous.textEntitiesAttribute?.entities ?? []
    let newEntities = (replacement.attributes.first { $0 is TextEntitiesMessageAttribute } as? TextEntitiesMessageAttribute)?.entities ?? []
    guard previous.text != replacement.text || previousEntities != newEntities || wygramAttachmentKeys(previous.media) != wygramAttachmentKeys(replacement.media) else { return }
    wygramArchiveMessage(transaction: transaction, mediaBox: mediaBox, message: previous, reason: "edited")
    wygramSetHistoryAttribute(transaction: transaction, message: previous, deletedAt: previous.wygramHistoryAttribute?.deletedAt, hasVersions: true)
}

func wygramStoreMessage(_ message: Message, attributes: [MessageAttribute]) -> StoreMessage {
    let forward = message.forwardInfo.map { StoreMessageForwardInfo(authorId: $0.author?.id, sourceId: $0.source?.id, sourceMessageId: $0.sourceMessageId, date: $0.date, authorSignature: $0.authorSignature, psaType: $0.psaType, flags: $0.flags) }
    return StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: forward, authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media)
}

private func wygramSetHistoryAttribute(transaction: Transaction, message: Message, deletedAt: Int32?, hasVersions: Bool) {
    var attributes = message.attributes.filter { !($0 is WyGramMessageHistoryAttribute) }
    attributes.append(WyGramMessageHistoryAttribute(deletedAt: deletedAt, hasPreviousVersions: hasVersions))
    transaction.updateMessage(message.id, update: { _ in .update(wygramStoreMessage(message, attributes: attributes)) })
}

public func wygramPrepareRemoteMessages(transaction: Transaction, mediaBox: MediaBox, messages: [StoreMessage]) -> [StoreMessage] {
    return messages.map { message in
        wygramArchivePreviousVersion(transaction: transaction, mediaBox: mediaBox, replacement: message)
        return wygramApplyLocalMessageHistory(transaction: transaction, replacement: message)
    }
}

public func wygramApplyLocalMessageHistory(transaction: Transaction, replacement: StoreMessage) -> StoreMessage {
    if case let .Id(id) = replacement.id, let previous = transaction.getMessage(id), previous.wygramRetainedPhotoAttribute != nil {
        return wygramStoreMessage(previous, attributes: previous.attributes)
    }
    guard case let .Id(id) = replacement.id, let previous = transaction.getMessage(id), let local = previous.wygramHistoryAttribute else { return replacement }
    if local.deletedAt != nil { return wygramStoreMessage(previous, attributes: previous.attributes) }
    var attributes = replacement.attributes.filter { !($0 is WyGramMessageHistoryAttribute) }
    attributes.append(local)
    return replacement.withUpdatedAttributes(attributes)
}

// Only remote deletion paths call this function. Manual local deletion stays available.
public func wygramPrepareRemoteMessageDeletion(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) -> [MessageId] {
    let enabled = wygramHistorySettings(transaction: transaction).keepDeletedMessages
    var remove: [MessageId] = []
    for id in ids {
        if wygramRetainDisappearingPhoto(transaction: transaction, mediaBox: mediaBox, messageId: id) { continue }
        guard let message = transaction.getMessage(id) else { remove.append(id); continue }
        if message.wygramHistoryAttribute?.deletedAt != nil { continue }
        if enabled && wygramCanArchive(message) {
            wygramArchiveMessage(transaction: transaction, mediaBox: mediaBox, message: message, reason: "deleted")
            wygramSetHistoryAttribute(transaction: transaction, message: message, deletedAt: Int32(Date().timeIntervalSince1970), hasVersions: message.wygramHistoryAttribute?.hasPreviousVersions ?? false)
        } else { remove.append(id) }
    }
    return remove
}

public func wygramPrepareRemoteMessageRangeDeletion(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, namespace: MessageId.Namespace, maxId: Int32) -> [MessageId] {
    var ids: [MessageId] = []
    transaction.withAllMessages(peerId: peerId, namespace: namespace) { message in
        if message.id.id > 0 && message.id.id <= maxId { ids.append(message.id) }
        return true
    }
    return wygramPrepareRemoteMessageDeletion(transaction: transaction, mediaBox: mediaBox, ids: ids)
}

private func wygramArchiveMessage(transaction: Transaction, mediaBox: MediaBox, message: Message, reason: String) {
    let editedDate = (message.attributes.first { $0 is EditedMessageAttribute } as? EditedMessageAttribute)?.date ?? message.timestamp
    let entities = PostboxEncoder()
    entities.encodeObjectArray(message.textEntitiesAttribute?.entities ?? [], forKey: "e")
    var identity = Data("\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id):\(editedDate):\(reason):\(message.text)".utf8)
    identity.append(entities.makeData())
    identity.append(Data(wygramAttachmentKeys(message.media).joined(separator: "|").utf8))
    let key = Data(SHA256.hash(data: identity))
    let itemId = MemoryBuffer(data: key)
    guard transaction.getOrderedItemListItem(collectionId: wygramMessageHistoryCollectionId, itemId: itemId) == nil else { return }
    let directory = wygramMessageHistoryDirectory(mediaBox: mediaBox)
    var attachments: [WyGramArchivedAttachment] = []
    func save(_ resource: MediaResource?, name: String, mediaKey: String, extension fileExtension: String) {
        var localFileName: String?
        if let resource = resource, let path = mediaBox.completedResourcePath(resource) {
            let safeExtension = fileExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(10)
            let fileName = UUID().uuidString + (safeExtension.isEmpty ? "" : "." + safeExtension)
            let destination = directory.appendingPathComponent(fileName)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                do { try FileManager.default.linkItem(atPath: path, toPath: destination.path) }
                catch { try FileManager.default.copyItem(atPath: path, toPath: destination.path) }
                localFileName = fileName
            } catch {
                // Text is still retained if a downloaded file cannot be copied.
            }
        }
        attachments.append(WyGramArchivedAttachment(name: name, mediaKey: mediaKey, localFileName: localFileName))
    }
    for media in message.media {
        if let file = media as? TelegramMediaFile {
            let name = file.fileName ?? (file.isVideo ? "Video.mp4" : file.isVoice ? "Voice.ogg" : "File")
            save(file.resource, name: name, mediaKey: "file:\(file.fileId)", extension: (name as NSString).pathExtension)
        } else if let image = media as? TelegramMediaImage {
            let available = image.representations.reversed().first { mediaBox.completedResourcePath($0.resource) != nil }
            save(available?.resource, name: "Photo.jpg", mediaKey: "image:\(image.imageId)", extension: "jpg")
        } else if !(media is TelegramMediaWebpage) {
            save(nil, name: String(describing: type(of: media)), mediaKey: String(describing: media.id), extension: "")
        }
    }
    let mediaEncoder = PostboxEncoder()
    mediaEncoder.encodeGenericObjectArray(message.media, forKey: "m")
    let entry = WyGramArchivedMessage(key: key, peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id,
        chatName: wygramPeerName(message.peers[message.id.peerId] ?? transaction.getPeer(message.id.peerId)), authorName: wygramPeerName(message.author),
        messageTimestamp: message.timestamp, versionTimestamp: editedDate, capturedAt: Int32(Date().timeIntervalSince1970), reason: reason, text: message.text, entities: message.textEntitiesAttribute?.entities ?? [], mediaData: mediaEncoder.makeData(), attachments: attachments)
    if let contents = CodableEntry(entry) {
        transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: wygramMessageHistoryCollectionId, item: OrderedItemListEntry(id: itemId, contents: contents), removeTailIfCountExceeds: nil)
    }
}

public func wygramMessageHistory(postbox: Postbox, messageId: MessageId? = nil, peerId: PeerId? = nil) -> Signal<[WyGramArchivedMessage], NoError> {
    return postbox.transaction { transaction in
        transaction.getOrderedListItems(collectionId: wygramMessageHistoryCollectionId).compactMap { $0.contents.get(WyGramArchivedMessage.self) }.filter { entry in
            (messageId == nil || entry.id == messageId) && (peerId == nil || entry.id.peerId == peerId)
        }
    }
}

public func wygramRemoveMessageHistory(postbox: Postbox, keys: [Data]? = nil) -> Signal<Void, NoError> {
    return postbox.transaction { transaction in
        let entries = transaction.getOrderedListItems(collectionId: wygramMessageHistoryCollectionId)
        let selected = keys.map(Set.init)
        let directory = wygramMessageHistoryDirectory(mediaBox: postbox.mediaBox)
        var affectedIds = Set<MessageId>()
        for item in entries {
            if let entry = item.contents.get(WyGramArchivedMessage.self), selected == nil || selected!.contains(entry.key) {
                affectedIds.insert(entry.id)
                transaction.removeOrderedItemListItem(collectionId: wygramMessageHistoryCollectionId, itemId: item.id)
                for attachment in entry.attachments {
                    if let name = attachment.localFileName { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
                }
            }
        }
        let remaining = transaction.getOrderedListItems(collectionId: wygramMessageHistoryCollectionId).compactMap { $0.contents.get(WyGramArchivedMessage.self) }
        for id in affectedIds {
            if let message = transaction.getMessage(id), let retained = message.wygramRetainedPhotoAttribute,
               !remaining.contains(where: { $0.key == retained.archiveKey }) {
                var resourceIds: [MediaResourceId] = []
                addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
                let _ = postbox.mediaBox.removeCachedResources(resourceIds, force: true).start()
                _internal_deleteMessages(transaction: transaction, mediaBox: postbox.mediaBox, ids: [id])
                continue
            }
            if let message = transaction.getMessage(id), let local = message.wygramHistoryAttribute {
                let hasVersions = remaining.contains { $0.id == id && $0.reason == "edited" }
                if local.deletedAt == nil && !hasVersions {
                    let attributes = message.attributes.filter { !($0 is WyGramMessageHistoryAttribute) }
                    transaction.updateMessage(id, update: { _ in .update(wygramStoreMessage(message, attributes: attributes)) })
                } else {
                    wygramSetHistoryAttribute(transaction: transaction, message: message, deletedAt: local.deletedAt, hasVersions: hasVersions)
                }
            }
        }
    }
}
