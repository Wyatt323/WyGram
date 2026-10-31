import Foundation
import Darwin
import SQLite3
import SGAppGroupIdentifier

@main struct Probe {
    static var checks: [[String: Any]] = []
    static func check(_ name: String, _ value: Bool) { checks.append(["name": name, "passed": value]); print("\(value ? "PASS" : "FAIL") \(name)") }
    static func inode(_ url: URL) -> UInt64 { var s = stat(); precondition(lstat(url.path, &s) == 0); return UInt64(s.st_ino) }
    static func journal(_ local: URL, _ group: WyGramDirectShare.Group, source: URL) throws {
        var s = stat(); precondition(lstat(source.path, &s) == 0)
        let record: [String: Any] = ["group": group.identifier, "device": Int64(s.st_dev), "inode": UInt64(s.st_ino)]
        try JSONSerialization.data(withJSONObject: record).write(to: local.appendingPathComponent(".wygram-direct-share-transition.json"))
    }
    static func snapshot(_ url: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        for case let child as URL in FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])! {
            if (try? child.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { result[String(child.path.dropFirst(url.path.count+1))] = try! Data(contentsOf: child) }
        }
        return result
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wygram-direct-share-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func fixture(_ name: String) throws -> (URL, WyGramDirectShare.Group, UserDefaults) {
            let base = root.appendingPathComponent(name)
            let local = base.appendingPathComponent("local"), shared = base.appendingPathComponent("shared")
            try fm.createDirectory(at: local.appendingPathComponent("telegram-data/accounts-metadata"), withIntermediateDirectories: true)
            try fm.createDirectory(at: local.appendingPathComponent("telegram-data/account-1/wygram-message-history"), withIntermediateDirectories: true)
            try fm.createDirectory(at: shared, withIntermediateDirectories: true)
            try Data(repeating: 0x42, count: 48).write(to: local.appendingPathComponent("telegram-data/.tempkey"))
            try Data("LOCAL RETAINED PHOTO FIXTURE".utf8).write(to: local.appendingPathComponent("telegram-data/account-1/wygram-message-history/retained-photo-1.jpg"))
            let sql = local.appendingPathComponent("telegram-data/accounts-metadata/test.sqlite").path
            var db: OpaquePointer?; precondition(sqlite3_open(sql, &db) == SQLITE_OK)
            precondition(sqlite3_exec(db, "CREATE TABLE records(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO records VALUES(1,'WyGram fixture');", nil, nil, nil) == SQLITE_OK)
            sqlite3_close(db)
            let defaults = UserDefaults(suiteName: "app.wygram.test." + UUID().uuidString)!
            defaults.set("local", forKey: WyGramDirectShare.selectionKey)
            return (local, .init(identifier: "group.wygram.fixture", url: shared), defaults)
        }
        do {
            let (local, group, d) = try fixture("opt-in")
            let before = snapshot(local.appendingPathComponent("telegram-data"))
            check("no-automatic-migration", try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d) == nil)
            check("unrequested-account-intact", snapshot(local.appendingPathComponent("telegram-data")) == before)
            _ = WyGramDirectShare.request(group: group, defaults: d)
            check("missing-permission-does-not-move", try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [], defaults: d) == nil)
            check("permission-failure-keeps-account", snapshot(local.appendingPathComponent("telegram-data")) == before && d.string(forKey: WyGramDirectShare.resultKey) == "permissions")
            let store = try ApplicationDataStorage.resolve(sharedDirectory: nil, sharedGroupIdentifier: group.identifier, localDirectory: local, defaults: d)
            check("failed-opt-in-still-opens-original-local-store", store.baseURL == local && store.sharedGroupIdentifier == nil)
        }
        do {
            let (local, group, d) = try fixture("success")
            let source = local.appendingPathComponent("telegram-data"), destination = group.url.appendingPathComponent("telegram-data")
            let before = snapshot(source), originalInode = inode(source)
            check("request-persisted", WyGramDirectShare.request(group: group, defaults: d))
            let selected = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d)
            check("atomic-transition-selects-exact-group", selected?.identifier == group.identifier)
            check("same-directory-inode-no-copy", inode(destination) == originalInode && !fm.fileExists(atPath: source.path))
            check("all-records-key-and-retained-photos-preserved", snapshot(destination) == before)
            check("relative-retained-photo-path-resolves", fm.fileExists(atPath: destination.appendingPathComponent("account-1/wygram-message-history/retained-photo-1.jpg").path))
            var db: OpaquePointer?, statement: OpaquePointer?
            let opened = sqlite3_open(destination.appendingPathComponent("accounts-metadata/test.sqlite").path, &db) == SQLITE_OK
            let prepared = sqlite3_prepare_v2(db, "SELECT name FROM records WHERE id=1", -1, &statement, nil) == SQLITE_OK
            check("sqlite-reopens-with-original-record", opened && prepared && sqlite3_step(statement) == SQLITE_ROW && String(cString: sqlite3_column_text(statement, 0)) == "WyGram fixture")
            sqlite3_finalize(statement); sqlite3_close(db)
            check("selection-committed-without-pending-request", d.string(forKey: WyGramDirectShare.selectionKey) == "shared" && d.string(forKey: WyGramDirectShare.groupKey) == group.identifier && d.string(forKey: WyGramDirectShare.requestKey) == nil)
            let store = try ApplicationDataStorage.resolve(sharedDirectory: group.url, sharedGroupIdentifier: group.identifier, localDirectory: local, defaults: d)
            check("restart-resolves-shared-store", store.baseURL == group.url && store.sharedGroupIdentifier == group.identifier)
            check("repeat-start-does-not-move-again", try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d) == nil)
            let inbox = WyGramShareInbox(directory: group.url.appendingPathComponent("WyGramShareInbox/app.wygram.fixture"))
            let other = WyGramShareInbox(directory: local.appendingPathComponent("WyGramShareInbox/app.wygram.fixture"))
            inbox.publishAccountStorage(group: group.url); other.publishAccountStorage(group: group.url)
            check("only-actual-account-group-published-shared", !inbox.mainUsesLocalStorage && other.mainUsesLocalStorage)
            check("native-share-account-eligible-after-transition", WyGramShareInbox.canUseSharedAccount(group: group.url, inboxes: [inbox]))
        }
        for occupied in [false, true] {
            let (local, group, d) = try fixture("occupied-\(occupied)")
            let target = group.url.appendingPathComponent("telegram-data")
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            if occupied { try Data("OTHER ACCOUNT".utf8).write(to: target.appendingPathComponent("other")) }
            let before = snapshot(local.appendingPathComponent("telegram-data")), other = snapshot(target)
            _ = WyGramDirectShare.request(group: group, defaults: d)
            check("occupied-destination-refused-\(occupied)", try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d) == nil)
            check("both-stores-preserved-\(occupied)", snapshot(local.appendingPathComponent("telegram-data")) == before && snapshot(target) == other && d.string(forKey: WyGramDirectShare.resultKey) == "occupied")
        }
        do {
            let (local, group, d) = try fixture("move-denied")
            let before = snapshot(local.appendingPathComponent("telegram-data"))
            _ = WyGramDirectShare.request(group: group, defaults: d)
            let result = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d, mover: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            check("move-failure-returns-to-local", result == nil && d.string(forKey: WyGramDirectShare.selectionKey) == "local")
            check("move-failure-keeps-every-original-byte", snapshot(local.appendingPathComponent("telegram-data")) == before)
            check("failed-transition-cleans-journal-and-request", !fm.fileExists(atPath: local.appendingPathComponent(".wygram-direct-share-transition.json").path) && d.string(forKey: WyGramDirectShare.requestKey) == nil)
        }
        do {
            let (local, group, d) = try fixture("destination-race")
            _ = WyGramDirectShare.request(group: group, defaults: d)
            let result = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d, mover: { source, target in
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            })
            check("exclusive-rename-refuses-racing-destination", result == nil && fm.fileExists(atPath: local.appendingPathComponent("telegram-data/.tempkey").path))
        }
        for moved in [false, true] {
            let (local, group, d) = try fixture("crash-\(moved)")
            let source = local.appendingPathComponent("telegram-data"), target = group.url.appendingPathComponent("telegram-data")
            let before = snapshot(source)
            try journal(local, group, source: source)
            if moved { precondition(renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0) }
            let result = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d)
            check("interrupted-transition-recovers-\(moved)", moved ? result?.identifier == group.identifier : result == nil)
            check("crash-recovery-keeps-original-bytes-\(moved)", snapshot(moved ? target : source) == before)
            check("crash-recovery-remembers-correct-selection-\(moved)", d.string(forKey: WyGramDirectShare.selectionKey) == (moved ? "shared" : "local"))
        }
        do {
            let (local, group, d) = try fixture("crash-permissions-lost")
            let source = local.appendingPathComponent("telegram-data"), target = group.url.appendingPathComponent("telegram-data")
            try journal(local, group, source: source)
            precondition(renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0)
            do { _ = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [], defaults: d); check("lost-permissions-stop-empty-store-initialisation", false) }
            catch { check("lost-permissions-stop-empty-store-initialisation", !fm.fileExists(atPath: source.path) && fm.fileExists(atPath: target.appendingPathComponent(".tempkey").path)) }
            check("journal-survives-unavailable-destination", fm.fileExists(atPath: local.appendingPathComponent(".wygram-direct-share-transition.json").path))
            check("permissions-restored-resume-same-account", try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d)?.identifier == group.identifier)
        }
        do {
            let (local, group, d) = try fixture("bad-key")
            try Data([1]).write(to: local.appendingPathComponent("telegram-data/.tempkey"))
            _ = WyGramDirectShare.request(group: group, defaults: d)
            check("invalid-key-never-moved-or-regenerated", try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d) == nil && (try Data(contentsOf: local.appendingPathComponent("telegram-data/.tempkey"))) == Data([1]))
        }
        do {
            let (local, group, d) = try fixture("symlink")
            let source = local.appendingPathComponent("telegram-data"), outside = local.appendingPathComponent("outside")
            try fm.moveItem(at: source, to: outside); try fm.createSymbolicLink(at: source, withDestinationURL: outside)
            _ = WyGramDirectShare.request(group: group, defaults: d)
            check("symlink-store-refused", try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d) == nil && fm.fileExists(atPath: outside.appendingPathComponent(".tempkey").path))
        }
        do {
            let (local, group, d) = try fixture("corrupt-journal")
            try Data("invalid".utf8).write(to: local.appendingPathComponent(".wygram-direct-share-transition.json"))
            do { _ = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d); check("corrupt-journal-blocks-destructive-fallback", false) }
            catch { check("corrupt-journal-blocks-destructive-fallback", fm.fileExists(atPath: local.appendingPathComponent("telegram-data/.tempkey").path)) }
        }
        do {
            let base = root.appendingPathComponent("startup-cleanup")
            for directory in ["telegram-data", "Library", "WyGramShareInbox", "WyGramNotificationBridge", "obsolete-legacy-data"] {
                try fm.createDirectory(at: base.appendingPathComponent(directory), withIntermediateDirectories: true)
                try Data(directory.utf8).write(to: base.appendingPathComponent(directory + "/fixture"))
            }
            performAppGroupUpgrades(appGroupPath: base.path, rootPath: base.appendingPathComponent("telegram-data").path)
            for _ in 0..<200 {
                if !fm.fileExists(atPath: base.appendingPathComponent("obsolete-legacy-data").path) { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            check("startup-cleanup-keeps-pending-share-inbox", fm.fileExists(atPath: base.appendingPathComponent("WyGramShareInbox/fixture").path))
            check("startup-cleanup-keeps-notification-bridge", fm.fileExists(atPath: base.appendingPathComponent("WyGramNotificationBridge/fixture").path))
            check("startup-cleanup-keeps-account-directory", fm.fileExists(atPath: base.appendingPathComponent("telegram-data/fixture").path))
            check("startup-cleanup-still-removes-obsolete-directory", !fm.fileExists(atPath: base.appendingPathComponent("obsolete-legacy-data").path))
        }
        let report: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks, "scope": "Exact production transition and ApplicationDataStorage code with constructed directories and a real SQLite fixture; not Telegram accounts, iOS entitlements or LCSign device validation."]
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        if !checks.allSatisfy({ $0["passed"] as? Bool == true }) { exit(1) }
    }
}
