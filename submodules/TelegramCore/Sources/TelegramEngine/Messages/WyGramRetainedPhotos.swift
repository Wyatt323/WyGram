import Foundation
import CryptoKit
import Postbox
import SwiftSignalKit

// Keep the durable copy outside MediaBox's evictable cache. The resource uses the
// existing LocalFileMediaResource codec, including its FlatBuffers representation.
// Resolve its filename against this account on each fetch, never a saved container path.
public func wygramRetainedPhotoPath(mediaBox: MediaBox, resource: LocalFileMediaResource) -> String {
    return wygramMessageHistoryDirectory(mediaBox: mediaBox).appendingPathComponent("retained-photo-\(resource.fileId).jpg").path
}

public func wygramIsDisappearingPhoto(_ message: Message) -> Bool {
    guard message.flags.contains(.Incoming),
          message.id.namespace == Namespaces.Message.Cloud || message.id.peerId.namespace == Namespaces.Peer.SecretChat,
          !message.attributes.contains(where: { $0 is EphemeralMessageAttribute }),
          message.media.count == 1, let image = message.media.first as? TelegramMediaImage,
          image.video == nil, image.videoRepresentations.isEmpty else { return false }
    if let timeout = message.autoclearAttribute?.timeout, timeout > 0 { return true }
    return message.id.peerId.namespace == Namespaces.Peer.SecretChat && (message.autoremoveAttribute?.timeout ?? 0) > 0
}

// Called inside the same transaction as consumption, expiration, or a remote
// replacement/deletion. No timer is removed until a complete image is safely copied.
@discardableResult
public func wygramRetainDisappearingPhoto(transaction: Transaction, mediaBox: MediaBox, messageId: MessageId) -> Bool {
    guard let message = transaction.getMessage(messageId) else { return false }
    if message.wygramRetainedPhotoAttribute != nil { return true }
    guard wygramHistorySettings(transaction: transaction).keepDisappearingPhotos,
          wygramIsDisappearingPhoto(message), let image = message.media.first as? TelegramMediaImage,
          let representation = image.representations.max(by: {
              Int64($0.dimensions.width) * Int64($0.dimensions.height) < Int64($1.dimensions.width) * Int64($1.dimensions.height)
          }), let sourcePath = mediaBox.completedResourcePath(representation.resource),
          let size = (try? FileManager.default.attributesOfItem(atPath: sourcePath)[.size]) as? NSNumber,
          size.int64Value > 0 else { return false }

    let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: size.int64Value)
    let directory = wygramMessageHistoryDirectory(mediaBox: mediaBox)
    let destination = URL(fileURLWithPath: wygramRetainedPhotoPath(mediaBox: mediaBox, resource: resource))
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: sourcePath, toPath: destination.path)
        let copiedSize = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
        guard copiedSize?.int64Value == size.int64Value else {
            try? FileManager.default.removeItem(at: destination)
            return false
        }
    } catch {
        // Keep the original lifecycle if the file cannot be retained (e.g. disk full).
        return false
    }

    let key = Data(SHA256.hash(data: Data("retained-photo:\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)".utf8)))
    let mediaEncoder = PostboxEncoder()
    mediaEncoder.encodeGenericObjectArray(message.media, forKey: "m")
    func name(_ peer: Peer?) -> String {
        if let user = peer as? TelegramUser { return [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ") }
        if let group = peer as? TelegramGroup { return group.title }
        if let channel = peer as? TelegramChannel { return channel.title }
        return ""
    }
    let entry = WyGramArchivedMessage(key: key, peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id,
        chatName: name(message.peers[message.id.peerId] ?? transaction.getPeer(message.id.peerId)), authorName: name(message.author),
        messageTimestamp: message.timestamp, versionTimestamp: message.timestamp, capturedAt: Int32(Date().timeIntervalSince1970), reason: "disappearing",
        text: message.text, entities: message.textEntitiesAttribute?.entities ?? [], mediaData: mediaEncoder.makeData(),
        attachments: [WyGramArchivedAttachment(name: "Photo.jpg", mediaKey: "image:\(image.imageId)", localFileName: destination.lastPathComponent)])
    guard let contents = CodableEntry(entry) else {
        try? FileManager.default.removeItem(at: destination)
        return false
    }
    transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: wygramMessageHistoryCollectionId,
        item: OrderedItemListEntry(id: MemoryBuffer(data: key), contents: contents), removeTailIfCountExceeds: nil)

    // Prime the normal cache for immediate display; a cache miss can always fetch
    // from the independent copy through wygramFetchRetainedPhoto below.
    mediaBox.copyResourceData(from: representation.resource.id, to: resource.id, synchronous: true)
    let retainedImage = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: resource.fileId),
        representations: [TelegramMediaImageRepresentation(dimensions: representation.dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: nil)],
        immediateThumbnailData: image.immediateThumbnailData, reference: nil, partialReference: nil, flags: image.flags)
    var attributes = message.attributes.filter { !($0 is AutoremoveTimeoutMessageAttribute) && !($0 is AutoclearTimeoutMessageAttribute) }
    attributes.append(WyGramRetainedPhotoAttribute(archiveKey: key))
    let retained = wygramStoreMessage(message, attributes: attributes).withUpdatedMedia([retainedImage])
    transaction.updateMessage(message.id, update: { _ in .update(retained) })
    return true
}

public func wygramFetchRetainedPhoto(mediaBox: MediaBox, resource: MediaResource) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError>? {
    guard let resource = resource as? LocalFileMediaResource else { return nil }
    let path = wygramRetainedPhotoPath(mediaBox: mediaBox, resource: resource)
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    // Emit a complete data range so both MediaBox versions finish full-range
    // fetch requests. V2's copyLocalItem updates the file but not its range map.
    return Signal { subscriber in
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
            guard !data.isEmpty else {
                subscriber.putError(.generic)
                return EmptyDisposable
            }
            subscriber.putNext(.dataPart(resourceOffset: 0, data: data, range: 0 ..< Int64(data.count), complete: true))
            subscriber.putCompletion()
        } catch {
            subscriber.putError(.generic)
        }
        return EmptyDisposable
    }
}
