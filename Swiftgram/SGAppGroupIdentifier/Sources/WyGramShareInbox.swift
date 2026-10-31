import Foundation

// A file handoff only. Account databases, keys and session data never enter this
// inbox. Entitlement discovery cannot grant access: containerURL must succeed.
public struct WyGramShareInbox {
    public struct Item: Codable {
        public let file: String
        public let name: String
        public let size: Int64
    }

    public struct Batch: Codable {
        public let id: String
        public let created: Date
        public let items: [Item]
    }

    public let directory: URL
    public static let lifetime: TimeInterval = 3600
    public static let maximumBytes: Int64 = 2 * 1024 * 1024 * 1024
    public static let maximumItems = 100
    public static let importRequested = Notification.Name("WyGramShareInbox.importRequested")
    public static let importStatusKey = "wygram.shareInbox.importStatus"

    // Main-app diagnostics contain no filenames, paths, account or chat IDs.
    public static func recordImportStatus(_ status: String) {
        UserDefaults.standard.set(status, forKey: self.importStatusKey)
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public static func current() -> [WyGramShareInbox] {
        let main = WyGramPushCapabilities.enclosingApplication()
        guard let identifier = main.bundleIdentifier, !identifier.isEmpty,
              identifier.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").inverted) == nil,
              !identifier.contains("..") else { return [] }
        // Both processes must discover the same actually signed intersection,
        // rather than different profile/canonical-name candidate lists.
        return WyGramDirectShare.availableGroups().map { group in
            return WyGramShareInbox(directory: group.url.appendingPathComponent("WyGramShareInbox", isDirectory: true).appendingPathComponent(identifier, isDirectory: true))
        }
    }

    public static func canUseSharedAccount(group: URL?, inboxes: [WyGramShareInbox]) -> Bool {
        guard let group, inboxes.contains(where: { $0.storageMode == "shared" }), !inboxes.contains(where: { $0.mainUsesLocalStorage }) else { return false }
        let root = group.appendingPathComponent("telegram-data", isDirectory: true)
        let key = root.appendingPathComponent(".tempkey")
        // Do not let an extension generate a replacement encryption key for an
        // inaccessible/stale account store. The main app prepares this file.
        guard let values = try? key.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == 48,
              let bytes = try? Data(contentsOf: key), bytes.count == 48 else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("accounts-metadata").path)
    }

    public func publishStorage(shared: Bool) {
        do {
            try self.prepare()
            try Data((shared ? "shared" : "local").utf8).write(to: self.directory.appendingPathComponent("storage-mode"), options: .atomic)
        } catch {
            // An unavailable bridge must not affect the account's storage choice.
        }
    }

    public func publishAccountStorage(group: URL?) {
        let root = self.directory.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        self.publishStorage(shared: group.map { $0.resolvingSymlinksInPath().standardizedFileURL == root } ?? false)
    }

    // A container lookup in the extension alone does not establish that the
    // main app reads this inbox. Prefer a directory it has actually prepared,
    // including when re-signing makes a different App Group available first.
    public static func preparedForImport(inboxes: [WyGramShareInbox]) -> WyGramShareInbox? {
        return inboxes.first(where: { $0.storageMode != nil })
    }

    public var mainUsesLocalStorage: Bool {
        return self.storageMode == "local"
    }

    private var storageMode: String? {
        let url = self.directory.appendingPathComponent("storage-mode")
        guard self.regularFile(url, maximumSize: 16), let data = try? Data(contentsOf: url),
              let mode = String(data: data, encoding: .utf8), ["shared", "local"].contains(mode) else { return nil }
        return mode
    }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard self.realDirectory(self.directory) else { throw CocoaError(.fileWriteNoPermission) }
    }

    public func begin(id: String) throws {
        guard Self.validId(id) else { throw CocoaError(.fileWriteInvalidFileName) }
        try self.prepare()
        try FileManager.default.createDirectory(at: self.staging(id), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    // Call inside NSItemProvider's callback, before its temporary URL expires.
    public func copy(source: URL, name: String, id: String, index: Int, remainingBytes: Int64) throws -> Item {
        guard Self.validId(id), index >= 0, index < Self.maximumItems, source.isFileURL,
              self.realDirectory(self.staging(id)) else { throw CocoaError(.fileReadInvalidFileName) }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, Int64(size) <= remainingBytes, size >= 0 else { throw CocoaError(.fileReadTooLarge) }
        let file = "\(index).data"
        let destination = self.staging(id).appendingPathComponent(file)
        try FileManager.default.copyItem(at: source, to: destination)
        guard self.regularFile(destination, maximumSize: remainingBytes),
              (try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize == size else { throw CocoaError(.fileReadCorruptFile) }
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: destination.path)
        let safeName = (name as NSString).lastPathComponent
        return Item(file: file, name: safeName.isEmpty ? "file" : String(safeName.prefix(240)), size: Int64(size))
    }

    public func finish(id: String, items: [Item]) throws -> Batch {
        let batch = Batch(id: id, created: Date(), items: items)
        guard self.valid(batch, folder: self.staging(id)) else { throw CocoaError(.fileReadCorruptFile) }
        try JSONEncoder().encode(batch).write(to: self.staging(id).appendingPathComponent("manifest.json"), options: .atomic)
        // Atomic publication: the main app cannot see a half-copied batch.
        try FileManager.default.moveItem(at: self.staging(id), to: self.folder(id))
        return batch
    }

    public func pending(now: Date = Date()) -> [Batch] {
        let children = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        // A killed extension may leave an unpublished copy behind. It must not
        // retain sensitive selected files indefinitely or become a pending send.
        for child in children {
            let name = child.lastPathComponent
            let id = name.hasPrefix(".") && name.hasSuffix(".tmp") ? String(name.dropFirst().dropLast(4)) : name
            if Self.validId(id), let created = (try? child.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
               now.timeIntervalSince(created) > Self.lifetime { self.remove(id: id) }
        }
        return children.prefix(200).compactMap { folder -> Batch? in
            guard Self.validId(folder.lastPathComponent) else { return nil }
            let manifest = folder.appendingPathComponent("manifest.json")
            guard self.realDirectory(folder), self.regularFile(manifest, maximumSize: 128 * 1024),
                  let data = try? Data(contentsOf: manifest),
                  let batch = try? JSONDecoder().decode(Batch.self, from: data), batch.id == folder.lastPathComponent else { return nil }
            guard batch.created.timeIntervalSince(now) <= 60, now.timeIntervalSince(batch.created) <= Self.lifetime else {
                self.remove(id: batch.id)
                return nil
            }
            return self.valid(batch, folder: folder) ? batch : nil
        }.sorted { $0.created < $1.created }
    }

    public func fileURL(batch: Batch, item: Item) -> URL {
        return self.folder(batch.id).appendingPathComponent(item.file)
    }

    public func remove(id: String) {
        guard Self.validId(id) else { return }
        try? FileManager.default.removeItem(at: self.folder(id))
        try? FileManager.default.removeItem(at: self.staging(id))
    }

    public static func validId(_ id: String) -> Bool {
        return UUID(uuidString: id)?.uuidString == id
    }

    private func folder(_ id: String) -> URL { return self.directory.appendingPathComponent(id, isDirectory: true) }
    private func staging(_ id: String) -> URL { return self.directory.appendingPathComponent(".\(id).tmp", isDirectory: true) }

    private func realDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func regularFile(_ url: URL, maximumSize: Int64) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              let size = values.fileSize else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true && size >= 0 && Int64(size) <= maximumSize
    }

    private func valid(_ batch: Batch, folder: URL) -> Bool {
        guard Self.validId(batch.id), self.realDirectory(folder), !batch.items.isEmpty, batch.items.count <= Self.maximumItems else { return false }
        var total: Int64 = 0
        for (index, item) in batch.items.enumerated() {
            guard item.file == "\(index).data", !item.name.isEmpty, item.name.count <= 240,
                  item.name == (item.name as NSString).lastPathComponent, item.name != ".", item.name != "..",
                  item.size >= 0, item.size <= Self.maximumBytes - total,
                  self.regularFile(folder.appendingPathComponent(item.file), maximumSize: item.size),
                  (try? folder.appendingPathComponent(item.file).resourceValues(forKeys: [.fileSizeKey]))?.fileSize == Int(item.size) else { return false }
            total += item.size
        }
        return true
    }
}
