// Adapted from RegramDev/Regram-ios, acb65027922c1f76818309b21ae1996754a29a94.
// MARK: WyGram — one durable Keychain record for the certificate, password and name.
import Foundation

struct WGUpdateIdentity: Codable {
    let p12: Data
    let password: String
    // Optional so certificates imported by b34593 remain readable.
    let name: String?

    static func load() -> WGUpdateIdentity? {
        guard let data = WGUpdateKeychain.read("identity"),
              let identity = try? JSONDecoder().decode(WGUpdateIdentity.self, from: data),
              !identity.p12.isEmpty else { return nil }
        return identity
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return String(data: WGUpdateKeychain.read("certificate-name") ?? Data(), encoding: .utf8) ?? ""
    }
}
