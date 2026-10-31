import Foundation
import SwiftSignalKit
import TelegramCore

public struct SGStatus: Equatable, Codable {
    public var status: Int64
    
    public static var `default`: SGStatus {
        return SGStatus(status: 2)
    }
    
    public init(status: Int64) {
        self.status = max(2, status)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        // Existing Swiftgram installs may have a cached free-tier status.
        // WyGram's local Pro features are available to every user.
        self.status = max(2, try container.decodeIfPresent(Int64.self, forKey: "status") ?? 2)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(max(2, self.status), forKey: "status")
    }
}

public func updateSGStatusInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (SGStatus) -> SGStatus) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.sgStatus, { entry in
            let currentSettings: SGStatus
            if let entry = entry?.get(SGStatus.self) {
                currentSettings = entry
            } else {
                currentSettings = SGStatus.default
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}
