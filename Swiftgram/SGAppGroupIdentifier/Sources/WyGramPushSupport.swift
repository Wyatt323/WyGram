import Foundation

// The provisioning profile and XML signature are discovery hints, not proof of
// permission. Every group still has to pass the system's container lookup.
public struct WyGramPushCapabilities {
    public let environment: String?
    public let groups: [String]
    public let applicationIdentifier: String?

    public init(entitlements: [String: Any]) {
        let environment = entitlements["aps-environment"] as? String
        self.environment = ["production", "development"].contains(environment ?? "") ? environment : nil
        self.groups = ((entitlements["com.apple.security.application-groups"] as? [String]) ?? []).filter {
            $0.hasPrefix("group.") && !$0.contains("*") && !$0.contains("/") && !$0.contains("..")
        }.sorted()
        self.applicationIdentifier = entitlements["application-identifier"] as? String
    }

    public static func profileEntitlements(_ data: Data) -> [String: Any] {
        guard data.count <= 4 * 1024 * 1024,
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound ..< end.upperBound), format: nil) as? [String: Any]
        else { return [:] }
        return plist["Entitlements"] as? [String: Any] ?? [:]
    }

    public static func signedEntitlements(_ data: Data) -> [String: Any] {
        func number(_ offset: Int, big: Bool = false) -> UInt32? {
            guard offset >= 0, offset <= data.count - 4 else { return nil }
            let bytes = data[offset ..< offset + 4]
            return big ? bytes.reduce(0) { ($0 << 8) | UInt32($1) } : bytes.reversed().reduce(0) { ($0 << 8) | UInt32($1) }
        }
        guard number(0) == 0xfeedfacf, let count = number(16), count < 65536 else { return [:] }
        var offset = 32
        for _ in 0 ..< count {
            guard let command = number(offset), let size = number(offset + 4), size >= 8,
                  Int(size) <= data.count - offset else { return [:] }
            if command == 0x1d, size >= 16, let start = number(offset + 8), let length = number(offset + 12) {
                let start = Int(start), length = Int(length)
                guard length >= 12, start <= data.count - length,
                      number(start, big: true) == 0xfade0cc0,
                      let blobLength = number(start + 4, big: true), Int(blobLength) <= length,
                      let entries = number(start + 8, big: true), Int(entries) <= (length - 12) / 8 else { return [:] }
                for index in 0 ..< Int(entries) {
                    guard let relative = number(start + 16 + index * 8, big: true), Int(relative) <= length - 8 else { continue }
                    let blob = start + Int(relative)
                    guard number(blob, big: true) == 0xfade7171, let blobSize = number(blob + 4, big: true),
                          blobSize >= 8, Int(blobSize) <= length - Int(relative) else { continue }
                    if let value = try? PropertyListSerialization.propertyList(from: data.subdata(in: blob + 8 ..< blob + Int(blobSize)), format: nil) as? [String: Any] { return value }
                }
                return [:]
            }
            offset += Int(size)
        }
        return [:]
    }

    public static func enclosingApplication(_ bundle: Bundle = .main) -> Bundle {
        guard bundle.bundleURL.pathExtension == "appex" else { return bundle }
        return Bundle(url: bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) ?? bundle
    }

    public static func load(_ bundle: Bundle = .main) -> WyGramPushCapabilities {
        var values: [String: Any] = [:]
        if let profile = try? Data(contentsOf: bundle.bundleURL.appendingPathComponent("embedded.mobileprovision")) {
            values = self.profileEntitlements(profile)
        }
        if let executable = bundle.executableURL, let data = try? Data(contentsOf: executable, options: .mappedIfSafe) {
            values.merge(self.signedEntitlements(data)) { _, signed in signed }
        }
        return WyGramPushCapabilities(entitlements: values)
    }

    public static func sandbox(defaultValue: Bool) -> Bool {
        switch self.load(self.enclosingApplication()).environment {
        case "development": return true
        case "production": return false
        default: return defaultValue
        }
    }
}

public struct WyGramPushDirectory {
    public let groupIdentifier: String
    public let url: URL

    public static func resolve(bundleIdentifier: String, groups: [String], container: (String) -> URL?) -> WyGramPushDirectory? {
        guard !bundleIdentifier.isEmpty, !bundleIdentifier.contains(".."),
              bundleIdentifier.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").inverted) == nil else { return nil }
        let canonical = "group." + bundleIdentifier
        let candidates = [canonical] + groups.sorted().filter { $0 != canonical }
        for group in candidates where group.hasPrefix("group.") && !group.contains("*") && !group.contains("/") && !group.contains("..") {
            if let root = container(group) {
                return WyGramPushDirectory(groupIdentifier: group, url: root.appendingPathComponent("WyGramNotificationBridge", isDirectory: true).appendingPathComponent(bundleIdentifier, isDirectory: true))
            }
        }
        return nil
    }

    public static func current() -> WyGramPushDirectory? {
        let main = WyGramPushCapabilities.enclosingApplication()
        guard let identifier = main.bundleIdentifier else { return nil }
        let mainGroups = WyGramPushCapabilities.load(main).groups
        let ownGroups = WyGramPushCapabilities.load().groups
        let groups = Bundle.main.bundleURL.pathExtension == "appex" && !ownGroups.isEmpty ? mainGroups.filter { ownGroups.contains($0) } : mainGroups
        return self.resolve(bundleIdentifier: identifier, groups: groups, container: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) })
    }
}

public struct WyGramPushBridgeAccount: Codable {
    public let recordId: Int64
    public let keyId: Data
    public let key: Data
    public init(recordId: Int64, keyId: Data, key: Data) {
        self.recordId = recordId; self.keyId = keyId; self.key = key
    }
}

public enum WyGramPushBridge {
    public static func write(_ account: WyGramPushBridgeAccount, directory: URL) throws {
        guard account.keyId.count == 8, account.key.count == 256 else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("account-\(account.recordId).json")
        try JSONEncoder().encode(account).write(to: path, options: .atomic)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: path.path)
    }

    public static func accounts(directory: URL) -> [WyGramPushBridgeAccount] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])) ?? []
        return files.prefix(100).compactMap { file in
            guard file.lastPathComponent.hasPrefix("account-"), file.pathExtension == "json",
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: file), data.count < 8192,
                  let account = try? JSONDecoder().decode(WyGramPushBridgeAccount.self, from: data), account.keyId.count == 8, account.key.count == 256, file.lastPathComponent == "account-\(account.recordId).json" else { return nil }
            return account
        }
    }

    public static func retain(recordIds: Set<Int64>, directory: URL) {
        for account in self.accounts(directory: directory) where !recordIds.contains(account.recordId) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("account-\(account.recordId).json"))
        }
    }
}

// Never persist device tokens, message text, API credentials or raw error text.
public enum WyGramPushStatus {
    private static let prefix = "wygram.push."
    public static func record(_ stage: String, value: String, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: self.prefix + stage)
        defaults.set(Date().timeIntervalSince1970, forKey: self.prefix + stage + ".time")
    }
    public static func value(_ stage: String, defaults: UserDefaults = .standard) -> String? { defaults.string(forKey: self.prefix + stage) }
    public static func date(_ stage: String, defaults: UserDefaults = .standard) -> Date? {
        let value = defaults.double(forKey: self.prefix + stage + ".time")
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }
    public static func safeError(_ code: String) -> String {
        guard !code.isEmpty, code.count <= 80, code.rangeOfCharacter(from: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_").inverted) == nil else { return "REQUEST_FAILED" }
        return code
    }
    public static func received(directory: URL, value: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let event: [String: Any] = ["time": Date().timeIntervalSince1970, "result": value]
        if let data = try? JSONSerialization.data(withJSONObject: event) { try? data.write(to: directory.appendingPathComponent("last-received.json"), options: .atomic) }
    }
    public static func lastReceived(directory: URL) -> Date? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("last-received.json")), data.count < 4096,
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let time = event["time"] as? Double else { return nil }
        return Date(timeIntervalSince1970: time)
    }
}
