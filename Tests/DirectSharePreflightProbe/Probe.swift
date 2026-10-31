import Foundation
import Darwin
import SGAppGroupIdentifier

@main struct Probe {
    static var checks: [[String: Any]] = []
    static func check(_ name: String, _ value: Bool) { checks.append(["name": name, "passed": value]); print("\(value ? "PASS" : "FAIL") \(name)") }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wygram-preflight-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func group(_ name: String) throws -> WyGramDirectShare.Group {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return .init(identifier: "group.wygram.fixture", url: url)
        }
        func contents(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }
        do {
            let real = try group("root-alias-target")
            let alias = root.appendingPathComponent("os-container-alias")
            try fm.createSymbolicLink(at: alias, withDestinationURL: real.url)
            let input = WyGramDirectShare.Group(identifier: real.identifier, url: alias)
            let candidates = WyGramDirectShare.setupGroups([input])
            check("trusted-container-root-alias-can-be-prepared", candidates.count == 1)
            check("checking-alias-leaves-no-test-files", contents(real.url).isEmpty)
        }
        do {
            let parent = try group("root-readonly-owned-namespace-writable")
            let namespace = parent.url.appendingPathComponent("WyGramAccounts", isDirectory: true)
            try fm.createDirectory(at: namespace, withIntermediateDirectories: false)
            defer { _ = chmod(parent.url.path, 0o700) }
            precondition(chmod(parent.url.path, 0o500) == 0)
            check("fixture-root-writable-hint-is-false", !fm.isWritableFile(atPath: parent.url.path))
            let file = namespace.appendingPathComponent("actual-write-fixture")
            try Data("TEST".utf8).write(to: file)
            check("fixture-owned-namespace-actually-writable", fm.fileExists(atPath: file.path))
            try fm.removeItem(at: file)
            let candidates = WyGramDirectShare.setupGroups([parent])
            check("writable-namespace-works-with-readonly-container-root", candidates.count == 1)
            check("namespace-check-leaves-no-test-files", contents(namespace).isEmpty)
        }
        #if !BASELINE
        do {
            let container = try group("normal-root")
            let before = contents(container.url)
            let result = WyGramDirectShare.setupChecks([container])
            check("normal-root-passes-real-io", result.count == 1 && result[0].available && result[0].diagnostic == "ready(0)")
            check("root-probe-creates-no-account-or-leftovers", contents(container.url) == before)
        }
        do {
            let container = try group("readonly-all")
            defer { _ = chmod(container.url.path, 0o700) }
            precondition(chmod(container.url.path, 0o500) == 0)
            let result = WyGramDirectShare.setupChecks([container])[0]
            check("real-write-denial-is-not-bypassed", !result.available && result.stage == "probe-mkdir" && [EACCES, EPERM, EROFS].contains(result.code))
            check("write-denial-has-no-leftovers", contents(container.url).isEmpty)
        }
        do {
            let container = try group("namespace-file")
            let file = container.url.appendingPathComponent("WyGramAccounts")
            try Data("OTHER DATA".utf8).write(to: file)
            let result = WyGramDirectShare.setupChecks([container])[0]
            check("namespace-file-reports-exact-type-error", !result.available && result.stage == "namespace-type" && result.code == ENOTDIR)
            check("namespace-file-not-overwritten", try Data(contentsOf: file) == Data("OTHER DATA".utf8))
        }
        do {
            let container = try group("namespace-link")
            let outside = try group("namespace-link-outside")
            try fm.createSymbolicLink(at: container.url.appendingPathComponent("WyGramAccounts"), withDestinationURL: outside.url)
            let result = WyGramDirectShare.setupChecks([container])[0]
            check("namespace-link-remains-rejected", !result.available && result.stage == "namespace-type")
            check("namespace-link-target-is-untouched", contents(outside.url).isEmpty)
        }
        do {
            let missing = root.appendingPathComponent("missing")
            let result = WyGramDirectShare.setupChecks([.init(identifier: "group.fixture", url: missing)])[0]
            check("missing-system-container-reports-enoent", !result.available && result.stage == "container-stat" && result.code == ENOENT)
            check("missing-system-container-not-created", !fm.fileExists(atPath: missing.path))
        }
        do {
            let container = try group("root-file")
            try fm.removeItem(at: container.url)
            try Data("ROOT FILE".utf8).write(to: container.url)
            let result = WyGramDirectShare.setupChecks([container])[0]
            check("non-directory-root-refused", !result.available && result.stage == "container-type" && result.code == ENOTDIR)
        }
        do {
            let real = try group("alias-migration")
            let alias = root.appendingPathComponent("migration-os-alias")
            try fm.createSymbolicLink(at: alias, withDestinationURL: real.url)
            let container = WyGramDirectShare.Group(identifier: real.identifier, url: alias)
            let local = root.appendingPathComponent("alias-local")
            let source = local.appendingPathComponent("telegram-data")
            try fm.createDirectory(at: source.appendingPathComponent("accounts-metadata"), withIntermediateDirectories: true)
            let key = Data(repeating: 0x51, count: 48)
            try key.write(to: source.appendingPathComponent(".tempkey"))
            var before = stat(); precondition(lstat(source.path, &before) == 0)
            let defaults = UserDefaults(suiteName: "app.wygram.preflight." + UUID().uuidString)!
            defaults.set("local", forKey: WyGramDirectShare.selectionKey)
            let candidate = WyGramDirectShare.setupGroups([container])[0]
            _ = WyGramDirectShare.request(group: candidate, defaults: defaults)
            let selected = try WyGramDirectShare.performRequestedTransition(localDirectory: local, groups: [container], defaults: defaults)!
            let target = selected.accountURL.appendingPathComponent("telegram-data")
            var after = stat(); precondition(lstat(target.path, &after) == 0)
            check("alias-migration-still-uses-exclusive-whole-store-rename", before.st_ino == after.st_ino && !fm.fileExists(atPath: source.path))
            check("alias-migration-keeps-key-bytes", try Data(contentsOf: target.appendingPathComponent(".tempkey")) == key)
            let inbox = WyGramShareInbox(directory: alias.appendingPathComponent("WyGramShareInbox/app.wygram.fixture"))
            inbox.publishAccountStorage(group: selected.accountURL)
            let found = WyGramDirectShare.sharedAccountGroup(groups: [container], bundleIdentifier: "app.wygram.fixture")
            check("alias-main-and-extension-resolve-same-account", found?.accountURL == selected.accountURL && WyGramShareInbox.canUseSharedAccount(group: selected.accountURL, inboxes: [inbox]))
            check("probe-diagnostics-contain-no-paths-or-account-identifiers", WyGramDirectShare.setupChecks([container]).allSatisfy { !$0.diagnostic.contains(root.path) && !$0.diagnostic.contains("group.") && !$0.diagnostic.contains("/") })
        }
        #endif
        let report: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks, "scope": "Actual production storage checks, POSIX permissions and filesystem aliases with constructed data. Alias/root-write mismatch fixtures reproduce concrete preflight bugs; they do not prove the phone has the same filesystem cause or signed App Group rights."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        if report["passed"] as? Bool != true { exit(1) }
    }
}
