import Foundation
import Darwin

public enum WyGramDirectShare {
    public static let selectionKey = "wygram.applicationDataStorage"
    public static let groupKey = "wygram.applicationDataStorage.group"
    public static let requestKey = "wygram.directShare.request"
    public static let resultKey = "wygram.directShare.result"
    static let journalName = ".wygram-direct-share-transition.json"

    public struct Group {
        public let identifier: String
        public let url: URL
        public init(identifier: String, url: URL) { self.identifier = identifier; self.url = url }
    }

    public static func commonSignedGroups(mainExecutable: Data, shareExecutable: Data) -> Set<String> {
        let main = WyGramPushCapabilities(entitlements: WyGramPushCapabilities.signedEntitlements(mainExecutable))
        let share = WyGramPushCapabilities(entitlements: WyGramPushCapabilities.signedEntitlements(shareExecutable))
        return Set(main.groups).intersection(share.groups)
    }

    public static func availableGroups() -> [Group] {
        let main = WyGramPushCapabilities.enclosingApplication()
        guard let identifier = main.bundleIdentifier,
              let extensions = try? FileManager.default.contentsOfDirectory(at: main.bundleURL.appendingPathComponent("PlugIns"), includingPropertiesForKeys: nil),
              let share = extensions.compactMap({ Bundle(url: $0) }).first(where: {
                  ($0.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.share-services"
              }), let mainURL = main.executableURL, let shareURL = share.executableURL,
              let mainData = try? Data(contentsOf: mainURL, options: .mappedIfSafe),
              let shareData = try? Data(contentsOf: shareURL, options: .mappedIfSafe) else { return [] }
        // Profiles describe permitted capabilities, not the entitlements actually
        // signed into each executable. Do not move an account on profile hints.
        let common = self.commonSignedGroups(mainExecutable: mainData, shareExecutable: shareData)
        let canonical = "group." + identifier
        return common.sorted { a, b in a == canonical ? b != canonical : (b == canonical ? false : a < b) }.compactMap { group in
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
            return Group(identifier: group, url: url)
        }
    }

    public static func sharedAccountGroup() -> Group? {
        return self.availableGroups().first { group in
            let main = WyGramPushCapabilities.enclosingApplication().bundleIdentifier ?? ""
            let inbox = WyGramShareInbox(directory: group.url.appendingPathComponent("WyGramShareInbox").appendingPathComponent(main))
            return WyGramShareInbox.canUseSharedAccount(group: group.url, inboxes: [inbox])
        }
    }

    public static func request(group: Group, defaults: UserDefaults = .standard) -> Bool {
        defaults.set(group.identifier, forKey: self.requestKey)
        defaults.removeObject(forKey: self.resultKey)
        return defaults.synchronize()
    }

    private struct Journal: Codable {
        let group: String
        let device: Int64
        let inode: UInt64
    }

    private static func identity(_ url: URL) -> (Int64, UInt64)? {
        var value = stat()
        guard lstat(url.path, &value) == 0, value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return nil }
        return (Int64(value.st_dev), UInt64(value.st_ino))
    }

    private static func validStore(_ url: URL) -> Bool {
        let key = url.appendingPathComponent(".tempkey")
        guard self.identity(url) != nil, self.identity(url.appendingPathComponent("accounts-metadata")) != nil,
              let values = try? key.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true && values.fileSize == 48
    }

    private static func matches(_ url: URL, journal: Journal) -> Bool {
        guard let (device, inode) = self.identity(url) else { return false }
        return device == journal.device && inode == journal.inode && self.validStore(url)
    }

    private static func commit(_ group: Group, journal: URL, defaults: UserDefaults) {
        defaults.set(group.identifier, forKey: self.groupKey)
        defaults.set("shared", forKey: self.selectionKey)
        defaults.removeObject(forKey: self.requestKey)
        defaults.set("enabled", forKey: self.resultKey)
        // Keep the recovery journal if preferences cannot be flushed. A restart
        // must never create an empty private account store after a successful move.
        if defaults.synchronize() { try? FileManager.default.removeItem(at: journal) }
    }

    // Called before ANY account, encryption key or logger opens the store. Only
    // an explicit in-app request enables this transition. rename is atomic and
    // never falls back to copying databases/session keys across containers.
    public static func performRequestedTransition(localDirectory: URL, groups: [Group], defaults: UserDefaults = .standard, mover: ((URL, URL) throws -> Void)? = nil) throws -> Group? {
        let fm = FileManager.default
        let source = localDirectory.appendingPathComponent("telegram-data")
        let journalURL = localDirectory.appendingPathComponent(self.journalName)
        if fm.fileExists(atPath: journalURL.path) {
            guard let values = try? journalURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 8193) <= 8192,
                  let data = try? Data(contentsOf: journalURL), let journal = try? JSONDecoder().decode(Journal.self, from: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let group = groups.first(where: { $0.identifier == journal.group }),
               self.matches(group.url.appendingPathComponent("telegram-data"), journal: journal),
               !fm.fileExists(atPath: source.path) {
                self.commit(group, journal: journalURL, defaults: defaults)
                return group
            }
            // If the original directory is still present, no move occurred.
            // A missing source without the exact destination is an error, not
            // permission to initialise a new empty account database.
            guard self.matches(source, journal: journal) else { throw CocoaError(.fileReadNoPermission) }
            try fm.removeItem(at: journalURL)
            defaults.removeObject(forKey: self.requestKey)
            defaults.set("interrupted", forKey: self.resultKey)
            return nil
        }
        guard let requested = defaults.string(forKey: self.requestKey) else { return nil }
        guard let group = groups.first(where: { $0.identifier == requested }) else {
            defaults.removeObject(forKey: self.requestKey)
            defaults.set("permissions", forKey: self.resultKey)
            return nil
        }
        let destination = group.url.appendingPathComponent("telegram-data")
        guard self.validStore(source), let (device, inode) = self.identity(source),
              self.identity(localDirectory) != nil, self.identity(group.url) != nil else {
            defaults.removeObject(forKey: self.requestKey)
            defaults.set("source", forKey: self.resultKey)
            return nil
        }
        // Never merge or replace another account directory, including an empty
        // or stale directory previously created by a different installation.
        guard !fm.fileExists(atPath: destination.path) else {
            defaults.removeObject(forKey: self.requestKey)
            defaults.set("occupied", forKey: self.resultKey)
            return nil
        }
        let journal = Journal(group: requested, device: device, inode: inode)
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        let descriptor = open(journalURL.path, O_RDONLY)
        if descriptor >= 0 { _ = fsync(descriptor); close(descriptor) }
        do {
            if let mover { try mover(source, destination) }
            else if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        } catch {
            if !fm.fileExists(atPath: source.path), self.matches(destination, journal: journal) {
                self.commit(group, journal: journalURL, defaults: defaults)
                return group
            }
            guard self.matches(source, journal: journal) else { throw error }
            try? fm.removeItem(at: journalURL)
            defaults.removeObject(forKey: self.requestKey)
            defaults.set("move", forKey: self.resultKey)
            return nil
        }
        guard !fm.fileExists(atPath: source.path), self.matches(destination, journal: journal) else { throw CocoaError(.fileReadCorruptFile) }
        self.commit(group, journal: journalURL, defaults: defaults)
        return group
    }
}
