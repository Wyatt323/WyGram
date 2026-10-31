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
        var record: [String: Any] = ["group": group.identifier, "device": Int64(s.st_dev), "inode": UInt64(s.st_ino)]
        if let path = group.accountRelativePath { record["path"] = path }
        try JSONSerialization.data(withJSONObject: record).write(to: local.appendingPathComponent(".wygram-direct-share-transition.json"))
    }
    static func snapshot(_ url: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return result }
        for case let child as URL in enumerator {
            if (try? child.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { result[String(child.path.dropFirst(url.path.count+1))] = try! Data(contentsOf: child) }
        }
        return result
    }
    static func main() throws {
        let fm = FileManager.default
        // Construct only the Mach-O entitlement sections read by the production
        // parser. These are parser fixtures, not valid signatures/OS permissions.
        func executable(groups: [String]?) throws -> Data {
            let plist = try PropertyListSerialization.data(fromPropertyList: groups.map { ["com.apple.security.application-groups": $0] } ?? [:], format: .xml, options: 0)
            func integers(_ values: [UInt32], big: Bool = false) -> Data {
                var result = Data()
                for value in values { var n = big ? value.bigEndian : value.littleEndian; withUnsafeBytes(of: &n) { result.append(contentsOf: $0) } }
                return result
            }
            let length = UInt32(28 + plist.count)
            return integers([0xfeedfacf, 0x0100000c, 0, 2, 1, 16, 0, 0, 0x1d, 16, 48, length]) + integers([0xfade0cc0, length, 1, 5, 20, 0xfade7171, UInt32(8 + plist.count)], big: true) + plist
        }
        let mainExecutable = try executable(groups: ["group.wygram.fixture", "group.main-only"])
        check("matching-signed-group-discovered", WyGramDirectShare.commonSignedGroups(mainExecutable: mainExecutable, shareExecutable: try executable(groups: ["group.wygram.fixture", "group.share-only"])) == Set(["group.wygram.fixture"]))
        check("mismatched-signed-groups-refused", WyGramDirectShare.commonSignedGroups(mainExecutable: mainExecutable, shareExecutable: try executable(groups: ["group.other"])).isEmpty)
        check("profile-only-share-permission-not-inferred", WyGramDirectShare.commonSignedGroups(mainExecutable: mainExecutable, shareExecutable: try executable(groups: nil)).isEmpty)
        check("unsigned-main-permission-not-inferred", WyGramDirectShare.commonSignedGroups(mainExecutable: Data(), shareExecutable: mainExecutable).isEmpty)
        check("malformed-share-signature-refused", WyGramDirectShare.commonSignedGroups(mainExecutable: mainExecutable, shareExecutable: Data(mainExecutable.prefix(50))).isEmpty)
        let invalid = try executable(groups: ["group.*", "group../invalid", "invalid-group"])
        check("invalid-signed-group-names-refused", WyGramDirectShare.commonSignedGroups(mainExecutable: invalid, shareExecutable: invalid).isEmpty)
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
            let selected = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d)
            check("occupied-root-uses-separate-namespace-\(occupied)", selected?.accountRelativePath != nil)
            check("both-stores-preserved-\(occupied)", selected.map { snapshot($0.accountURL.appendingPathComponent("telegram-data")) == before } == true && snapshot(target) == other && d.string(forKey: WyGramDirectShare.resultKey) == "enabled")
        }
        do {
            let (local, occupied, d) = try fixture("occupied-first-free-second")
            let occupiedStore = occupied.url.appendingPathComponent("telegram-data")
            try fm.createDirectory(at: occupiedStore, withIntermediateDirectories: true)
            try Data("OTHER ACCOUNT".utf8).write(to: occupiedStore.appendingPathComponent("other"))
            let freeURL = occupied.url.deletingLastPathComponent().appendingPathComponent("free")
            try fm.createDirectory(at: freeURL, withIntermediateDirectories: true)
            let free = WyGramDirectShare.Group(identifier: "group.wygram.free", url: freeURL)
            let source = local.appendingPathComponent("telegram-data")
            let before = snapshot(source), originalInode = inode(source), other = snapshot(occupiedStore)
            check("setup-skips-occupied-first-candidate", WyGramDirectShare.vacantGroups([occupied, free]).map { $0.identifier } == [free.identifier])
            // A request saved by 1.1.0 may still name the first occupied group.
            _ = WyGramDirectShare.request(group: occupied, defaults: d)
            let selected = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [occupied, free], defaults: d)
            check("old-request-retries-free-common-group", selected?.identifier == free.identifier && d.string(forKey: WyGramDirectShare.groupKey) == free.identifier)
            check("alternative-group-keeps-directory-identity", inode(free.url.appendingPathComponent("telegram-data")) == originalInode && snapshot(free.url.appendingPathComponent("telegram-data")) == before)
            check("occupied-other-store-never-touched", snapshot(occupiedStore) == other)
        }
        do {
            let (local, group, d) = try fixture("shared-container-other-app-files")
            let other = group.url.appendingPathComponent("OtherApp/Documents")
            try fm.createDirectory(at: other, withIntermediateDirectories: true)
            try Data("OTHER APP FILE FIXTURE".utf8).write(to: other.appendingPathComponent("document.txt"))
            let original = snapshot(other)
            _ = WyGramDirectShare.request(group: group, defaults: d)
            let selected = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d)
            check("unused-account-slot-with-other-files-can-be-selected", selected?.identifier == group.identifier)
            performAppGroupUpgrades(appGroupPath: group.url.path, rootPath: group.url.appendingPathComponent("telegram-data").path)
            Thread.sleep(forTimeInterval: 0.25)
            check("startup-after-transition-preserves-other-app-files", snapshot(other) == original)
        }
        do {
            let (local, group, d) = try fixture("dangling-destination")
            let target = group.url.appendingPathComponent("telegram-data")
            try fm.createSymbolicLink(at: target, withDestinationURL: group.url.appendingPathComponent("missing"))
            check("dangling-destination-not-vacant", WyGramDirectShare.vacantGroups([group]).isEmpty)
            let before = snapshot(local.appendingPathComponent("telegram-data"))
            _ = WyGramDirectShare.request(group: group, defaults: d)
            let selected = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [group], defaults: d)
            check("dangling-root-uses-separate-namespace-without-touching-link", selected?.accountRelativePath != nil && selected.map { snapshot($0.accountURL.appendingPathComponent("telegram-data")) == before } == true && (try? fm.destinationOfSymbolicLink(atPath: target.path))?.hasSuffix("missing") == true)
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
            Thread.sleep(forTimeInterval: 0.25)
            check("startup-cleanup-keeps-pending-share-inbox", fm.fileExists(atPath: base.appendingPathComponent("WyGramShareInbox/fixture").path))
            check("startup-cleanup-keeps-notification-bridge", fm.fileExists(atPath: base.appendingPathComponent("WyGramNotificationBridge/fixture").path))
            check("startup-cleanup-keeps-account-directory", fm.fileExists(atPath: base.appendingPathComponent("telegram-data/fixture").path))
            check("startup-preserves-unowned-sibling-directory", fm.fileExists(atPath: base.appendingPathComponent("obsolete-legacy-data/fixture").path))
        }

        // Reproduce the unclickable setup: every common group already has a
        // root store. Use fresh app-owned locations, preserving all other stores.
        do {
            let (local, first, d) = try fixture("all-five-roots-occupied")
            var groups: [WyGramDirectShare.Group] = []
            for i in 0..<5 {
                let url = first.url.deletingLastPathComponent().appendingPathComponent("group-\(i)")
                try fm.createDirectory(at: url.appendingPathComponent("telegram-data/accounts-metadata"), withIntermediateDirectories: true)
                try Data(repeating: UInt8(i), count: 48).write(to: url.appendingPathComponent("telegram-data/.tempkey"))
                groups.append(.init(identifier: "group.fixture.\(i)", url: url))
            }
            let originals = groups.map { snapshot($0.url.appendingPathComponent("telegram-data")) }
            check("baseline-all-root-slots-occupied", WyGramDirectShare.vacantGroups(groups).isEmpty)
            let slots = WyGramDirectShare.setupGroups(groups)
            check("setup-action-available-despite-five-occupied-roots", slots.count == 5 && slots.allSatisfy { $0.accountRelativePath != nil })
            let source = local.appendingPathComponent("telegram-data"), original = snapshot(source), originalInode = inode(source)
            check("namespace-request-persisted", WyGramDirectShare.request(group: slots[0], defaults: d) && d.string(forKey: WyGramDirectShare.requestPathKey) == slots[0].accountRelativePath)
            let selected = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: groups, defaults: d)!
            check("namespace-store-inode-and-contents-preserved", inode(selected.accountURL.appendingPathComponent("telegram-data")) == originalInode && snapshot(selected.accountURL.appendingPathComponent("telegram-data")) == original)
            check("namespace-selection-persisted-as-relative-path", d.string(forKey: WyGramDirectShare.pathKey) == selected.accountRelativePath && !(d.string(forKey: WyGramDirectShare.pathKey) ?? "").hasPrefix("/"))
            check("all-other-root-stores-preserved", groups.enumerated().allSatisfy { snapshot($0.element.url.appendingPathComponent("telegram-data")) == originals[$0.offset] })
            let restarted = try ApplicationDataStorage.resolve(sharedDirectory: selected.url, sharedGroupIdentifier: selected.identifier, localDirectory: local, defaults: d)
            check("restart-uses-same-namespaced-parent", restarted.baseURL == selected.accountURL && restarted.sharedGroupIdentifier == selected.identifier)
            let inboxes = groups.map { WyGramShareInbox(directory: $0.url.appendingPathComponent("WyGramShareInbox/app.wygram.fixture")) }
            for inbox in inboxes { inbox.publishAccountStorage(group: restarted.baseURL) }
            let shared = WyGramDirectShare.sharedAccountGroup(groups: groups, bundleIdentifier: "app.wygram.fixture")
            check("extension-finds-main-exact-account-parent", shared?.accountURL == restarted.baseURL)
            check("extension-never-selects-other-root-store", !WyGramShareInbox.canUseSharedAccount(group: selected.url, inboxes: [inboxes[0]]))
            check("other-group-markers-remain-local", inboxes.dropFirst().allSatisfy { $0.mainUsesLocalStorage })
            let otherApp = WyGramShareInbox(directory: selected.url.appendingPathComponent("WyGramShareInbox/app.other.fixture"))
            check("other-app-marker-cannot-select-wygram-account", otherApp.sharedAccountLocation == nil && WyGramDirectShare.sharedAccountGroup(groups: groups, bundleIdentifier: "app.other.fixture") == nil)
            // Installation container changes do not invalidate relative locations.
            let relocated = selected.url.deletingLastPathComponent().appendingPathComponent("relocated")
            try fm.moveItem(at: selected.url, to: relocated)
            let relocatedGroup = WyGramDirectShare.Group(identifier: selected.identifier, url: relocated)
            let reopened = try ApplicationDataStorage.resolve(sharedDirectory: relocated, sharedGroupIdentifier: selected.identifier, localDirectory: local, defaults: d)
            check("changed-container-path-resolves-relative-account", reopened.baseURL == relocated.appendingPathComponent(selected.accountRelativePath!) && WyGramDirectShare.sharedAccountGroup(groups: [relocatedGroup], bundleIdentifier: "app.wygram.fixture")?.accountURL == reopened.baseURL)
            try fm.moveItem(at: reopened.baseURL, to: relocated.appendingPathComponent("offline-account"))
            do { _ = try ApplicationDataStorage.resolve(sharedDirectory: relocated, sharedGroupIdentifier: selected.identifier, localDirectory: local, defaults: d); check("missing-namespace-stops-empty-store-creation", false) }
            catch { check("missing-namespace-stops-empty-store-creation", !fm.fileExists(atPath: reopened.baseURL.path) && !fm.fileExists(atPath: source.path)) }
        }
        for moved in [false, true] {
            let (local, container, d) = try fixture("namespace-recovery-\(moved)")
            let group = WyGramDirectShare.setupGroups([container])[0]
            let source = local.appendingPathComponent("telegram-data"), destination = group.accountURL.appendingPathComponent("telegram-data")
            let before = snapshot(source)
            try fm.createDirectory(at: group.accountURL, withIntermediateDirectories: true)
            try journal(local, group, source: source)
            if moved { precondition(renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0) }
            let selected = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [container], defaults: d)
            check("namespace-recovery-exact-location-\(moved)", moved ? selected?.accountURL == group.accountURL && d.string(forKey: WyGramDirectShare.pathKey) == group.accountRelativePath : selected == nil)
            check("namespace-recovery-preserves-bytes-\(moved)", snapshot(moved ? destination : source) == before)
        }
        do {
            let (local, container, d) = try fixture("namespace-permissions-lost")
            let group = WyGramDirectShare.setupGroups([container])[0]
            let source = local.appendingPathComponent("telegram-data"), target = group.accountURL.appendingPathComponent("telegram-data")
            try fm.createDirectory(at: group.accountURL, withIntermediateDirectories: true)
            try journal(local, group, source: source)
            precondition(renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0)
            do { _ = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [], defaults: d); check("namespace-journal-kept-when-rights-lost", false) }
            catch { check("namespace-journal-kept-when-rights-lost", fm.fileExists(atPath: local.appendingPathComponent(".wygram-direct-share-transition.json").path) && !fm.fileExists(atPath: source.path)) }
            check("namespace-recovery-after-rights-restored", try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [container], defaults: d)?.accountURL == group.accountURL)
        }
        for path in ["../outside", "/tmp/outside", "WyGramAccounts/../outside", "WyGramAccounts/", "WyGramAccounts/not-a-uuid", "WyGramAccounts/" + UUID().uuidString + "/child"] {
            check("invalid-relative-path-refused-\(path)", !WyGramDirectShare.validAccountPath(path))
        }
        do {
            let (local, container, d) = try fixture("invalid-path")
            d.set("shared", forKey: WyGramDirectShare.selectionKey)
            d.set("../outside", forKey: WyGramDirectShare.pathKey)
            do { _ = try ApplicationDataStorage.resolve(sharedDirectory: container.url, sharedGroupIdentifier: container.identifier, localDirectory: local, defaults: d); check("invalid-persisted-path-stops-opening", false) }
            catch { check("invalid-persisted-path-stops-opening", fm.fileExists(atPath: local.appendingPathComponent("telegram-data/.tempkey").path)) }
            let inbox = WyGramShareInbox(directory: container.url.appendingPathComponent("WyGramShareInbox/app.wygram.fixture"))
            try inbox.prepare()
            for marker in ["shared:../outside", "shared:/tmp/outside", "shared:WyGramAccounts/no", "shared:", "garbage"] {
                try Data(marker.utf8).write(to: inbox.directory.appendingPathComponent("storage-mode"))
                check("invalid-marker-not-used-\(marker)", inbox.sharedAccountLocation == nil && WyGramDirectShare.sharedAccountGroup(groups: [container], bundleIdentifier: "app.wygram.fixture") == nil)
            }
        }
        do {
            let (local, container, d) = try fixture("namespace-symlink")
            let outside = local.appendingPathComponent("external")
            try fm.createDirectory(at: outside, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: container.url.appendingPathComponent("WyGramAccounts"), withDestinationURL: outside)
            check("symlink-namespace-not-eligible-for-setup", WyGramDirectShare.setupGroups([container]).isEmpty)
            let group = WyGramDirectShare.Group(identifier: container.identifier, url: container.url, accountRelativePath: "WyGramAccounts/" + UUID().uuidString)
            check("symlink-namespace-cannot-open-account", !WyGramDirectShare.usableAccount(group))
            _ = WyGramDirectShare.request(group: group, defaults: d)
            check("symlink-namespace-does-not-move-account", try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [container], defaults: d) == nil && fm.fileExists(atPath: local.appendingPathComponent("telegram-data/.tempkey").path) && snapshot(outside).isEmpty)
        }
        do {
            let (local, container, d) = try fixture("namespace-slot-occupied")
            let group = WyGramDirectShare.setupGroups([container])[0]
            try fm.createDirectory(at: group.accountURL, withIntermediateDirectories: true)
            try Data("OCCUPIED".utf8).write(to: group.accountURL.appendingPathComponent("keep"))
            let before = snapshot(group.accountURL)
            _ = WyGramDirectShare.request(group: group, defaults: d)
            let selected = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [container], defaults: d)
            check("occupied-namespace-slot-uses-new-slot", selected?.accountRelativePath != nil && selected?.accountRelativePath != group.accountRelativePath)
            check("occupied-namespace-slot-is-preserved", snapshot(group.accountURL) == before)
        }
        let report: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks, "scope": "Exact production transition and ApplicationDataStorage code with constructed directories and a real SQLite fixture; not Telegram accounts, iOS entitlements or LCSign device validation."]
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        if !checks.allSatisfy({ $0["passed"] as? Bool == true }) { exit(1) }
    }
}
