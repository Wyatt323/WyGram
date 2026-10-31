import Foundation

struct ApplicationDataStorage {
    static let selectionKey = "wygram.applicationDataStorage"

    let baseURL: URL
    let sharedGroupIdentifier: String?

    enum StorageError: LocalizedError {
        case previousSharedStorageUnavailable
        case directoryUnavailable

        var errorDescription: String? {
            switch self {
            case .previousSharedStorageUnavailable:
                return "无法访问之前使用的数据目录。请恢复原有签名的共享权限后重新打开应用。已有数据没有被移动或删除。"
            case .directoryUnavailable:
                return "无法准备应用数据目录。请检查可用空间和签名权限后重新打开应用。"
            }
        }
    }

    static func resolve(bundleIdentifier: String) throws -> ApplicationDataStorage {
        let fileManager = FileManager.default
        let groupIdentifier = "group.\(bundleIdentifier)"
        let sharedDirectory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        let supportDirectory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try self.resolve(
            sharedDirectory: sharedDirectory,
            sharedGroupIdentifier: groupIdentifier,
            localDirectory: supportDirectory.appendingPathComponent("WyGram", isDirectory: true),
            defaults: .standard,
            fileManager: fileManager
        )
    }

    static func resolve(sharedDirectory: URL?, sharedGroupIdentifier: String, localDirectory: URL, defaults: UserDefaults, fileManager: FileManager = .default) throws -> ApplicationDataStorage {
        let previousSelection = defaults.string(forKey: self.selectionKey)
        let hasLocalData = fileManager.fileExists(atPath: localDirectory.appendingPathComponent("telegram-data/accounts-metadata").path)

        // Keep the selected store across launches and signing changes. Never
        // silently replace a previously shared account database with an empty one.
        if previousSelection == "local" || (previousSelection == nil && hasLocalData) {
            return try self.localStorage(directory: localDirectory, defaults: defaults, fileManager: fileManager)
        }

        if let sharedDirectory = sharedDirectory {
            do {
                try self.prepare(directory: sharedDirectory, fileManager: fileManager)
                defaults.set("shared", forKey: self.selectionKey)
                return ApplicationDataStorage(baseURL: sharedDirectory, sharedGroupIdentifier: sharedGroupIdentifier)
            } catch {
                if previousSelection == "shared" {
                    throw StorageError.previousSharedStorageUnavailable
                }
            }
        } else if previousSelection == "shared" {
            throw StorageError.previousSharedStorageUnavailable
        }

        return try self.localStorage(directory: localDirectory, defaults: defaults, fileManager: fileManager)
    }

    private static func localStorage(directory: URL, defaults: UserDefaults, fileManager: FileManager) throws -> ApplicationDataStorage {
        try self.prepare(directory: directory, fileManager: fileManager)
        defaults.set("local", forKey: self.selectionKey)
        return ApplicationDataStorage(baseURL: directory, sharedGroupIdentifier: nil)
    }

    private static func prepare(directory: URL, fileManager: FileManager) throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard fileManager.isWritableFile(atPath: directory.path) else {
                throw StorageError.directoryUnavailable
            }
        } catch {
            throw StorageError.directoryUnavailable
        }
    }
}
